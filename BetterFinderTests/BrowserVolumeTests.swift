import XCTest
@testable import BetterFinder

final class BrowserVolumeTests: XCTestCase {

    func testCurrentVolumeURL_whenNotInVolumes_returnsNil() {
        let state = BrowserState(
            url: URL(fileURLWithPath: "/Users/me/Documents"),
            fileSystemService: FileSystemService()
        )

        XCTAssertNil(state.currentVolumeURL)
    }

    func testVolumeMountPoint_whenPathIsVolumesRoot_returnsNil() {
        let service = VolumeService()
        let url = URL(fileURLWithPath: "/Volumes")

        XCTAssertNil(service.volumeMountPoint(for: url))
    }

    func testVolumeMountPoint_whenNotInVolumes_returnsNil() {
        let service = VolumeService()
        let url = URL(fileURLWithPath: "/Users/me/Documents")

        XCTAssertNil(service.volumeMountPoint(for: url))
    }

    func testVolumeMountPoint_whenPathDoesNotExist_returnsNil() {
        let service = VolumeService()
        let url = URL(fileURLWithPath: "/Volumes/NonExistentVolume/some/path")

        XCTAssertNil(service.volumeMountPoint(for: url))
    }

    func testIsEjectableVolume_whenPathIsNotVolume_returnsFalse() {
        let service = VolumeService()
        let url = URL(fileURLWithPath: "/Users/me/Documents")

        XCTAssertFalse(service.isEjectableVolume(url))
    }

    func testIsEjectableVolume_whenPathIsVolumesRoot_returnsFalse() {
        let service = VolumeService()
        let url = URL(fileURLWithPath: "/Volumes")

        XCTAssertFalse(service.isEjectableVolume(url))
    }

    func testEjectVolume_whenVolumeNotFound_throwsMountPointNotFound() async {
        let service = VolumeService()
        let url = URL(fileURLWithPath: "/Volumes/NonExistentVolume")

        do {
            try await service.ejectVolume(at: url)
            XCTFail("Expected VolumeError.mountPointNotFound")
        } catch VolumeError.mountPointNotFound {
        } catch {
            XCTFail("Expected VolumeError.mountPointNotFound, got \(error)")
        }
    }

    func testAlertPresenter_isCalledOnError() async {
        let appState = AppState()
        var alertTitle: String?
        var alertMessage: String?
        appState.alertPresenter = { title, message in
            alertTitle = title
            alertMessage = message
        }

        let testURL = URL(fileURLWithPath: "/NonExistentVolume")
        await appState.ejectVolume(for: testURL)

        XCTAssertEqual(alertTitle, NSLocalizedString("EJECT_ALERT_TITLE", comment: ""))
        XCTAssertNotNil(alertMessage)
    }
}