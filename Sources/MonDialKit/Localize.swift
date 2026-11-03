import Foundation

/// The app is bilingual: German strings are the original, English is the translation.
/// The language follows the system setting and can be forced for testing with
/// `MONDIAL_LANG=de` or `MONDIAL_LANG=en`.
public enum UILanguage: String {
    case german = "de"
    case english = "en"

    public static var current: UILanguage {
        if let override = ProcessInfo.processInfo.environment["MONDIAL_LANG"]?.lowercased(),
           let forced = UILanguage(rawValue: override) {
            return forced
        }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("de") ? .german : .english
    }

    public static var isGerman: Bool { current == .german }
}

/// Picks the German or the English variant. Kept as a free function so call sites stay short
/// and both strings sit next to each other - a missing translation is then obvious.
///
/// `L("Helligkeit", "Brightness")`
/// `L("Nach %@ fehlt der Bildschirm.", "Missing a display after %@", argument)`
public func L(_ german: String, _ english: String, _ arguments: CVarArg...) -> String {
    let template = UILanguage.current == .german ? german : english
    guard !arguments.isEmpty else { return template }
    return String(format: template, arguments: arguments)
}
