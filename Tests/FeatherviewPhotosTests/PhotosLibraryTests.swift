import Photos
import Testing
@testable import FeatherviewPhotos

struct PhotosLibraryTests {
    /// The app makes the shared library at launch: PhotoKit's image manager waits for the first picture.
    @Test func makingTheLibraryMakesNoImageManager() {
        #expect(!PhotosLibrary().hasImageManager)
    }

    /// Delete: only the person's Cancel in Photos' prompt stays silent; any other refusal is reported.
    @Test func onlyCancelIsACancel() {
        #expect(PhotosLibrary.isCancel(PHPhotosError(.userCancelled)))
        #expect(!PhotosLibrary.isCancel(PHPhotosError(.accessUserDenied)))
        #expect(!PhotosLibrary.isCancel(CocoaError(.fileNoSuchFile)))
    }
}
