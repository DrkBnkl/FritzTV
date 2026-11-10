import XCTest
import CoreGraphics
@testable import FritzTVKit

final class PictureCropTests: XCTestCase {
    /// Seitenverhältnis des sichtbaren Ausschnitts: volles Bild geteilt durch die Vergrößerung.
    private func visibleAspect(width: Int, height: Int, sar: Double) -> Double? {
        guard let zoom = PictureCrop.zoom(width: width, height: height, sampleAspect: sar) else { return nil }
        let full = Double(width) * sar / Double(PictureCrop.visibleLines(height))
        return full * zoom.y / zoom.x
    }

    func testPALWidescreenFillsExactly16By9WithOverscan() {
        XCTAssertEqual(visibleAspect(width: 720, height: 576, sar: 16.0 / 11.0)!, 16.0 / 9.0, accuracy: 0.0001)
        let zoom = PictureCrop.defaultSD
        XCTAssertEqual(zoom.y, 1 / 0.95, accuracy: 0.0001)
        // Seitlich mindestens 22 Quellspalten (schwarzer Rand bei Kabel Eins) abschneiden.
        XCTAssertGreaterThan(720 * (1 - 1 / zoom.x) / 2, 22)
    }

    func testAlignedDecoderHeightUsesVisibleLines() {
        XCTAssertEqual(PictureCrop.zoom(width: 720, height: 578, sampleAspect: 16.0 / 11.0), PictureCrop.defaultSD)
    }

    func testExact16By9And4By3Sources() {
        XCTAssertEqual(visibleAspect(width: 720, height: 576, sar: 64.0 / 45.0)!, 16.0 / 9.0, accuracy: 0.0001)
        XCTAssertEqual(visibleAspect(width: 720, height: 576, sar: 12.0 / 11.0)!, 4.0 / 3.0, accuracy: 0.0001)
    }

    func testOtherFormatsKeepTheirAspect() {
        XCTAssertEqual(visibleAspect(width: 544, height: 576, sar: 1)!, 544.0 / 576.0, accuracy: 0.0001)
    }

    func testInvalidInputGivesNil() {
        XCTAssertNil(PictureCrop.zoom(width: 720, height: 576, sampleAspect: 0))
        XCTAssertNil(PictureCrop.zoom(width: 0, height: 576, sampleAspect: 1))
    }

    func testFrameIsCenteredAndScaled() {
        let frame = PictureCrop.Zoom(x: 1.1, y: 1.2).frame(in: CGRect(x: 0, y: 0, width: 100, height: 50))
        XCTAssertEqual(frame.width, 110, accuracy: 0.001)
        XCTAssertEqual(frame.height, 60, accuracy: 0.001)
        XCTAssertEqual(frame.midX, 50, accuracy: 0.001)
        XCTAssertEqual(frame.midY, 25, accuracy: 0.001)
        XCTAssertEqual(PictureCrop.Zoom.none.frame(in: CGRect(x: 5, y: 5, width: 10, height: 10)),
                       CGRect(x: 5, y: 5, width: 10, height: 10))
    }
}
