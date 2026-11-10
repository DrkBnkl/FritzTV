import XCTest
@testable import FritzTVKit

final class PictureCropTests: XCTestCase {
    private func aspect(of geometry: String?, sampleAspect: Double) -> Double? {
        guard let geometry else { return nil }
        let parts = geometry.split(whereSeparator: { "x+".contains($0) }).compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return parts[0] * sampleAspect / parts[1]
    }

    func testPALWidescreenGetsOverscanAndExact16By9() {
        let geometry = PictureCrop.geometry(width: 720, height: 576, sampleAspect: 16.0 / 11.0)
        XCTAssertEqual(geometry, "684x560+18+8")
        XCTAssertEqual(aspect(of: geometry, sampleAspect: 16.0 / 11.0)!, 16.0 / 9.0, accuracy: 0.01)
    }

    func testAlignedDecoderHeightUsesVisibleLines() {
        XCTAssertEqual(PictureCrop.geometry(width: 720, height: 578, sampleAspect: 16.0 / 11.0), "684x560+18+8")
    }

    func testExact16By9SourceAlsoGetsOverscan() {
        let sar = 64.0 / 45.0
        let geometry = PictureCrop.geometry(width: 720, height: 576, sampleAspect: sar)
        XCTAssertEqual(aspect(of: geometry, sampleAspect: sar)!, 16.0 / 9.0, accuracy: 0.01)
    }

    func testPAL4By3IsCroppedTo4By3() {
        let sar = 12.0 / 11.0
        let geometry = PictureCrop.geometry(width: 720, height: 576, sampleAspect: sar)
        XCTAssertEqual(aspect(of: geometry, sampleAspect: sar)!, 4.0 / 3.0, accuracy: 0.01)
    }

    func testOtherFormatsKeepTheirAspect() {
        // 544 × 576 mit SAR 1 ist kein Standardformat: nur Overscan, Seitenverhältnis bleibt.
        let geometry = PictureCrop.geometry(width: 544, height: 576, sampleAspect: 1)
        XCTAssertEqual(aspect(of: geometry, sampleAspect: 1)!, 544.0 / 576.0, accuracy: 0.01)
    }

    func testInvalidInputGivesNil() {
        XCTAssertNil(PictureCrop.geometry(width: 720, height: 576, sampleAspect: 0))
        XCTAssertNil(PictureCrop.geometry(width: 0, height: 576, sampleAspect: 1))
    }

    func testDefaultMatchesPALWidescreen() {
        XCTAssertEqual(PictureCrop.defaultSDGeometry, "684x560+18+8")
    }
}
