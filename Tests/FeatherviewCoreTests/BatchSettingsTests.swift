import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct BatchSettingsTests {
    private func freshDefaults() -> (UserDefaults, String) {
        let name = "featherview-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    /// Every field set to something other than its default.
    private func everythingChanged() -> BatchSettings {
        var s = BatchSettings()
        s.mode = .convertAndRename
        s.formatID = "png"
        s.options.quality = 55
        s.outputFolder = "/tmp/{folder}/out"
        s.renamePattern = "trip-###"
        s.crop = { var c = CropSettings(); c.isOn = true; c.x = 1; c.y = 2; c.width = 3; c.height = 4; c.anchor = .bottomRight; return c }()
        s.resize = {
            var r = ResizeSettings()
            r.isOn = true; r.mode = .megapixels; r.width = 800; r.height = 600; r.side = 1024; r.megapixels = 2.5
            r.percentWidth = 30; r.percentHeight = 40; r.keepAspect = false; r.dontEnlarge = false; r.dontShrink = true; r.dpi = 300
            return r
        }()
        s.orientation = { var o = OrientationSettings(); o.rotate = .left; o.flipHorizontal = true; o.flipVertical = true; return o }()
        s.colour = {
            var c = ColourSettings()
            c.isOn = true; c.greyscale = true; c.negative = true; c.autoAdjust = true
            c.brightness = 10; c.contrast = -20; c.gamma = 2.2; c.saturation = 30
            c.balanceRed = 1; c.balanceGreen = 2; c.balanceBlue = 3; c.sharpen = 4; c.blur = 5
            c.reduceColours = 16; c.dither = false
            return c
        }()
        s.filters = {
            var f = FilterSettings()
            f.isOn = true; f.unsharpMask = 10; f.noiseReduction = 20; f.sepia = 30; f.colourTemperature = -40; f.autoLevels = true
            return f
        }()
        s.canvas = {
            var c = CanvasSettings()
            c.isOn = true; c.autoCropBorders = true; c.method = .aspectRatio; c.left = -1; c.right = 2; c.top = 3; c.bottom = 4
            c.width = 100; c.height = 200; c.ratioWidth = 16; c.ratioHeight = 9; c.anchor = .top; c.colour = .white
            return c
        }()
        s.border = {
            var b = BorderSettings()
            b.isOn = true; b.outerWidth = 5; b.outerColour = .black; b.innerWidth = 2; b.innerColour = .white
            return b
        }()
        s.text = {
            var t = TextSettings()
            t.isOn = true; t.text = "{date}"; t.fontName = "Menlo-Regular"; t.sizePercent = 5; t.colour = .black
            t.position = .topLeft; t.marginPercent = 4; t.placement = .stripBelow; t.opacity = 0.5
            t.shadow = false; t.backgroundBox = true; t.boxColour = RGBAColor(red: 1, green: 1, blue: 0, alpha: 0.25)
            return t
        }()
        s.watermark = {
            var w = WatermarkSettings()
            w.isOn = true; w.path = "/tmp/logo.png"; w.position = .center; w.marginPercent = 1; w.widthPercent = 50; w.opacity = 0.8
            return w
        }()
        s.safety = SafetySettings(replaceExisting: true, trashOriginals: true, keepDates: true, recreateSubfolders: true)
        return s
    }

    @Test func defaultsMatchTheSpec() {
        let s = BatchSettings()
        #expect(s.mode == .convert)
        #expect(s.renamePattern == "{name}")
        #expect(s.format == .jpeg)
        #expect(s.resize.keepAspect && s.resize.dontEnlarge && !s.resize.dontShrink)
        #expect(!s.hasOperations)
        #expect(!s.crop.isOn && !s.resize.isOn && !s.orientation.isOn && !s.colour.isOn && !s.filters.isOn)
        #expect(!s.canvas.isOn && !s.border.isOn && !s.text.isOn && !s.watermark.isOn)
        #expect(s.safety == SafetySettings())
        #expect(!s.safety.replaceExisting && !s.safety.trashOriginals)
    }

    @Test func emptyJSONDecodesToDefaults() throws {
        let s = try JSONDecoder().decode(BatchSettings.self, from: Data("{}".utf8))
        #expect(s == BatchSettings())
    }

    @Test func roundTripsEveryField() throws {
        let s = everythingChanged()
        let back = try JSONDecoder().decode(BatchSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        // Every nested struct differs from its default, so a forgotten key would show.
        let d = BatchSettings()
        #expect(s.crop != d.crop && s.resize != d.resize && s.orientation != d.orientation && s.colour != d.colour)
        #expect(s.filters != d.filters && s.canvas != d.canvas && s.border != d.border && s.text != d.text)
        #expect(s.watermark != d.watermark && s.safety != d.safety)
    }

    @Test func missingNestedKeyKeepsDefault() throws {
        let s = everythingChanged()
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        var resize = json["resize"] as! [String: Any]
        resize["keepAspect"] = nil
        resize["side"] = "not a number"
        json["resize"] = resize
        json["mode"] = nil
        let back = try JSONDecoder().decode(BatchSettings.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(back.resize.keepAspect == ResizeSettings().keepAspect)
        #expect(back.resize.side == ResizeSettings().side)
        #expect(back.resize.megapixels == 2.5)
        #expect(back.mode == .convert)
        #expect(back.text == s.text)
    }

    @Test func unknownFormatFallsBackToJPEG() throws {
        let s = try JSONDecoder().decode(BatchSettings.self, from: Data(#"{"formatID":"nope"}"#.utf8))
        #expect(s.formatID == "nope")
        #expect(s.format == .jpeg)
    }

    @Test func hasOperationsOnlyWhenAStepIsOn() {
        var s = BatchSettings()
        s.mode = .convertAndRename
        s.renamePattern = "x-###"
        s.safety.replaceExisting = true
        s.resize.side = 99  // settings of a step that is off don't count
        #expect(!s.hasOperations)
        let steps: [(inout BatchSettings) -> Void] = [
            { $0.crop.isOn = true }, { $0.resize.isOn = true }, { $0.orientation.rotate = .right },
            { $0.orientation.flipHorizontal = true }, { $0.orientation.flipVertical = true },
            { $0.colour.isOn = true }, { $0.filters.isOn = true }, { $0.canvas.isOn = true },
            { $0.border.isOn = true }, { $0.text.isOn = true }, { $0.watermark.isOn = true },
        ]
        for step in steps {
            var t = s
            step(&t)
            #expect(t.hasOperations)
        }
    }

    @Test func presetsSaveLoadDeleteAndList() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(BatchPresets.names(in: defaults).isEmpty)
        let web = everythingChanged()
        BatchPresets.save("Web 10", web, in: defaults)
        BatchPresets.save("Web 9", BatchSettings(), in: defaults)
        BatchPresets.save("archive", BatchSettings(), in: defaults)
        #expect(BatchPresets.names(in: defaults) == ["archive", "Web 9", "Web 10"])
        #expect(BatchPresets.load("Web 10", in: defaults) == web)
        #expect(BatchPresets.load("missing", in: defaults) == nil)
        BatchPresets.save("Web 10", BatchSettings(), in: defaults)  // same name replaces
        #expect(BatchPresets.load("Web 10", in: defaults) == BatchSettings())
        BatchPresets.delete("Web 9", in: defaults)
        #expect(BatchPresets.names(in: defaults) == ["archive", "Web 10"])

        #expect(BatchPresets.current(in: defaults) == BatchSettings())
        BatchPresets.saveCurrent(web, in: defaults)
        #expect(BatchPresets.current(in: defaults) == web)
        #expect(BatchPresets.names(in: defaults) == ["archive", "Web 10"])
    }

    @Test func corruptPresetIsSkipped() throws {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        BatchPresets.save("good", BatchSettings(), in: defaults)
        var stored = try JSONDecoder().decode([String: Data].self, from: defaults.data(forKey: "batchPresets")!)
        stored["bad"] = Data("not json".utf8)
        defaults.set(try JSONEncoder().encode(stored), forKey: "batchPresets")
        #expect(BatchPresets.load("bad", in: defaults) == nil)
        #expect(BatchPresets.load("good", in: defaults) == BatchSettings())
        #expect(BatchPresets.names(in: defaults) == ["good"])

        defaults.set(Data("garbage".utf8), forKey: "batchPresets")
        #expect(BatchPresets.names(in: defaults).isEmpty)
        defaults.set(Data("garbage".utf8), forKey: "batchSettings")
        #expect(BatchPresets.current(in: defaults) == BatchSettings())
    }

    @Test func unreadablePresetStoreIsNeverOverwritten() throws {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let future = Data(#"{"version":2,"presets":{"A":{}}}"#.utf8)
        for blob: Any in [future, Data("garbage".utf8), "a string"] {
            defaults.set(blob, forKey: "batchPresets")
            #expect(BatchPresets.save("B", BatchSettings(), in: defaults) == false)
            #expect(BatchPresets.delete("A", in: defaults) == false)
            #expect((defaults.object(forKey: "batchPresets") as? NSObject) == (blob as? NSObject))
        }
        defaults.removeObject(forKey: "batchPresets")
        #expect(BatchPresets.save("B", BatchSettings(), in: defaults))
        #expect(BatchPresets.names(in: defaults) == ["B"])
    }
}
