import TVServices
import FritzTVKit

final class ContentProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        let channels = TopShelfStore.load()
        let items: [TVTopShelfSectionedItem] = channels.map { ch in
            let item = TVTopShelfSectionedItem(identifier: "channel-\(ch.number)")
            item.title = "\(ch.number) · \(ch.name)"
            item.imageShape = .square

            // Suche nach hochauflösendem gebündelten Kachel-Icon
            var candidateSlugs = ChannelLogo.candidateURLs(for: ch.name).map { $0.deletingPathExtension().lastPathComponent }
            let groupSlug = ChannelLogo.slug(for: ch.groupKey)
            if !candidateSlugs.contains(groupSlug) {
                candidateSlugs.append(groupSlug)
            }

            var imageAssigned = false
            for slug in candidateSlugs {
                if let url2x = Bundle.main.url(forResource: "channel_\(slug)@2x", withExtension: "png") {
                    let url1x = Bundle.main.url(forResource: "channel_\(slug)", withExtension: "png") ?? url2x
                    item.setImageURL(url1x, for: .screenScale1x)
                    item.setImageURL(url2x, for: .screenScale2x)
                    imageAssigned = true
                    break
                }
            }

            if !imageAssigned {
                if let gen2x = Bundle.main.url(forResource: "channel_generic@2x", withExtension: "png") {
                    let gen1x = Bundle.main.url(forResource: "channel_generic", withExtension: "png") ?? gen2x
                    item.setImageURL(gen1x, for: .screenScale1x)
                    item.setImageURL(gen2x, for: .screenScale2x)
                } else if let logoURL = ch.logoURL {
                    item.setImageURL(logoURL, for: .screenScale1x)
                    item.setImageURL(logoURL, for: .screenScale2x)
                }
            }

            // Nummer plus Senderschlüssel: Die App wählt über den Schlüssel, falls sich die
            // Platznummern seit dem letzten Speichern verschoben haben.
            var components = URLComponents()
            components.scheme = "fritztv"
            components.host = "channel"
            components.path = "/\(ch.number)"
            components.queryItems = [URLQueryItem(name: "key", value: ch.groupKey)]
            if let url = components.url {
                item.playAction = TVTopShelfAction(url: url)
                item.displayAction = TVTopShelfAction(url: url)
            }
            return item
        }

        let section = TVTopShelfItemCollection(items: items)
        section.title = "Sender"
        let content = TVTopShelfSectionedContent(sections: [section])
        completionHandler(content)
    }
}
