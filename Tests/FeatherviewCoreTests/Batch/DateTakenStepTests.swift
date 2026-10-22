import Foundation
import ImageIO
import Testing
@testable import FeatherviewCore

@Suite struct DateShiftDirectionTests {
    @Test func earlierSurvivesAZeroShift() {
        var d = DateTakenSettings()
        d.shiftSeconds = -3600  // from saved settings: the direction was never picked
        d.setShiftPart(0, unit: 3600, count: 24)
        #expect(d.shiftSeconds == 0 && d.shiftsEarlier)
        d.setShiftPart(2, unit: 3600, count: 24)
        #expect(d.shiftSeconds == -7200)
    }

    @Test func directionPickedAtZeroIsSaved() throws {
        var d = DateTakenSettings()
        d.shiftsEarlier = true
        let decoded = try JSONDecoder().decode(DateTakenSettings.self, from: JSONEncoder().encode(d))
        #expect(decoded.shiftsEarlier)
        var e = decoded
        e.setShiftPart(3, unit: 3600, count: 24)
        #expect(e.shiftSeconds == -10800)
    }

    @Test func partsReadAndReplace() {
        var d = DateTakenSettings()
        d.shiftSeconds = -(86_400 + 2 * 3600 + 3 * 60 + 4)
        #expect(d.shiftPart(unit: 86_400, count: 3651) == 1 && d.shiftPart(unit: 3600, count: 24) == 2
            && d.shiftPart(unit: 60, count: 60) == 3 && d.shiftPart(unit: 1, count: 60) == 4)
        d.setShiftPart(5, unit: 60, count: 60)
        #expect(d.shiftSeconds == -(86_400 + 2 * 3600 + 5 * 60 + 4))
        d.shiftsEarlier = false
        #expect(d.shiftSeconds == 86_400 + 2 * 3600 + 5 * 60 + 4)
    }

    @Test func minShiftDoesNotTrap() {
        var d = DateTakenSettings()
        d.shiftSeconds = .min
        #expect(d.shiftsEarlier)
        _ = d.shiftPart(unit: 1, count: 60)
        d.setShiftPart(0, unit: 1, count: 60)
        #expect(d.shiftSeconds < 0)
    }
}

@Suite struct BatchPreviewNamesTests {
    func photo(_ dir: URL, _ name: String, taken: String) throws -> BatchInput {
        BatchInput(url: try Fixtures.writeImage(to: dir.appendingPathComponent(name), width: 8, height: 8, properties: [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: taken]]), root: nil)
    }

    @Test func dateUsesTheNewDateTaken() throws {
        let dir = try Fixtures.makeTempDir()
        let input = try photo(dir, "a.jpg", taken: "2024:03:10 09:00:00")
        var s = BatchSettings()
        s.renamePattern = "{date}-{n}"
        s.formatID = "jpg"
        #expect(BatchPreviewNames.compute(s, inputs: [input]).names == ["2024-03-10-1.jpg"])
        s.dateTaken.isOn = true
        s.dateTaken.mode = .set
        s.dateTaken.setTo = "2019:05:01 12:00:00"
        #expect(BatchPreviewNames.compute(s, inputs: [input]).names == ["2019-05-01-1.jpg"])
        s.dateTaken.mode = .shift
        s.dateTaken.shiftSeconds = -86_400
        #expect(BatchPreviewNames.compute(s, inputs: [input]).names == ["2024-03-09-1.jpg"])
    }

    @Test func countsEveryPartAndStopsWhenCancelled() async throws {
        let dir = try Fixtures.makeTempDir()
        let gif = BatchInput(url: try Fixtures.writeAnimatedGIF(to: dir.appendingPathComponent("a.gif"), delays: [0.1, 0.1, 0.1]), root: nil)
        let jpeg = try photo(dir, "b.jpg", taken: "2024:03:10 09:00:00")
        var s = BatchSettings()
        s.frames.isOn = true
        let all = BatchPreviewNames.compute(s, inputs: [gif, jpeg, gif, jpeg, jpeg])
        #expect(all.names.count == 5 && all.more == 4 && all.frameCounts[gif.url] == 3)
        #expect(all.cancelled == false)

        let cancelled = await Task { [s] in
            withUnsafeCurrentTask { $0?.cancel() }
            return BatchPreviewNames.compute(s, inputs: [gif, jpeg])
        }.value
        #expect(cancelled.cancelled && cancelled.frameCounts.isEmpty)

        s.frames.isOn = false
        s.tiles.isOn = true
        let tiles = await Task { [s] in
            withUnsafeCurrentTask { $0?.cancel() }
            return BatchPreviewNames.compute(s, inputs: [jpeg])
        }.value
        #expect(tiles.cancelled)
    }

    @Test func textDateUsesTheNewDateTaken() throws {
        let dir = try Fixtures.makeTempDir()
        let input = try photo(dir, "a.jpg", taken: "2024:03:10 09:00:00")
        var s = BatchSettings()
        #expect(BatchPreviewNames.date(s, url: input.url) == MetadataReader.exifDate("2024:03:10 09:00:00"))
        s.dateTaken.isOn = true
        s.dateTaken.mode = .set
        s.dateTaken.setTo = "2019:05:01 12:00:00"
        #expect(BatchPreviewNames.date(s, url: input.url) == MetadataReader.exifDate("2019:05:01 12:00:00"))
    }

    @Test func countsPartsWithoutListingThem() {
        var s = BatchSettings()
        #expect(BatchPreviewNames.parts(s, frames: 0) == 1)
        #expect(BatchPreviewNames.parts(s, frames: 300) == 300)
        s.tiles.isOn = true
        s.tiles.rows = 100
        s.tiles.columns = 100
        #expect(BatchPreviewNames.parts(s, frames: 300) == 3_000_000)
        #expect(BatchPreviewNames.parts(s, frames: 1) == 10_000)
        #expect(PartLabels.combined(frames: 300, rows: 100, columns: 100, limit: 2) == ["001-001-001", "001-001-002"])
        #expect(PartLabels.combined(frames: 3, rows: 1, columns: 1, limit: 5) == ["1", "2", "3"])
    }
}
