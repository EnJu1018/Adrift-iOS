import Foundation

enum APIConfig {
    // Includes the reverse-proxy prefix, exactly like Web's API_URL.
    static let baseURL = URL(string: "https://adrifttw.com/api")!

    static func assetURL(from path: String?, baseURL: URL = baseURL) -> URL? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return nil }
        if let url = URL(string: path), let scheme = url.scheme {
            return ["https", "http"].contains(scheme.lowercased()) ? url : nil
        }

        let trimmedBase = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedPath.isEmpty else { return nil }
        let prefix = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !prefix.isEmpty, trimmedPath.hasPrefix(prefix + "/") {
            trimmedPath.removeFirst(prefix.count + 1)
        }
        return URL(string: "\(trimmedBase)/\(trimmedPath)")
    }
}
