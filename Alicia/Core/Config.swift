import Foundation

/// Backend connection settings for the live Alicia service.
///
/// Resolution order (first hit wins, per key):
///   1. UserDefaults — "alicia.baseURL" / "alicia.token" (set once from a
///      debugger or a future in-app settings screen).
///   2. The bundled `Secrets.plist` (gitignored — copy `Secrets.example.plist`
///      next to it and fill in your values).
///
/// If no complete configuration is found the app falls back to
/// `MockAliciaService`, so the repo stays runnable for anyone who clones it.
enum AliciaConfig {
    private static var secrets: [String: Any] {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return dict
    }

    static var baseURL: URL? {
        let raw = UserDefaults.standard.string(forKey: "alicia.baseURL")
            ?? secrets["BaseURL"] as? String
        guard let raw, let url = URL(string: raw), url.scheme != nil else { return nil }
        return url
    }

    static var token: String? {
        let raw = UserDefaults.standard.string(forKey: "alicia.token")
            ?? secrets["Token"] as? String
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return raw.trimmingCharacters(in: .whitespaces)
    }

    /// The service the app should run with: live when fully configured,
    /// mock otherwise.
    static func makeService() -> AliciaService {
        if let base = baseURL, let token {
            return LiveAliciaService(baseURL: base, token: token)
        }
        return MockAliciaService()
    }
}
