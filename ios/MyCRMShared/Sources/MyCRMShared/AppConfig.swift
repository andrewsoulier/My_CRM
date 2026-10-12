import Foundation

/// Shared configuration for the app, keyboard, and iMessage extension via App Group.
public enum AppConfig {
    public static let appGroupId = "group.com.mycrm.shared"
    private static let baseURLKey = "crm.baseURL"
    private static let tokenKey = "crm.apiToken"

    public static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? .standard
    }

    public static var baseURL: URL? {
        get {
            guard let raw = sharedDefaults.string(forKey: baseURLKey),
                  let url = URL(string: raw),
                  !raw.isEmpty
            else { return nil }
            return url
        }
        set {
            sharedDefaults.set(newValue?.absoluteString, forKey: baseURLKey)
        }
    }

    public static var apiToken: String? {
        get { sharedDefaults.string(forKey: tokenKey) }
        set { sharedDefaults.set(newValue, forKey: tokenKey) }
    }

    public static var isConfigured: Bool {
        baseURL != nil && !(apiToken ?? "").isEmpty
    }
}
