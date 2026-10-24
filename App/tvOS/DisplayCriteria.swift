import AVKit
import CoreMedia
import UIKit

/// Bittet tvOS, die Bildwiederholrate auf 50 Hz umzuschalten (deutsches Fernsehen).
/// Wirkt nur, wenn am Apple TV unter Einstellungen › Video und Audio
/// „Inhalt anpassen › Bildrate“ eingeschaltet ist.
enum DisplayCriteria {
    @MainActor
    static func request50Hz() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first else { return }

        var description: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                       codecType: kCMVideoCodecType_H264,
                                       width: 1920,
                                       height: 1080,
                                       extensions: nil,
                                       formatDescriptionOut: &description)
        guard let description else { return }
        window.avDisplayManager.preferredDisplayCriteria = AVDisplayCriteria(refreshRate: 50,
                                                                             formatDescription: description)
    }
}
