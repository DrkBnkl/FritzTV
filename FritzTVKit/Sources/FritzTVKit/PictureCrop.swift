import Foundation

/// Beschnitt von PAL-SD-Bildern auf das Standardformat.
///
/// SD-Sender senden 720 × 576 Pixel mit einem Pixel-Seitenverhältnis (SAR) von 16:11 (16:9) bzw.
/// 12:11 (4:3). Über die volle Breite ergibt das etwa 1,82 bzw. 1,36 – etwas breiter als 16:9 bzw. 4:3,
/// weil die Randspalten zur Austastung gehören. In einem 16:9-Fenster oder auf dem Fernseher blieben
/// dadurch schmale schwarze Balken oben und unten. Liegt das Bild bis zu 4 % über einem
/// Standardformat, wird links und rechts auf dieses Format beschnitten.
public enum PictureCrop {
    /// VLC-Beschnitt („16:9“ oder „4:3“) oder `nil`, wenn das Bild bleiben soll, wie es ist.
    public static func standardRatio(width: Double, height: Double, sampleAspect: Double) -> String? {
        guard width > 0, height > 0, sampleAspect > 0 else { return nil }
        let aspect = width * sampleAspect / height
        let standards: [(ratio: Double, name: String)] = [(16.0 / 9.0, "16:9"), (4.0 / 3.0, "4:3")]
        for standard in standards where aspect > standard.ratio * 1.001 && aspect < standard.ratio * 1.04 {
            return standard.name
        }
        return nil
    }
}
