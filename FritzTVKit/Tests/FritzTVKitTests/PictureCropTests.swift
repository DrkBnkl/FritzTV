import XCTest
@testable import FritzTVKit

final class PictureCropTests: XCTestCase {
    func testPALWidescreenIsCroppedTo16By9() {
        XCTAssertEqual(PictureCrop.standardRatio(width: 720, height: 576, sampleAspect: 16.0 / 11.0), "16:9")
        XCTAssertEqual(PictureCrop.standardRatio(width: 720, height: 576, sampleAspect: 64.0 / 45.0), nil)
    }

    func testPAL4By3IsCroppedTo4By3() {
        XCTAssertEqual(PictureCrop.standardRatio(width: 720, height: 576, sampleAspect: 12.0 / 11.0), "4:3")
    }

    func testExactOrFarOffFormatsStayUntouched() {
        XCTAssertNil(PictureCrop.standardRatio(width: 1920, height: 1080, sampleAspect: 1))
        XCTAssertNil(PictureCrop.standardRatio(width: 1280, height: 720, sampleAspect: 1))
        XCTAssertNil(PictureCrop.standardRatio(width: 544, height: 576, sampleAspect: 1))
        XCTAssertNil(PictureCrop.standardRatio(width: 720, height: 576, sampleAspect: 0))
    }
}
