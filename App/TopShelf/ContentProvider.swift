import TVServices
import FritzTVKit

final class ContentProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        let channels = TopShelfStore.load()
        let items: [TVTopShelfSectionedItem] = channels.map { ch in
            let item = TVTopShelfSectionedItem(identifier: "channel-\(ch.number)")
            item.title = "\(ch.number) · \(ch.name)"
            item.imageShape = .hdtv

            if let logoURL = ch.logoURL {
                item.setImageURL(logoURL, for: .screenScale1x)
                item.setImageURL(logoURL, for: .screenScale2x)
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
