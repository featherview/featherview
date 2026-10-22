import CoreGraphics
import Foundation
import Observation

/// Plays the animation on screen (spec "Animation"): once frame 0 shows (the model's image), decodes the
/// following frames in order off the main thread and hands each to the canvas at its due time through
/// `onFrame`, with no SwiftUI update per frame. Only pausing, stepping and a new file change what it observes.
@MainActor @Observable
public final class AnimationPlayer {
    /// 0 without an animation.
    public private(set) var frameCount = 0
    /// The frame shown while paused (0-based); nil while playing or without an animation.
    public private(set) var pausedFrame: Int?
    /// The frame on screen when it isn't the model's image; nil until playback first moves.
    @ObservationIgnored public private(set) var current: CGImage?
    /// Puts a frame on the canvas; set by the canvas.
    @ObservationIgnored public var onFrame: (CGImage) -> Void = { _ in }
    /// The file playing, nil when stopped.
    @ObservationIgnored public private(set) var url: URL?

    public var isPlaying: Bool { frameCount > 1 && pausedFrame == nil }

    @ObservationIgnored private let colorSpace: CGColorSpace?
    @ObservationIgnored private var delays: [Duration] = []
    @ObservationIgnored private var playback = Playback(frameCount: 1, playing: false)
    @ObservationIgnored private var source: Task<FrameSource, Error>?
    /// Decoded frames kept (`FrameStore.wanted`), and decodes running or done but not yet taken.
    @ObservationIgnored private var frames: [Int: CGImage] = [:]
    @ObservationIgnored private(set) var decodes: [Int: Task<CGImage, Error>] = [:]
    /// The decode asked for last: each waits for the one before, so `FrameSource` goes through the file in order.
    @ObservationIgnored private var lastDecode: Task<CGImage, Error>?
    /// Whether every frame fits the memory budget; known from the first frame decoded at the target.
    @ObservationIgnored private var keepsAll: Bool?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Bumped by everything that makes a decode on its way stale (stop, a step, a new target).
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var visible = true

    public init(colorSpace: CGColorSpace?) {
        self.colorSpace = colorSpace
    }

    /// `first` is frame 0 at `target`, already on screen.
    public func start(url: URL, animation: Animation, target: DecodeTarget, first: CGImage, playing: Bool) {
        stop()
        guard animation.frameCount > 1 else { return }
        self.url = url
        delays = animation.delays
        frameCount = animation.frameCount
        playback = Playback(frameCount: frameCount, playing: playing)
        pausedFrame = playing ? nil : 0
        open(target)
        keep(first, at: 0)
        play()
    }

    /// Synchronous: once it returns no frame of this file reaches the canvas.
    public func stop() {
        task?.cancel()
        task = nil
        generation += 1
        dropFrames()
        source = nil
        current = nil
        url = nil
        if frameCount != 0 { frameCount = 0 }
        if pausedFrame != nil { pausedFrame = nil }
    }

    /// A zoom change: the frames decode at `target` from now on, the frame shown stays the same.
    public func retarget(_ target: DecodeTarget) {
        guard url != nil else { return }
        task?.cancel()
        generation += 1
        dropFrames()
        open(target)
        // Frame 0 at the new target is the model's new image.
        if playback.frame == 0 { current = nil } else { showFrame(playback.frame) }
        play()
    }

    public func togglePlaying() {
        guard frameCount > 1 else { return }
        playback.togglePlaying()
        pausedFrame = playback.isPlaying ? nil : playback.frame
        if playback.isPlaying {
            play()
        } else {
            task?.cancel()
        }
    }

    /// ⌥→ / ⌥←: one frame on or back, pausing; false at either end.
    @discardableResult public func step(forward: Bool) -> Bool {
        guard frameCount > 1 else { return false }
        task?.cancel()
        generation += 1
        let moved = playback.step(forward: forward)
        // A held key steps faster than frames decode: the decodes left behind would never be taken.
        dropUnwanted()
        if pausedFrame != playback.frame { pausedFrame = playback.frame }
        if moved { showFrame(playback.frame) }
        return moved
    }

    /// Playback waits while the window is hidden (occluded or minimized) and goes on from the same frame.
    public func setVisible(_ visible: Bool) {
        guard visible != self.visible else { return }
        self.visible = visible
        if visible { play() } else { task?.cancel() }
    }

    private func open(_ target: DecodeTarget) {
        guard let url else { return }
        let colorSpace = colorSpace
        source = Task.detached(priority: .utility) { try FrameSource(url: url, target: target, colorSpace: colorSpace) }
    }

    private func dropFrames() {
        for decode in decodes.values { decode.cancel() }
        decodes = [:]
        lastDecode = nil
        frames = [:]
        keepsAll = nil
    }

    /// Runs playback from the frame shown; its delay counts from now.
    private func play() {
        task?.cancel()
        guard playback.isPlaying, visible, frameCount > 1 else { return }
        let generation = generation
        task = Task { [weak self] in
            var shownAt = ContinuousClock.now
            // Holds the player only while a frame is taken, so a player whose window closed goes away.
            while let delay = self?.decodeAhead(generation) {
                do { try await Task.sleep(until: shownAt + delay, clock: .continuous) } catch { return }
                guard await self?.advance(generation) == true else { return }
                // A late frame isn't skipped: its delay counts from when it showed.
                shownAt = .now
            }
        }
    }

    /// Starts decoding the frames due after the one shown; returns how long that one stays, nil once stale.
    private func decodeAhead(_ generation: Int) -> Duration? {
        guard isCurrent(generation) else { return nil }
        let shown = playback.frame
        for index in FrameStore.wanted(shown: shown, count: frameCount, keepsAll: keepsAll ?? false).dropFirst()
        where frames[index] == nil {
            _ = decode(index)
        }
        return delays[shown]
    }

    /// Shows the next frame; false once stale.
    private func advance(_ generation: Int) async -> Bool {
        guard isCurrent(generation) else { return false }
        let next = (playback.frame + 1) % frameCount
        let image: CGImage
        if let decoded = try? await fetch(next) {
            guard isCurrent(generation) else { return false }
            image = decoded
            playback.advance()
        } else {
            // A truncated file: play the frames that decode, then loop. With one good frame, stay on it.
            guard isCurrent(generation), next > 1, let first = await cut(to: next), isCurrent(generation) else { return false }
            image = first
        }
        show(image)
        return true
    }

    /// Keeps only the first `count` frames, playing again from frame 0; returns frame 0.
    private func cut(to count: Int) async -> CGImage? {
        let generation = generation
        frameCount = count
        delays = Array(delays.prefix(count))
        playback = Playback(frameCount: count, playing: true)
        for (index, decode) in decodes where index >= count { decode.cancel() }
        decodes = decodes.filter { $0.key < count }
        frames = frames.filter { $0.key < count }
        guard let first = try? await fetch(0), self.generation == generation else { return nil }
        return first
    }

    /// Decodes `index` at the current target and shows it, unless something newer came first.
    private func showFrame(_ index: Int) {
        let generation = generation
        Task {
            if let image = try? await fetch(index) {
                guard self.generation == generation else { return }
                show(image)
            } else if self.generation == generation, index > 0, index < frameCount {
                // Past the frames the file holds: it ends at the one before.
                frameCount = index
                delays = Array(delays.prefix(index))
                playback = Playback(frameCount: index, playing: false)
                while playback.frame < index - 1, playback.step(forward: true) {}
                pausedFrame = playback.frame
                showFrame(playback.frame)
            }
        }
    }

    private func show(_ image: CGImage) {
        dropUnwanted()
        current = image
        onFrame(image)
    }

    /// Keeps only the frames and decodes `FrameStore.wanted` for the frame shown.
    private func dropUnwanted() {
        let wanted = Set(FrameStore.wanted(shown: playback.frame, count: frameCount, keepsAll: keepsAll ?? false))
        frames = frames.filter { wanted.contains($0.key) }
        for (index, decode) in decodes where !wanted.contains(index) { decode.cancel() }
        decodes = decodes.filter { wanted.contains($0.key) }
    }

    private func fetch(_ index: Int) async throws -> CGImage {
        if let kept = frames[index] { return kept }
        let generation = generation
        let image = try await decode(index).value
        if self.generation == generation, index < frameCount { keep(image, at: index) }
        return image
    }

    private func keep(_ image: CGImage, at index: Int) {
        if keepsAll == nil { keepsAll = FrameStore.keepsAll(frameBytes: image.bytesPerRow * image.height, count: frameCount) }
        decodes[index] = nil
        frames[index] = image
    }

    private func decode(_ index: Int) -> Task<CGImage, Error> {
        if let running = decodes[index] { return running }
        let previous = lastDecode, source = source
        let decode = Task.detached(priority: .utility) {
            _ = await previous?.result
            try Task.checkCancellation()
            guard let source else { throw CancellationError() }
            return try await source.value.frame(index)
        }
        decodes[index] = decode
        lastDecode = decode
        return decode
    }

    private func isCurrent(_ generation: Int) -> Bool {
        !Task.isCancelled && self.generation == generation && url != nil
    }
}
