import CoreGraphics
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct SplitStepsTests {
    private func xs(_ rects: [CGRect]) -> [CGFloat] { rects.map(\.minX) }

    @Test func evenTiles() throws {
        let rects = try TileStep.rects(width: 1600, height: 900, columns: 2, rows: 2, overlap: 0)
        #expect(rects == [CGRect(x: 0, y: 0, width: 800, height: 450), CGRect(x: 800, y: 0, width: 800, height: 450),
                          CGRect(x: 0, y: 450, width: 800, height: 450), CGRect(x: 800, y: 450, width: 800, height: 450)])
    }

    @Test func oddWidthEqualTiles() throws {
        let rects = try TileStep.rects(width: 1601, height: 10, columns: 2, rows: 1, overlap: 0)
        #expect(rects.map(\.width) == [801, 801])
        #expect(xs(rects) == [0, 800])
        #expect(rects.last?.maxX == 1601)
    }

    @Test func overlapShared() throws {
        let rects = try TileStep.rects(width: 1000, height: 10, columns: 3, rows: 1, overlap: 50)
        #expect(rects.map(\.width) == [367, 367, 367])
        #expect(xs(rects) == [0, 317, 633])
        #expect(rects.last?.maxX == 1000)
    }

    @Test func negativeOverlapLeavesGaps() throws {
        let rects = try TileStep.rects(width: 1000, height: 10, columns: 2, rows: 1, overlap: -100)
        #expect(rects.map(\.width) == [450, 450])
        #expect(xs(rects) == [0, 550])
    }

    @Test func tooMuchNegativeOverlapThrows() {
        #expect(throws: TileError.nothingLeft) {
            try TileStep.rects(width: 100, height: 10, columns: 4, rows: 1, overlap: -40)
        }
    }

    @Test func oneByOneIsWholeImage() throws {
        #expect(try TileStep.rects(width: 640, height: 480, columns: 1, rows: 1, overlap: 30)
                == [CGRect(x: 0, y: 0, width: 640, height: 480)])
    }

    @Test func cutTopLeftIsTopLeft() throws {
        var source = RGBAImage(width: 4, height: 4)
        for y in 0..<2 { for x in 0..<2 { source[x, y] = (255, 0, 0, 255) } }
        let tiles = try TileStep.cut(try #require(source.makeCGImage()), columns: 2, rows: 2, overlap: 0)
        #expect(tiles.count == 4)
        let first = try #require(RGBAImage(tiles[0])), last = try #require(RGBAImage(tiles[3]))
        #expect(first.width == 2 && first.height == 2)
        #expect(first[0, 0] == (255, 0, 0, 255) && first[1, 1] == (255, 0, 0, 255))
        #expect(last[0, 0] == (0, 0, 0, 255))
    }

    @Test func frameLabelsPad() {
        #expect(PartLabels.frames(9) == (1...9).map(String.init))
        let twelve = PartLabels.frames(12)
        #expect(twelve.first == "01" && twelve.last == "12" && twelve.count == 12)
        #expect(PartLabels.frames(120).first == "001")
    }

    @Test func tileLabels() {
        #expect(PartLabels.tiles(rows: 2, columns: 3) == ["1-1", "1-2", "1-3", "2-1", "2-2", "2-3"])
        #expect(PartLabels.tiles(rows: 1, columns: 12).first == "1-01")
    }

    @Test func combinedLabels() {
        #expect(PartLabels.combined(frames: 3, rows: 2, columns: 1)
                == ["1-1-1", "1-2-1", "2-1-1", "2-2-1", "3-1-1", "3-2-1"])
        #expect(PartLabels.combined(frames: 1, rows: 2, columns: 1) == ["1-1", "2-1"])
        #expect(PartLabels.combined(frames: 3, rows: 1, columns: 1) == ["1", "2", "3"])
        #expect(PartLabels.combined(frames: 1, rows: 1, columns: 1) == [])
    }

    @Test func labelsMatchTilesOutsideTheLimits() throws {
        for (columns, rows) in [(0, 2), (200, 1), (150, 1), (-3, 101)] {
            let count = try TileStep.rects(width: 1000, height: 1000, columns: columns, rows: rows, overlap: 0).count
            #expect(PartLabels.tiles(rows: rows, columns: columns).count == count)
            #expect(PartLabels.combined(frames: 2, rows: rows, columns: columns).count == 2 * count)
        }
        #expect(PartLabels.tiles(rows: 1, columns: 150).first == "1-001")
        #expect(PartLabels.combined(frames: 1, rows: 1, columns: 0) == [])
    }

    @Test func hugeOverlapDoesNotTrap() throws {
        #expect(try TileStep.rects(width: 100, height: 100, columns: 3, rows: 1, overlap: .max).count == 3)
        #expect(throws: TileError.self) {
            try TileStep.rects(width: 100, height: 100, columns: 3, rows: 1, overlap: .min)
        }
    }
}
