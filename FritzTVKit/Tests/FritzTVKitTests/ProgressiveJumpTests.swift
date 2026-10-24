import XCTest
@testable import FritzTVKit

final class ProgressiveJumpTests: XCTestCase {
    func testProgressiveJumpSequence() {
        var lastPressAt = Date.distantPast
        var lastForward = true
        var pressCount = 0

        let start = Date(timeIntervalSince1970: 1000)

        // 1. Drücken: +10 s
        let step1 = ProgressiveJump.nextStep(
            forward: true,
            lastPressAt: &lastPressAt,
            lastDirectionForward: &lastForward,
            pressCount: &pressCount,
            now: start
        )
        XCTAssertEqual(step1.stepDelta, 10.0)
        XCTAssertEqual(step1.totalSeconds, 10.0)
        XCTAssertEqual(step1.displayText, "+10 s")

        // 2. Drücken nach 0.3 s: +30 s (Delta 20 s)
        let step2 = ProgressiveJump.nextStep(
            forward: true,
            lastPressAt: &lastPressAt,
            lastDirectionForward: &lastForward,
            pressCount: &pressCount,
            now: start.addingTimeInterval(0.3)
        )
        XCTAssertEqual(step2.stepDelta, 20.0)
        XCTAssertEqual(step2.totalSeconds, 30.0)
        XCTAssertEqual(step2.displayText, "+30 s")

        // 3. Drücken nach weiteren 0.3 s: +1 Min (60 s, Delta 30 s)
        let step3 = ProgressiveJump.nextStep(
            forward: true,
            lastPressAt: &lastPressAt,
            lastDirectionForward: &lastForward,
            pressCount: &pressCount,
            now: start.addingTimeInterval(0.6)
        )
        XCTAssertEqual(step3.stepDelta, 30.0)
        XCTAssertEqual(step3.totalSeconds, 60.0)
        XCTAssertEqual(step3.displayText, "+1 Min.")

        // 4. Drücken nach weiteren 0.3 s: +3 Min (180 s, Delta 120 s)
        let step4 = ProgressiveJump.nextStep(
            forward: true,
            lastPressAt: &lastPressAt,
            lastDirectionForward: &lastForward,
            pressCount: &pressCount,
            now: start.addingTimeInterval(0.9)
        )
        XCTAssertEqual(step4.stepDelta, 120.0)
        XCTAssertEqual(step4.totalSeconds, 180.0)
        XCTAssertEqual(step4.displayText, "+3 Min.")

        // 5. Drücken nach weiteren 0.3 s: +5 Min (300 s, Delta 120 s)
        let step5 = ProgressiveJump.nextStep(
            forward: true,
            lastPressAt: &lastPressAt,
            lastDirectionForward: &lastForward,
            pressCount: &pressCount,
            now: start.addingTimeInterval(1.2)
        )
        XCTAssertEqual(step5.stepDelta, 120.0)
        XCTAssertEqual(step5.totalSeconds, 300.0)
        XCTAssertEqual(step5.displayText, "+5 Min.")

        // 6. Drücken nach weiteren 0.3 s: +10 Min (600 s, Delta 300 s)
        let step6 = ProgressiveJump.nextStep(
            forward: true,
            lastPressAt: &lastPressAt,
            lastDirectionForward: &lastForward,
            pressCount: &pressCount,
            now: start.addingTimeInterval(1.5)
        )
        XCTAssertEqual(step6.stepDelta, 300.0)
        XCTAssertEqual(step6.totalSeconds, 600.0)
        XCTAssertEqual(step6.displayText, "+10 Min.")
    }

    func testProgressiveJumpBackward() {
        var lastPressAt = Date.distantPast
        var lastForward = false
        var pressCount = 0

        let start = Date(timeIntervalSince1970: 1000)

        // 1. Drücken: -10 s
        let step1 = ProgressiveJump.nextStep(
            forward: false,
            lastPressAt: &lastPressAt,
            lastDirectionForward: &lastForward,
            pressCount: &pressCount,
            now: start
        )
        XCTAssertEqual(step1.stepDelta, -10.0)
        XCTAssertEqual(step1.totalSeconds, -10.0)
        XCTAssertEqual(step1.displayText, "−10 s")

        // 2. Drücken: -30 s
        let step2 = ProgressiveJump.nextStep(
            forward: false,
            lastPressAt: &lastPressAt,
            lastDirectionForward: &lastForward,
            pressCount: &pressCount,
            now: start.addingTimeInterval(0.4)
        )
        XCTAssertEqual(step2.stepDelta, -20.0)
        XCTAssertEqual(step2.totalSeconds, -30.0)
        XCTAssertEqual(step2.displayText, "−30 s")

        // 3. Drücken: -1 Min
        let step3 = ProgressiveJump.nextStep(
            forward: false,
            lastPressAt: &lastPressAt,
            lastDirectionForward: &lastForward,
            pressCount: &pressCount,
            now: start.addingTimeInterval(0.8)
        )
        XCTAssertEqual(step3.stepDelta, -30.0)
        XCTAssertEqual(step3.totalSeconds, -60.0)
        XCTAssertEqual(step3.displayText, "−1 Min.")

        // 4. Drücken: -3 Min
        let step4 = ProgressiveJump.nextStep(
            forward: false,
            lastPressAt: &lastPressAt,
            lastDirectionForward: &lastForward,
            pressCount: &pressCount,
            now: start.addingTimeInterval(1.2)
        )
        XCTAssertEqual(step4.stepDelta, -120.0)
        XCTAssertEqual(step4.totalSeconds, -180.0)
        XCTAssertEqual(step4.displayText, "−3 Min.")

        // 5. Drücken: -5 Min
        let step5 = ProgressiveJump.nextStep(
            forward: false,
            lastPressAt: &lastPressAt,
            lastDirectionForward: &lastForward,
            pressCount: &pressCount,
            now: start.addingTimeInterval(1.6)
        )
        XCTAssertEqual(step5.stepDelta, -120.0)
        XCTAssertEqual(step5.totalSeconds, -300.0)
        XCTAssertEqual(step5.displayText, "−5 Min.")
    }

    func testTimeoutResetsToFirstStep() {
        var lastPressAt = Date.distantPast
        var lastForward = true
        var pressCount = 0

        let start = Date(timeIntervalSince1970: 1000)

        _ = ProgressiveJump.nextStep(
            forward: true,
            lastPressAt: &lastPressAt,
            lastDirectionForward: &lastForward,
            pressCount: &pressCount,
            now: start
        )

        _ = ProgressiveJump.nextStep(
            forward: true,
            lastPressAt: &lastPressAt,
            lastDirectionForward: &lastForward,
            pressCount: &pressCount,
            now: start.addingTimeInterval(0.5)
        )

        // Mehr als 1.0 Sekunde Pause -> Reset auf Step 1 (+10 s)
        let stepAfterTimeout = ProgressiveJump.nextStep(
            forward: true,
            lastPressAt: &lastPressAt,
            lastDirectionForward: &lastForward,
            pressCount: &pressCount,
            now: start.addingTimeInterval(2.0)
        )
        XCTAssertEqual(stepAfterTimeout.stepDelta, 10.0)
        XCTAssertEqual(stepAfterTimeout.totalSeconds, 10.0)
        XCTAssertEqual(stepAfterTimeout.displayText, "+10 s")
        XCTAssertEqual(pressCount, 1)
    }

    func testDirectionChangeResetsToFirstStep() {
        var lastPressAt = Date.distantPast
        var lastForward = true
        var pressCount = 0

        let start = Date(timeIntervalSince1970: 1000)

        _ = ProgressiveJump.nextStep(
            forward: true,
            lastPressAt: &lastPressAt,
            lastDirectionForward: &lastForward,
            pressCount: &pressCount,
            now: start
        )

        // Richtungswechsel innerhalb von 0.3 s von Vorwärts auf Rückwärts
        let stepReverse = ProgressiveJump.nextStep(
            forward: false,
            lastPressAt: &lastPressAt,
            lastDirectionForward: &lastForward,
            pressCount: &pressCount,
            now: start.addingTimeInterval(0.3)
        )
        XCTAssertEqual(stepReverse.stepDelta, -10.0)
        XCTAssertEqual(stepReverse.totalSeconds, -10.0)
        XCTAssertEqual(stepReverse.displayText, "−10 s")
        XCTAssertEqual(pressCount, 1)
    }
}
