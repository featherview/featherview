import Testing
@testable import FeatherviewCore

@Suite struct PictureTransformTests {
    static let all: [OrientationChange] = [
        .rotate(.clockwise), .rotate(.counterClockwise), .flip(.horizontal), .flip(.vertical),
    ]

    /// Every sequence of 0–3 changes.
    static let sequences: [[OrientationChange]] = (1...3).reduce(into: [[]]) { result, length in
        result += result.filter { $0.count == length - 1 }.flatMap { seq in all.map { seq + [$0] } }
    }

    static func orientation(after changes: [OrientationChange], from start: Int = 1) -> Int {
        changes.reduce(start, OrientationRotator.next)
    }

    @Test func transformMatchesOrientationTables() {
        #expect(Self.sequences.count == 1 + 4 + 16 + 64)
        for seq in Self.sequences {
            #expect(PictureTransform(seq).orientation == Self.orientation(after: seq), "\(seq)")
        }
    }

    @Test func turnsAreNotWrapped() {
        #expect(PictureTransform(Array(repeating: .rotate(.clockwise), count: 3)).turns == 3)
        #expect(PictureTransform([.rotate(.counterClockwise)]).turns == -1)
    }

    @Test func rotateOnMirroredTurnsBack() {
        let transform = PictureTransform([.flip(.horizontal), .rotate(.clockwise)])
        #expect(transform.mirrored)
        #expect(transform.turns == -1)
    }

    /// A transform as changes: its quarter turns clockwise, then the mirror (`M^m ∘ R^t`).
    static func changes(of transform: PictureTransform) -> [OrientationChange] {
        Array(repeating: .rotate(.clockwise), count: ((transform.turns % 4) + 4) % 4)
            + (transform.mirrored ? [.flip(.horizontal)] : [])
    }

    @Test func tailIsWhatRemains() {
        for seq in Self.sequences {
            for k in 0...seq.count {
                let written = PictureTransform(Array(seq.prefix(k))).orientation
                let tail = PictureTransform(Array(seq.dropFirst(k)))
                #expect(Self.orientation(after: Self.changes(of: tail), from: written)
                    == Self.orientation(after: seq), "\(seq) split at \(k)")
            }
        }
    }
}
