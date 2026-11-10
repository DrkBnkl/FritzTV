import Foundation
import CoreGraphics

/// Bildausschnitt für SD-Sender: Overscan und Standardformat.
///
/// SD-Sender senden 720 × 576 Pixel mit einem Pixel-Seitenverhältnis (SAR) von 16:11 (16:9) bzw.
/// 12:11 (4:3). Über die volle Breite ergibt das etwa 1,82 bzw. 1,36 – etwas breiter als 16:9 bzw. 4:3,
/// weil die Randspalten zur Austastung gehören. Viele Sender schicken außerdem schwarze Randspalten
/// und -zeilen mit (Kabel Eins links und rechts je rund 22 Spalten), die ein Fernseher per Overscan
/// ausblendet.
///
/// VLC zeichnet das volle Bild; die App vergrößert die Zeichenfläche um `Zoom` und schneidet den Rand
/// ab, sodass ein Ausschnitt mit rund 2,5 % Overscan je Rand genau das Standardformat füllt. Der
/// Beschnitt der VLC-Videoausgabe (`crop`) eignet sich dafür nicht: Auf dem Mac verschob er den Rand
/// nur von oben und unten an die Seiten.
public enum PictureCrop {
    /// Anteil der Bildhöhe bzw. -breite, der an jedem Rand abgeschnitten wird.
    public static let overscan = 0.025

    /// Vergrößerung der Zeichenfläche gegenüber dem sichtbaren Bildbereich.
    public struct Zoom: Equatable, Sendable {
        public let x: Double
        public let y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        public static let none = Zoom(x: 1, y: 1)

        /// Rahmen der Zeichenfläche, zentriert über `bounds`.
        public func frame(in bounds: CGRect) -> CGRect {
            let width = bounds.width * x
            let height = bounds.height * y
            return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
        }
    }

    /// Vergrößerung für 720 × 576 mit SAR 16:11, solange die Videospur noch kein Format meldet.
    public static let defaultSD = zoom(width: 720, height: 576, sampleAspect: 16.0 / 11.0)!

    /// Vergrößerung für eine Videospur oder `nil` bei ungültigen Angaben.
    ///
    /// VLC passt das volle Bild (Breite × sichtbare Zeilen, SAR) in die Zeichenfläche ein. Ist diese um
    /// Bild/Ausschnitt größer als der sichtbare Bereich, füllt der Ausschnitt den Bereich genau.
    public static func zoom(width: Int, height: Int, sampleAspect: Double) -> Zoom? {
        guard width > 16, height > 16, sampleAspect > 0, sampleAspect.isFinite else { return nil }
        let lines = Double(visibleLines(height))
        let croppedHeight = lines * (1 - 2 * overscan)
        let fullAspect = Double(width) * sampleAspect / lines
        let aspect = standardAspect(near: fullAspect) ?? fullAspect
        let croppedWidth = min(aspect * croppedHeight / sampleAspect, Double(width))
        return Zoom(x: Double(width) / croppedWidth, y: lines / croppedHeight)
    }

    /// 16:9 bzw. 4:3, wenn das Bild bis zu 4 % breiter oder 1 % schmaler ist.
    static func standardAspect(near aspect: Double) -> Double? {
        [16.0 / 9.0, 4.0 / 3.0].first { aspect > $0 * 0.99 && aspect < $0 * 1.04 }
    }

    /// Decoder liefern bei PAL teils 578 oder mehr Zeilen (Ausrichtung); sichtbar sind 576.
    static func visibleLines(_ height: Int) -> Int {
        (577...592).contains(height) ? 576 : height
    }
}
