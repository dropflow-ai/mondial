import Foundation
import MonDialKit

// MARK: - Helpers

func writeOut(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
}

func writeErr(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    writeErr("Fehler: \(message)\n")
    exit(code)
}

let usage = """
mondialctl \(MonDialVersion.string) - Helligkeit und Lautstärke externer Bildschirme steuern (DDC/CI)

AUFRUF
  mondialctl list [--json]
  mondialctl get <attribut> [-d <bildschirm>]
  mondialctl set <attribut> <wert> [-d <bildschirm>]
  mondialctl step <attribut> <delta> [-d <bildschirm>]
  mondialctl mute on|off|toggle [-d <bildschirm>]
  mondialctl doctor [--json]

ATTRIBUTE
  brightness | helligkeit     Helligkeit in Prozent
  volume | lautstaerke        Lautstärke in Prozent
  contrast | kontrast         Kontrast in Prozent
  mute                        Stummschaltung (on/off/toggle)

BILDSCHIRM (-d)
  1, 2, 3 ...                 Index aus "mondialctl list"
  <uuid>                      UUID (auch Teilstring)
  <name>                      Teilstring des Namens, z.B. "LG"

BEISPIELE
  mondialctl list
  mondialctl get brightness
  mondialctl set volume 35
  mondialctl step brightness -6
  mondialctl mute toggle
  mondialctl set brightness 40 -d "LG"

OPTIONEN
  --json                      Maschinenlesbare Ausgabe
  -h, --help                  Diese Hilfe
"""

// MARK: - Argument parsing

var positional: [String] = []
var displaySelector: String?
var wantsJSON = false

var index = 0
let arguments = Array(CommandLine.arguments.dropFirst())
while index < arguments.count {
    let argument = arguments[index]
    switch argument {
    case "-d", "--display":
        index += 1
        guard index < arguments.count else { fail("Nach \(argument) fehlt der Bildschirm.") }
        displaySelector = arguments[index]
    case "--json":
        wantsJSON = true
    case "-h", "--help":
        writeOut(usage)
        exit(0)
    case "-v", "--version":
        writeOut("mondialctl \(MonDialVersion.string)\n")
        exit(0)
    default:
        positional.append(argument)
    }
    index += 1
}

guard let command = positional.first else {
    writeOut(usage)
    exit(0)
}

// MARK: - Display selection

func allDisplays() -> [PhysicalDisplay] {
    DisplayManager.refresh()
}

func selectDisplay(from displays: [PhysicalDisplay], selector: String?) -> PhysicalDisplay {
    guard let selector, !selector.isEmpty else {
        if let external = displays.first(where: { !$0.isBuiltin && $0.hasDDC }) { return external }
        if let external = displays.first(where: { !$0.isBuiltin }) { return external }
        guard let first = displays.first else { fail("Kein Bildschirm gefunden.") }
        return first
    }

    if let number = Int(selector), number >= 1, number <= displays.count {
        return displays[number - 1]
    }

    let lowered = selector.lowercased()
    if let match = displays.first(where: { $0.id.lowercased().hasPrefix(lowered) }) {
        return match
    }
    if let match = displays.first(where: { $0.name.lowercased().contains(lowered) }) {
        return match
    }
    fail("Bildschirm \"\(selector)\" nicht gefunden. Nutze \"mondialctl list\".")
}

func parseAttribute(_ raw: String) -> VCP {
    switch raw.lowercased() {
    case "brightness", "helligkeit", "b", "h": return .brightness
    case "volume", "lautstaerke", "lautstärke", "v", "l": return .volume
    case "contrast", "kontrast", "c": return .contrast
    case "mute", "stumm": return .mute
    default: fail("Unbekanntes Attribut \"\(raw)\".")
    }
}

func percentString(current: UInt16, max: UInt16) -> String {
    guard max > 0 else { return "0" }
    return String(Int((Double(current) / Double(max) * 100).rounded()))
}

func jsonEscape(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

// MARK: - Commands

func runList() {
    let displays = allDisplays()
    if wantsJSON {
        var entries: [String] = []
        for (offset, display) in displays.enumerated() {
            let brightness = display.read(.brightness)
            let volume = display.read(.volume)
            let fields: [String] = [
                "\"index\": \(offset + 1)",
                "\"name\": \"\(jsonEscape(display.name))\"",
                "\"uuid\": \"\(jsonEscape(display.id))\"",
                "\"id\": \(display.displayID)",
                "\"vendor\": \(display.vendor)",
                "\"model\": \(display.model)",
                "\"serial\": \(display.serial)",
                "\"builtin\": \(display.isBuiltin)",
                "\"ddc\": \(display.hasDDC)",
                "\"brightness\": \(brightness.map { String($0.current) } ?? "null")",
                "\"brightnessMax\": \(brightness.map { String($0.max) } ?? "null")",
                "\"volume\": \(volume.map { String($0.current) } ?? "null")",
                "\"volumeMax\": \(volume.map { String($0.max) } ?? "null")"
            ]
            entries.append("{\(fields.joined(separator: ", "))}")
        }
        writeOut("[\(entries.joined(separator: ",\n "))]\n")
        exit(0)
    }

    guard !displays.isEmpty else {
        writeErr("Kein Bildschirm gefunden.\n")
        exit(1)
    }

    for (offset, display) in displays.enumerated() {
        let brightness = display.read(.brightness)
        let volume = display.read(.volume)
        var details: [String] = []
        details.append(display.isBuiltin ? "intern" : "extern")
        details.append(display.hasDDC ? "DDC" : "kein DDC")
        if let brightness {
            details.append("Helligkeit \(percentString(current: brightness.current, max: brightness.max)) %")
        }
        if let volume {
            details.append("Lautstärke \(percentString(current: volume.current, max: volume.max)) %")
        }
        writeOut("[\(offset + 1)] \(display.name)\n")
        writeOut("    \(details.joined(separator: " · "))\n")
        writeOut("    UUID \(display.id)\n")
    }
    exit(0)
}

func runGet() {
    guard positional.count >= 2 else { fail("Aufruf: mondialctl get <attribut>") }
    let attribute = parseAttribute(positional[1])
    let display = selectDisplay(from: allDisplays(), selector: displaySelector)

    guard display.hasDDC else { fail("\(display.name) unterstützt kein DDC/CI.") }
    guard let reply = display.read(attribute) else {
        fail("\(display.name) antwortet nicht auf \(attribute.localizedName).", code: 2)
    }

    switch attribute {
    case .mute:
        writeOut(reply.current == 1 ? "on\n" : "off\n")
    default:
        writeOut("\(percentString(current: reply.current, max: reply.max))\n")
    }
    exit(0)
}

func runSet() {
    guard positional.count >= 3 else { fail("Aufruf: mondialctl set <attribut> <wert>") }
    let attribute = parseAttribute(positional[1])
    let value = positional[2]
    let display = selectDisplay(from: allDisplays(), selector: displaySelector)

    guard display.hasDDC else { fail("\(display.name) unterstützt kein DDC/CI.") }

    if attribute == .mute {
        let target: UInt16
        switch value.lowercased() {
        case "on", "an", "1", "true": target = 1
        case "off", "aus", "2", "false": target = 2
        case "toggle": target = (display.read(.mute)?.current == 1) ? 2 : 1
        default: fail("Für \"mute\" erwarte ich on, off oder toggle.")
        }
        guard display.write(.mute, value: target) else { fail("Schreiben fehlgeschlagen.", code: 2) }
        writeOut(target == 1 ? "on\n" : "off\n")
        exit(0)
    }

    guard let percent = Double(value.replacingOccurrences(of: "%", with: "")) else {
        fail("\"\(value)\" ist keine Zahl.")
    }
    let clamped = min(100, max(0, percent))
    let maxValue = display.read(attribute)?.max ?? 100
    let raw = UInt16((clamped / 100.0 * Double(maxValue)).rounded())

    guard display.write(attribute, value: raw) else { fail("Schreiben fehlgeschlagen.", code: 2) }
    writeOut("\(Int(clamped.rounded()))\n")
    exit(0)
}

func runStep() {
    guard positional.count >= 3 else { fail("Aufruf: mondialctl step <attribut> <delta>") }
    let attribute = parseAttribute(positional[1])
    if attribute == .mute {
        let display = selectDisplay(from: allDisplays(), selector: displaySelector)
        let current = display.read(.mute)?.current ?? 2
        let target: UInt16 = current == 1 ? 2 : 1
        guard display.write(.mute, value: target) else { fail("Schreiben fehlgeschlagen.", code: 2) }
        writeOut(target == 1 ? "on\n" : "off\n")
        exit(0)
    }

    guard let delta = Double(positional[2]) else { fail("\"\(positional[2])\" ist keine Zahl.") }
    let display = selectDisplay(from: allDisplays(), selector: displaySelector)
    guard display.hasDDC else { fail("\(display.name) unterstützt kein DDC/CI.") }
    guard let reply = display.read(attribute) else { fail("Lesen fehlgeschlagen.", code: 2) }

    let currentPercent = Double(reply.current) / Double(reply.max) * 100
    let targetPercent = min(100, max(0, currentPercent + delta))
    let raw = UInt16((targetPercent / 100.0 * Double(reply.max)).rounded())
    guard display.write(attribute, value: raw) else { fail("Schreiben fehlgeschlagen.", code: 2) }
    writeOut("\(Int(targetPercent.rounded()))\n")
    exit(0)
}

func runMute() {
    let value = positional.count >= 2 ? positional[1] : "toggle"
    let display = selectDisplay(from: allDisplays(), selector: displaySelector)
    guard display.hasDDC else { fail("\(display.name) unterstützt kein DDC/CI.") }

    let target: UInt16
    switch value.lowercased() {
    case "on", "an", "1", "true": target = 1
    case "off", "aus", "2", "false": target = 2
    case "toggle": target = (display.read(.mute)?.current == 1) ? 2 : 1
    default: fail("Für \"mute\" erwarte ich on, off oder toggle.")
    }

    guard display.write(.mute, value: target) else { fail("Schreiben fehlgeschlagen.", code: 2) }
    writeOut(target == 1 ? "on\n" : "off\n")
    exit(0)
}

func startClock() -> UInt64 {
    DispatchTime.now().uptimeNanoseconds
}

func elapsedMilliseconds(since start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

func runDoctor() {
    let displays = allDisplays()
    let backend = Diagnostics.ddcBackendDescription

    if wantsJSON {
        var entries: [String] = []
        for display in displays {
            let brightness = display.read(.brightness)
            let volume = display.read(.volume)
            let mute = display.read(.mute)
            let fields = [
                "\"name\": \"\(jsonEscape(display.name))\"",
                "\"uuid\": \"\(jsonEscape(display.id))\"",
                "\"builtin\": \(display.isBuiltin)",
                "\"transport\": \"\(jsonEscape(display.debugDescription))\"",
                "\"brightness\": \(brightness.map { String($0.current) } ?? "null")",
                "\"volume\": \(volume.map { String($0.current) } ?? "null")",
                "\"mute\": \(mute.map { String($0.current) } ?? "null")"
            ]
            entries.append("{\(fields.joined(separator: ", "))}")
        }
        writeOut("{\"os\": \"\(Diagnostics.operatingSystem)\", \"arch\": \"\(Diagnostics.architecture)\", \"backend\": \"\(backend)\", \"displays\": [\(entries.joined(separator: ", "))]}\n")
        exit(0)
    }

    writeOut("MonDial \(MonDialVersion.string)\n")
    writeOut("System          \(Diagnostics.operatingSystem)\n")
    writeOut("Architektur     \(Diagnostics.architecture)\n")
    writeOut("DDC-Backend     \(backend)\n")
    writeOut("Bildschirme     \(displays.count)\n\n")

    for (offset, display) in displays.enumerated() {
        writeOut("[\(offset + 1)] \(display.name)\n")
        writeOut("    UUID        \(display.id)\n")
        writeOut("    Display-ID  \(display.displayID)\n")
        writeOut("    Vendor      \(display.vendor) / Model \(display.model) / Serial \(display.serial)\n")
        writeOut("    Typ         \(display.isBuiltin ? "intern" : "extern")\n")
        writeOut("    Transport   \(display.debugDescription)\n")

        for attribute in [VCP.brightness, .contrast, .volume, .mute] {
            let clock = startClock()
            let reply = display.read(attribute)
            let duration = elapsedMilliseconds(since: clock)
            let label = attribute.localizedName.padding(toLength: 12, withPad: " ", startingAt: 0)
            if let reply {
                let value = attribute == .mute
                    ? (reply.current == 1 ? "an" : "aus")
                    : "\(percentString(current: reply.current, max: reply.max)) % (max \(reply.max))"
                writeOut("    \(label)\(value)  [\(Int(duration)) ms]\n")
            } else {
                writeOut("    \(label)keine Antwort  [\(Int(duration)) ms]\n")
            }
        }
        writeOut("\n")
    }

    if displays.allSatisfy({ !$0.hasDDC }) {
        writeOut("Hinweis: kein Bildschirm hat einen DDC-Transport. Prüfe, ob im Monitor-OSD\n")
        writeOut("\"DDC/CI\" aktiviert ist und ob der Monitor per DisplayPort, USB-C oder HDMI\n")
        writeOut("angeschlossen ist (Adapter können DDC blockieren).\n")
    }
    exit(0)
}

switch command.lowercased() {
case "list", "ls":
    runList()
case "get":
    runGet()
case "set":
    runSet()
case "step", "chg":
    runStep()
case "mute":
    runMute()
case "doctor", "diag":
    runDoctor()
case "help":
    writeOut(usage)
    exit(0)
default:
    fail("Unbekanntes Kommando \"\(command)\". Nutze --help.")
}
