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
    writeErr("\(L("Fehler", "Error")): \(message)\n")
    exit(code)
}

let usageGerman = """
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

let usageEnglish = """
mondialctl \(MonDialVersion.string) - control brightness and volume of external displays (DDC/CI)

USAGE
  mondialctl list [--json]
  mondialctl get <attribute> [-d <display>]
  mondialctl set <attribute> <value> [-d <display>]
  mondialctl step <attribute> <delta> [-d <display>]
  mondialctl mute on|off|toggle [-d <display>]
  mondialctl doctor [--json]

ATTRIBUTES
  brightness | helligkeit     brightness in percent
  volume | lautstaerke        volume in percent
  contrast | kontrast         contrast in percent
  mute                        mute state (on/off/toggle)

DISPLAY (-d)
  1, 2, 3 ...                 index from "mondialctl list"
  <uuid>                      UUID (a substring is enough)
  <name>                      part of the name, e.g. "LG"

EXAMPLES
  mondialctl list
  mondialctl get brightness
  mondialctl set volume 35
  mondialctl step brightness -6
  mondialctl mute toggle
  mondialctl set brightness 40 -d "LG"

OPTIONS
  --json                      machine readable output
  -h, --help                  this help
"""

func pad(_ text: String, _ width: Int = 16) -> String {
    text.padding(toLength: width, withPad: " ", startingAt: 0)
}

let usage = UILanguage.isGerman ? usageGerman : usageEnglish

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
        guard index < arguments.count else { fail(L("Nach %@ fehlt der Bildschirm.", "Missing a display after %@", argument)) }
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
        guard let first = displays.first else { fail(L("Kein Bildschirm gefunden.", "No display found.")) }
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
    fail(L("Bildschirm \"%@\" nicht gefunden. Nutze \"mondialctl list\".", "Display \"%@\" not found. Try \"mondialctl list\".", selector))
}

func parseAttribute(_ raw: String) -> VCP {
    switch raw.lowercased() {
    case "brightness", "helligkeit", "b", "h": return .brightness
    case "volume", "lautstaerke", "lautstärke", "v", "l": return .volume
    case "contrast", "kontrast", "c": return .contrast
    case "mute", "stumm": return .mute
    default: fail(L("Unbekanntes Attribut \"%@\".", "Unknown attribute \"%@\".", raw))
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
        writeErr("\(L("Kein Bildschirm gefunden.", "No display found."))\n")
        exit(1)
    }

    for (offset, display) in displays.enumerated() {
        let brightness = display.read(.brightness)
        let volume = display.read(.volume)
        var details: [String] = []
        details.append(display.isBuiltin ? L("intern", "internal") : L("extern", "external"))
        details.append(display.hasDDC ? "DDC" : L("kein DDC", "no DDC"))
        if let brightness {
            details.append("\(L("Helligkeit", "brightness")) \(percentString(current: brightness.current, max: brightness.max)) %")
        }
        if let volume {
            details.append("\(L("Lautstärke", "volume")) \(percentString(current: volume.current, max: volume.max)) %")
        }
        writeOut("[\(offset + 1)] \(display.name)\n")
        writeOut("    \(details.joined(separator: " · "))\n")
        writeOut("    UUID \(display.id)\n")
    }
    exit(0)
}

func runGet() {
    guard positional.count >= 2 else { fail(L("Aufruf: mondialctl get <attribut>", "Usage: mondialctl get <attribute>")) }
    let attribute = parseAttribute(positional[1])
    let display = selectDisplay(from: allDisplays(), selector: displaySelector)

    guard display.hasDDC else { fail(L("%@ unterstützt kein DDC/CI.", "%@ does not support DDC/CI.", display.name)) }
    guard let reply = display.read(attribute) else {
        fail(L("%@ antwortet nicht auf %@.", "%@ does not answer for %@.", display.name, attribute.localizedName), code: 2)
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
    guard positional.count >= 3 else { fail(L("Aufruf: mondialctl set <attribut> <wert>", "Usage: mondialctl set <attribute> <value>")) }
    let attribute = parseAttribute(positional[1])
    let value = positional[2]
    let display = selectDisplay(from: allDisplays(), selector: displaySelector)

    guard display.hasDDC else { fail(L("%@ unterstützt kein DDC/CI.", "%@ does not support DDC/CI.", display.name)) }

    if attribute == .mute {
        let target: UInt16
        switch value.lowercased() {
        case "on", "an", "1", "true": target = 1
        case "off", "aus", "2", "false": target = 2
        case "toggle": target = (display.read(.mute)?.current == 1) ? 2 : 1
        default: fail(L("Für \"mute\" erwarte ich on, off oder toggle.", "For \"mute\" use on, off or toggle."))
        }
        guard display.write(.mute, value: target) else { fail(L("Schreiben fehlgeschlagen.", "Writing failed."), code: 2) }
        writeOut(target == 1 ? "on\n" : "off\n")
        exit(0)
    }

    guard let percent = Double(value.replacingOccurrences(of: "%", with: "")) else {
        fail(L("\"%@\" ist keine Zahl.", "\"%@\" is not a number.", value))
    }
    let clamped = min(100, max(0, percent))
    let maxValue = display.read(attribute)?.max ?? 100
    let raw = UInt16((clamped / 100.0 * Double(maxValue)).rounded())

    guard display.write(attribute, value: raw) else { fail(L("Schreiben fehlgeschlagen.", "Writing failed."), code: 2) }
    writeOut("\(Int(clamped.rounded()))\n")
    exit(0)
}

func runStep() {
    guard positional.count >= 3 else { fail(L("Aufruf: mondialctl step <attribut> <delta>", "Usage: mondialctl step <attribute> <delta>")) }
    let attribute = parseAttribute(positional[1])
    if attribute == .mute {
        let display = selectDisplay(from: allDisplays(), selector: displaySelector)
        let current = display.read(.mute)?.current ?? 2
        let target: UInt16 = current == 1 ? 2 : 1
        guard display.write(.mute, value: target) else { fail(L("Schreiben fehlgeschlagen.", "Writing failed."), code: 2) }
        writeOut(target == 1 ? "on\n" : "off\n")
        exit(0)
    }

    guard let delta = Double(positional[2]) else { fail(L("\"%@\" ist keine Zahl.", "\"%@\" is not a number.", positional[2])) }
    let display = selectDisplay(from: allDisplays(), selector: displaySelector)
    guard display.hasDDC else { fail(L("%@ unterstützt kein DDC/CI.", "%@ does not support DDC/CI.", display.name)) }
    guard let reply = display.read(attribute) else { fail(L("Lesen fehlgeschlagen.", "Reading failed."), code: 2) }

    let currentPercent = Double(reply.current) / Double(reply.max) * 100
    let targetPercent = min(100, max(0, currentPercent + delta))
    let raw = UInt16((targetPercent / 100.0 * Double(reply.max)).rounded())
    guard display.write(attribute, value: raw) else { fail(L("Schreiben fehlgeschlagen.", "Writing failed."), code: 2) }
    writeOut("\(Int(targetPercent.rounded()))\n")
    exit(0)
}

func runMute() {
    let value = positional.count >= 2 ? positional[1] : "toggle"
    let display = selectDisplay(from: allDisplays(), selector: displaySelector)
    guard display.hasDDC else { fail(L("%@ unterstützt kein DDC/CI.", "%@ does not support DDC/CI.", display.name)) }

    let target: UInt16
    switch value.lowercased() {
    case "on", "an", "1", "true": target = 1
    case "off", "aus", "2", "false": target = 2
    case "toggle": target = (display.read(.mute)?.current == 1) ? 2 : 1
    default: fail(L("Für \"mute\" erwarte ich on, off oder toggle.", "For \"mute\" use on, off or toggle."))
    }

    guard display.write(.mute, value: target) else { fail(L("Schreiben fehlgeschlagen.", "Writing failed."), code: 2) }
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
    writeOut("\(pad(L("Architektur", "Architecture")))\(Diagnostics.architecture)\n")
    writeOut("\(pad(L("DDC-Backend", "DDC backend")))\(backend)\n")
    writeOut("\(pad(L("Bildschirme", "Displays")))\(displays.count)\n\n")

    for (offset, display) in displays.enumerated() {
        writeOut("[\(offset + 1)] \(display.name)\n")
        writeOut("    UUID        \(display.id)\n")
        writeOut("    Display-ID  \(display.displayID)\n")
        writeOut("    Vendor      \(display.vendor) / Model \(display.model) / Serial \(display.serial)\n")
        writeOut("    \(pad(L("Typ", "Type"), 12))\(display.isBuiltin ? L("intern", "internal") : L("extern", "external"))\n")
        writeOut("    Transport   \(display.debugDescription)\n")

        for attribute in [VCP.brightness, .contrast, .volume, .mute] {
            let clock = startClock()
            let reply = display.read(attribute)
            let duration = elapsedMilliseconds(since: clock)
            let label = attribute.localizedName.padding(toLength: 12, withPad: " ", startingAt: 0)
            if let reply {
                let value = attribute == .mute
                    ? (reply.current == 1 ? L("an", "on") : L("aus", "off"))
                    : "\(percentString(current: reply.current, max: reply.max)) % (max \(reply.max))"
                writeOut("    \(label)\(value)  [\(Int(duration)) ms]\n")
            } else {
                writeOut("    \(label)\(L("keine Antwort", "no answer"))  [\(Int(duration)) ms]\n")
            }
        }
        writeOut("\n")
    }

    if displays.allSatisfy({ !$0.hasDDC }) {
        writeOut(L("Hinweis: kein Bildschirm hat einen DDC-Transport. Prüfe, ob im Monitor-OSD\n",
                   "Note: no display has a DDC transport. Check whether \"DDC/CI\" is enabled in\n"))
        writeOut(L("\"DDC/CI\" aktiviert ist und ob der Monitor per DisplayPort, USB-C oder HDMI\n",
                   "the monitor menu and whether the display is connected through DisplayPort,\n"))
        writeOut(L("angeschlossen ist (Adapter können DDC blockieren).\n",
                   "USB-C or HDMI (adapters can block DDC).\n"))
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
    fail(L("Unbekanntes Kommando \"%@\". Nutze --help.", "Unknown command \"%@\". Try --help.", command))
}
