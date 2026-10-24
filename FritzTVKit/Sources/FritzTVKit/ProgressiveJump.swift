import Foundation

/// Berechnet progressive Spulschritte beim mehrmaligen schnellen Drücken (Option 2 / Kodi-Staffelung):
/// 1x drücken: 10 Sekunden (insgesamt 10 s)
/// 2x drücken: 30 Sekunden (insgesamt 30 s)
/// 3x drücken: 1 Minute (insgesamt 60 s)
/// 4x drücken: 3 Minuten (insgesamt 180 s)
/// 5x drücken: 5 Minuten (insgesamt 300 s)
/// ab 6x drücken: jeweils weitere 5 Minuten (600 s, 900 s...)
public struct ProgressiveJump {
    public struct Result: Equatable {
        /// Der relative Sprungwert in Sekunden für diesen einzelnen Tastendruck.
        public let stepDelta: Double
        /// Der gesamte bisherige Sprungwert in Sekunden seit Beginn der Sequenz.
        public let totalSeconds: Double
        /// Kurzer Anzeigetext für das HUD (z. B. "+10 s", "+30 s", "+1 Min.", "+3 Min.", "+5 Min.").
        public let displayText: String

        public init(stepDelta: Double, totalSeconds: Double, displayText: String) {
            self.stepDelta = stepDelta
            self.totalSeconds = totalSeconds
            self.displayText = displayText
        }
    }

    public static func nextStep(
        forward: Bool,
        lastPressAt: inout Date,
        lastDirectionForward: inout Bool,
        pressCount: inout Int,
        now: Date = Date(),
        timeout: TimeInterval = 1.0
    ) -> Result {
        if now.timeIntervalSince(lastPressAt) > timeout || lastDirectionForward != forward {
            pressCount = 1
        } else {
            pressCount += 1
        }
        lastPressAt = now
        lastDirectionForward = forward

        let totalSeconds: Double
        let stepDelta: Double
        let sign: Double = forward ? 1.0 : -1.0

        switch pressCount {
        case 1:
            totalSeconds = 10.0
            stepDelta = 10.0
        case 2:
            totalSeconds = 30.0
            stepDelta = 20.0 // 10 + 20 = 30
        case 3:
            totalSeconds = 60.0 // 1 Minute
            stepDelta = 30.0 // 30 + 30 = 60
        case 4:
            totalSeconds = 180.0 // 3 Minuten
            stepDelta = 120.0 // 60 + 120 = 180
        case 5:
            totalSeconds = 300.0 // 5 Minuten
            stepDelta = 120.0 // 180 + 120 = 300
        default:
            let extraSteps = pressCount - 5
            totalSeconds = 300.0 + Double(extraSteps) * 300.0
            stepDelta = 300.0
        }

        let prefix = forward ? "+" : "−"
        let displayText: String
        if totalSeconds < 60 {
            displayText = "\(prefix)\(Int(totalSeconds)) s"
        } else {
            let minutes = Int(totalSeconds / 60)
            displayText = "\(prefix)\(minutes) Min."
        }

        return Result(
            stepDelta: stepDelta * sign,
            totalSeconds: totalSeconds * sign,
            displayText: displayText
        )
    }
}
