import Foundation
import CoreGraphics
import Combine

/// Observable wrapper around a `PhysicalDisplay` for the menu bar app.
///
/// All DDC traffic runs on a private serial queue, because a single DDC transaction blocks
/// for 30-100 ms. Slider updates are coalesced so dragging a slider produces one write every
/// 40 ms instead of hundreds of queued transactions.
public final class DisplayController: ObservableObject, Identifiable {
    public let id: String
    public let displayID: CGDirectDisplayID
    public let name: String
    public let isBuiltin: Bool
    public let hasDDC: Bool

    @Published public private(set) var brightness: Double = 50
    @Published public private(set) var volume: Double = 50
    @Published public private(set) var isMuted = false
    @Published public private(set) var supportsBrightness = false
    @Published public private(set) var supportsVolume = false
    @Published public private(set) var supportsMute = false
    @Published public private(set) var usesSoftwareDimming = false
    @Published public private(set) var statusMessage = ""
    @Published public private(set) var isReady = false

    private let display: PhysicalDisplay
    private let queue: DispatchQueue
    private var brightnessMax: UInt16 = 100
    private var volumeMax: UInt16 = 100
    private var pendingBrightness: Double?
    private var pendingVolume: Double?
    private var flushScheduled = false
    /// Set when the display acknowledges DDC writes but never answers reads. Plenty of
    /// Samsung panels behave like this; brightness still works, we just cannot query it.
    private var writeOnlyBrightness = false
    private var brightnessReadable = false

    public init(display: PhysicalDisplay) {
        self.display = display
        self.id = display.id
        self.displayID = display.displayID
        self.name = display.name
        self.isBuiltin = display.isBuiltin
        self.hasDDC = display.hasDDC
        self.queue = DispatchQueue(label: "ch.dropflow.screenmix.ddc.\(display.displayID)")
    }

    // MARK: - Reading

    /// Reads brightness, volume and mute state from the display.
    public func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            var brightnessValue: Double?
            var volumeValue: Double?
            var muteValue: Bool?
            var brightnessMax: UInt16?
            var volumeMax: UInt16?

            if self.display.hasDDC {
                if let reply = self.display.read(.brightness) {
                    brightnessMax = reply.max
                    brightnessValue = Double(reply.current) / Double(reply.max) * 100
                }
                if let reply = self.display.read(.volume) {
                    volumeMax = reply.max
                    volumeValue = Double(reply.current) / Double(reply.max) * 100
                }
                if let reply = self.display.read(.mute) {
                    muteValue = reply.current == 1
                }
            }

            DispatchQueue.main.async {
                if let brightnessMax { self.brightnessMax = brightnessMax }
                if let volumeMax { self.volumeMax = volumeMax }
                self.brightnessReadable = brightnessValue != nil
                self.supportsBrightness = brightnessValue != nil || self.writeOnlyBrightness
                self.supportsVolume = volumeValue != nil
                self.supportsMute = muteValue != nil
                if let brightnessValue { self.brightness = brightnessValue }
                if let volumeValue { self.volume = volumeValue }
                if let muteValue { self.isMuted = muteValue }

                if self.display.hasDDC {
                    self.usesSoftwareDimming = brightnessValue == nil && !self.writeOnlyBrightness
                    if brightnessValue != nil {
                        self.statusMessage = ""
                    } else if self.writeOnlyBrightness {
                        self.statusMessage = "DDC (nur schreiben)"
                    } else {
                        self.statusMessage = "DDC ohne Rückmeldung"
                    }
                } else {
                    self.usesSoftwareDimming = true
                    self.statusMessage = "kein DDC"
                }
                self.isReady = true
            }
        }
    }

    // MARK: - Writing

    public func setBrightness(_ percent: Double) {
        let clamped = min(100, max(0, percent))
        brightness = clamped
        pendingBrightness = clamped
        scheduleFlush()
    }

    public func setVolume(_ percent: Double) {
        let clamped = min(100, max(0, percent))
        volume = clamped
        pendingVolume = clamped
        scheduleFlush()
    }

    public func stepBrightness(by delta: Double) {
        setBrightness(brightness + delta)
    }

    public func stepVolume(by delta: Double) {
        setVolume(volume + delta)
    }

    public func toggleMute() {
        setMuted(!isMuted)
    }

    public func setMuted(_ muted: Bool) {
        isMuted = muted
        let value: UInt16 = muted ? 1 : 2
        queue.async { [display = self.display] in
            display.write(.mute, value: value)
        }
    }

    public func resetSoftwareDimming() {
        SoftwareBrightness.reset(displayID: displayID)
        usesSoftwareDimming = false
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            let brightnessValue = self.pendingBrightness
            let volumeValue = self.pendingVolume
            self.pendingBrightness = nil
            self.pendingVolume = nil
            guard brightnessValue != nil || volumeValue != nil else { return }

            self.queue.async {
                if let brightnessValue { self.writeBrightness(brightnessValue) }
                if let volumeValue { self.writeVolume(volumeValue) }
            }
        }
    }

    private func writeBrightness(_ percent: Double) {
        if display.hasDDC {
            let maximum = brightnessReadable ? brightnessMax : 100
            let value = UInt16((percent / 100.0 * Double(maximum)).rounded())
            if display.write(.brightness, value: value) {
                if !brightnessReadable && !writeOnlyBrightness {
                    DispatchQueue.main.async {
                        self.writeOnlyBrightness = true
                        self.supportsBrightness = true
                        self.usesSoftwareDimming = false
                        self.statusMessage = "DDC (nur schreiben)"
                    }
                }
                return
            }
        }
        // No DDC at all, or the panel refused the write: dim through the gamma table so the
        // slider still does something useful.
        SoftwareBrightness.apply(displayID: displayID, percent: percent)
    }

    private func writeVolume(_ percent: Double) {
        guard supportsVolume, display.hasDDC else { return }
        let value = UInt16((percent / 100.0 * Double(volumeMax)).rounded())
        display.write(.volume, value: value)
    }
}
