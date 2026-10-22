import Testing
@testable import FeatherviewCore

@Suite struct CompareTextTests {
    @Test func titleNamesBoth() {
        #expect(CompareText.title(first: "a.jpg", second: "b.png") == "a.jpg and b.png")
    }

    @Test func chooseNamesTheFile() {
        #expect(CompareText.choose("IMG_1234.jpg") == "Choose an image to compare with IMG_1234.jpg")
    }

    @Test func differenceLabel() {
        #expect(CompareText.difference == "Difference")
    }
}
