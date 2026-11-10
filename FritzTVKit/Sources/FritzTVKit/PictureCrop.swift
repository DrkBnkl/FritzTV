import Foundation

/// Bildausschnitt für SD-Sender: Overscan und Beschnitt auf das Standardformat.
///
/// SD-Sender senden 720 × 576 Pixel mit einem Pixel-Seitenverhältnis (SAR) von 16:11 (16:9) bzw.
/// 12:11 (4:3). Über die volle Breite ergibt das etwa 1,82 bzw. 1,36 – etwas breiter als 16:9 bzw. 4:3,
/// weil die Randspalten zur Austastung gehören. Außerdem enthalten viele SD-Signale oben und unten
/// einige schwarze Zeilen, die ein Fernseher per Overscan ausblendet.
///
/// `geometry` liefert deshalb einen Ausschnitt, der an allen Rändern rund 2,5 % abschneidet (SAT.1 etwa sendet oben und unten je rund 11 schwarze Zeilen) und
/// dabei genau das Standardformat trifft. Liegt das Bild nicht nahe an 16:9 oder 4:3, bleibt sein
/// eigenes Seitenverhältnis erhalten.
public enum PictureCrop {
    /// Anteil der Bildhöhe, der oben und unten jeweils abgeschnitten wird.
    public static let overscan = 0.025

    /// Ausschnitt für 720 × 576 mit SAR 16:11, solange die Videospur noch kein Format meldet.
    public static let defaultSDGeometry = geometry(width: 720, height: 576, sampleAspect: 16.0 / 11.0)!

    /// VLC-Bildausschnitt im Format `BxH+X+Y` (Quellpixel) oder `nil` bei ungültigen Angaben.
    public static func geometry(width: Int, height: Int, sampleAspect: Double) -> String? {
        guard width > 16, height > 16, sampleAspect > 0, sampleAspect.isFinite else { return nil }
        // Decoder liefern bei PAL teils 578 oder mehr Zeilen (Ausrichtung); sichtbar sind 576.
        let lines = (577...592).contains(height) ? 576 : height
        let cut = even(Double(lines) * overscan)
        let croppedHeight = lines - 2 * cut
        let fullAspect = Double(width) * sampleAspect / Double(lines)
        let aspect = standardAspect(near: fullAspect) ?? fullAspect
        let croppedWidth = min(even(aspect * Double(croppedHeight) / sampleAspect), width)
        let x = even(Double(width - croppedWidth) / 2)
        return "\(croppedWidth)x\(croppedHeight)+\(x)+\(cut)"
    }

    /// 16:9 bzw. 4:3, wenn das Bild bis zu 4 % breiter oder 1 % schmaler ist.
    static func standardAspect(near aspect: Double) -> Double? {
        [16.0 / 9.0, 4.0 / 3.0].first { aspect > $0 * 0.99 && aspect < $0 * 1.04 }
    }

    private static func even(_ value: Double) -> Int {
        Int((value / 2).rounded()) * 2
    }
}
