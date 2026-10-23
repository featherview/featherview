import Testing
@testable import FeatherviewBench

@Suite struct OptionsTests {
    @Test func knownOptionsParse() throws {
        let options = try parseOptions(["--screen", "1x1", "--screen", "2x2", "--runs", "1"], mode: "decode")
        #expect(options == ["--screen": ["1x1", "2x2"], "--runs": ["1"]])
    }

    @Test func gridOptionsParse() throws {
        let options = try parseOptions(["--points", "128", "--scale", "2", "--cells", "40", "--width", "6",
                                        "--json", "a.json", "--baseline", "b.json"], mode: "grid")
        #expect(options == ["--points": ["128"], "--scale": ["2"], "--cells": ["40"], "--width": ["6"],
                            "--json": ["a.json"], "--baseline": ["b.json"]])
    }

    @Test func misspelledOptionFails() {
        #expect(throws: OptionError("Unknown option --sreen for decode.")) {
            try parseOptions(["--sreen", "1x1"], mode: "decode")
        }
    }

    @Test func otherModesOptionFails() {
        #expect(throws: OptionError("Unknown option --interval for browse.")) {
            try parseOptions(["--interval", "30"], mode: "browse")
        }
        #expect(throws: OptionError("Unknown option --runs for browse.")) {
            try parseOptions(["--runs", "3"], mode: "browse")
        }
    }

    @Test func missingValueFails() {
        #expect(throws: OptionError("Unexpected argument --runs.")) {
            try parseOptions(["--runs"], mode: "decode")
        }
    }
}
