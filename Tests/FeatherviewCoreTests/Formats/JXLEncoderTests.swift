import CJPEGXL
import Testing

@Suite struct JXLEncoderTests {
    @Test func linksLibjxl() {
        #expect(JxlEncoderVersion() == 12000)
    }
}
