import Photos
import Testing
@testable import FeatherviewPhotos

struct PhotosAlbumsTests {
    @Test func everySmartAlbumWithPicturesIsAMediaTypeButVideoHiddenAndListedOnesAreNot() {
        let spatial = PHAssetCollectionSubtype(rawValue: 219)!  // .smartAlbumSpatial, macOS 15+
        #expect(PhotosLibrary.isMediaType(spatial))
        #expect(PhotosLibrary.isMediaType(.smartAlbumPanoramas))
        #expect(PhotosLibrary.isMediaType(.smartAlbumRAW))
        for skipped: PHAssetCollectionSubtype in [
            .smartAlbumVideos, .smartAlbumSlomoVideos, .smartAlbumTimelapses, .smartAlbumCinematic,
            .smartAlbumScreenRecordings, .smartAlbumAllHidden, .smartAlbumFavorites, .smartAlbumRecentlyAdded,
            .smartAlbumUserLibrary, .smartAlbumUnableToUpload, .smartAlbumGeneric,
        ] {
            #expect(!PhotosLibrary.isMediaType(skipped), "\(skipped.rawValue)")
        }
    }
}
