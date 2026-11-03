import Foundation
import CoreGraphics

/// Fallback dimming for displays that do not answer DDC/CI at all (or for the built-in
/// panel of an iMac, which cannot be dimmed through DDC).
///
/// This manipulates the display's gamma table, which is exactly what "software dimming" in
/// tools like BetterDisplay or Lunar does. The picture gets darker without the backlight
/// actually drawing less power - so it is a fallback, not a replacement for DDC.
public enum SoftwareBrightness {
    private static var lastApplied: [CGDirectDisplayID: Double] = [:]

    /// `percent` is 100 = untouched, 0 = as dark as the gamma table allows (5 %).
    @discardableResult
    public static func apply(displayID: CGDirectDisplayID, percent: Double) -> Bool {
        let clamped = min(100.0, max(0.0, percent))
        let factor = CGGammaValue(max(0.05, clamped / 100.0))
        let error = CGSetDisplayTransferByFormula(
            displayID,
            0, factor, 1,
            0, factor, 1,
            0, factor, 1
        )
        if error == .success {
            lastApplied[displayID] = clamped
            return true
        }
        return false
    }

    /// Restores the untouched gamma table.
    public static func reset(displayID: CGDirectDisplayID) {
        _ = CGSetDisplayTransferByFormula(displayID, 0, 1, 1, 0, 1, 1, 0, 1, 1)
        lastApplied.removeValue(forKey: displayID)
    }

    public static func resetAll() {
        for displayID in lastApplied.keys {
            reset(displayID: displayID)
        }
    }

    public static func isDimmed(displayID: CGDirectDisplayID) -> Bool {
        guard let value = lastApplied[displayID] else { return false }
        return value < 99.5
    }
}
