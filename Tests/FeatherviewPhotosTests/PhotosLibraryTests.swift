import Testing
@testable import FeatherviewPhotos

struct PhotosLibraryTests {
    /// The app makes the shared library at launch: PhotoKit's image manager waits for the first picture.
    @Test func makingTheLibraryMakesNoImageManager() {
        #expect(!PhotosLibrary().hasImageManager)
    }
}
