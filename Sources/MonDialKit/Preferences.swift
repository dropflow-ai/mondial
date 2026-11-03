import Foundation

public enum PreferenceKey {
    public static let hotKeysEnabled = "hotKeysEnabled"
    public static let mediaKeysEnabled = "mediaKeysEnabled"
    public static let showPercentage = "showPercentage"
    public static let stepSize = "stepSize"
    public static let selectedDisplayUUID = "selectedDisplayUUID"
}

public enum Preferences {
    public static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PreferenceKey.hotKeysEnabled: true,
            PreferenceKey.mediaKeysEnabled: false,
            PreferenceKey.showPercentage: true,
            PreferenceKey.stepSize: 6.25
        ])
    }

    public static var hotKeysEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: PreferenceKey.hotKeysEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.hotKeysEnabled) }
    }

    public static var mediaKeysEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: PreferenceKey.mediaKeysEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.mediaKeysEnabled) }
    }

    public static var stepSize: Double {
        get {
            let value = UserDefaults.standard.double(forKey: PreferenceKey.stepSize)
            return value > 0 ? value : 6.25
        }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.stepSize) }
    }
}

/// Small helper used by `mondialctl doctor` and the CLI's error messages.
public enum Diagnostics {
    public static var architecture: String {
        #if arch(arm64)
        return "arm64 (Apple Silicon)"
        #elseif arch(x86_64)
        return "x86_64 (Intel)"
        #else
        return L("unbekannt", "unknown")
        #endif
    }

    public static var ddcBackendDescription: String {
        #if arch(arm64)
        return PrivateAPI.shared.supportsIOAVService
            ? L("IOAVService (privat, Apple Silicon)", "IOAVService (private, Apple Silicon)")
            : L("IOAVService nicht verfügbar", "IOAVService unavailable")
        #elseif arch(x86_64)
        return "IOI2CInterface (Intel)"
        #else
        return L("nicht unterstützt", "unsupported")
        #endif
    }

    public static var operatingSystem: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
