import CoreGraphics
import Foundation

public enum TileError: Error { case nothingLeft }

/// The Tiles step: the finished image cut into columns × rows of equal size. The first tile starts
/// at 0, the last ends at the edge, and neighbours share about `overlap` pixels (gaps when negative).
public enum TileStep {
    /// Row-major, top row first, origin top-left in pixel space.
    public static func rects(width: Int, height: Int, columns: Int, rows: Int, overlap: Int) throws -> [CGRect] {
        let xs = try spans(width, count: min(max(columns, 1), 100), overlap: overlap)
        let ys = try spans(height, count: min(max(rows, 1), 100), overlap: overlap)
        return ys.flatMap { y in xs.map { x in CGRect(x: x.start, y: y.start, width: x.size, height: y.size) } }
    }

    public static func cut(_ image: CGImage, columns: Int, rows: Int, overlap: Int) throws -> [CGImage] {
        try rects(width: image.width, height: image.height, columns: columns, rows: rows, overlap: overlap).map {
            guard let tile = image.cropping(to: $0) else { throw TileError.nothingLeft }
            return tile
        }
    }

    /// One axis: `size = min(length, ceil((length + (count − 1)·overlap) / count))`,
    /// tile i at `round(i·(length − size) / (count − 1))`.
    private static func spans(_ length: Int, count: Int, overlap: Int) throws -> [(start: Int, size: Int)] {
        let size = min(length, Int((Double(length + (count - 1) * overlap) / Double(count)).rounded(.up)))
        guard size >= 1 else { throw TileError.nothingLeft }
        return (0..<count).map { i in
            (count == 1 ? 0 : Int((Double(i * (length - size)) / Double(count - 1)).rounded()), size)
        }
    }
}

/// `{part}` labels for an input that yields several outputs: 1-based, zero-padded to the count's digits.
public enum PartLabels {
    public static func frames(_ count: Int) -> [String] { padded(count) }

    /// `row-column`, rows top to bottom, columns left to right.
    public static func tiles(rows: Int, columns: Int) -> [String] {
        padded(rows).flatMap { row in padded(columns).map { "\(row)-\($0)" } }
    }

    /// Frame-major `frame-row-column`; a single frame or a 1 × 1 grid drops its part, both single give none.
    public static func combined(frames: Int, rows: Int, columns: Int) -> [String] {
        let tiles = rows * columns > 1 ? tiles(rows: rows, columns: columns) : []
        guard frames > 1 else { return tiles }
        return tiles.isEmpty ? padded(frames) : padded(frames).flatMap { f in tiles.map { "\(f)-\($0)" } }
    }

    private static func padded(_ count: Int) -> [String] {
        guard count > 0 else { return [] }
        let width = String(count).count
        return (1...count).map { n in
            let digits = String(n)
            return String(repeating: "0", count: width - digits.count) + digits
        }
    }
}
