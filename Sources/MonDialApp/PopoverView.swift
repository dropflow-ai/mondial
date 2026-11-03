import SwiftUI
import AppKit
import MonDialKit

struct PopoverView: View {
    @ObservedObject var store: DisplayStore
    @StateObject private var audio = AudioOutputStore()

    @State private var hotKeysEnabled = Preferences.hotKeysEnabled
    @State private var mediaKeysEnabled = Preferences.mediaKeysEnabled
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var showSettings = false
    @State private var showDiagnostics = false
    @State private var permissionWarning = false

    private let accent = Color(red: 0.0, green: 0.72, blue: 0.76)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if store.displays.isEmpty {
                Text("Kein Bildschirm gefunden.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.displays) { display in
                    DisplaySection(display: display, accent: accent)
                }
            }

            outputRow

            Divider()

            if showSettings {
                settings
            }

            if showDiagnostics {
                diagnosticsSection
            }

            footer
        }
        .padding(14)
        .frame(width: 340)
        .tint(accent)
        .onAppear { audio.refresh() }
    }

    private var outputRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "hifispeaker.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("Ausgabe")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Menu {
                ForEach(audio.devices) { device in
                    Button {
                        audio.select(device)
                    } label: {
                        if device.id == audio.currentID {
                            Label("\(device.name)  (\(device.detail))", systemImage: "checkmark")
                        } else {
                            Text("\(device.name)  (\(device.detail))")
                        }
                    }
                }
                Divider()
                Button("Liste aktualisieren") { audio.refresh() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: audio.devices.first { $0.id == audio.currentID }?.symbol ?? "speaker.wave.2")
                        .font(.system(size: 10))
                    Text(audio.currentName)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Audioausgabe des Macs umschalten")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.max.fill")
                .foregroundStyle(accent)
            Text("MonDial")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showSettings.toggle() }
            } label: {
                Image(systemName: showSettings ? "gearshape.fill" : "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Einstellungen")
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Tastenkürzel ⌃⌥↑ / ⌃⌥↓", isOn: $hotKeysEnabled)
                .onChange(of: hotKeysEnabled) { value in
                    Preferences.hotKeysEnabled = value
                    if value {
                        HotKeyManager.shared.start()
                    } else {
                        HotKeyManager.shared.stop()
                    }
                }

            Toggle("Medientasten abfangen (F1 / F2 / F10–F12)", isOn: $mediaKeysEnabled)
                .onChange(of: mediaKeysEnabled) { value in
                    if value {
                        let started = MediaKeyMonitor.shared.start()
                        permissionWarning = !started
                        if !started {
                            mediaKeysEnabled = false
                            Preferences.mediaKeysEnabled = false
                        } else {
                            Preferences.mediaKeysEnabled = true
                        }
                    } else {
                        MediaKeyMonitor.shared.stop()
                        Preferences.mediaKeysEnabled = false
                    }
                }

            if permissionWarning {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dafür braucht MonDial die Berechtigung „Bedienungshilfen“.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Systemeinstellungen öffnen") {
                        openAccessibilitySettings()
                    }
                    .font(.caption)
                }
            }

            Toggle("Beim Anmelden öffnen", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { value in
                    LoginItem.setEnabled(value)
                }
        }
        .font(.callout)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                store.refresh(force: true)
            } label: {
                Label("Neu scannen", systemImage: "arrow.clockwise")
                    .font(.callout)
            }
            .buttonStyle(.borderless)

            Button {
                showDiagnostics.toggle()
                if showDiagnostics {
                    store.displays.forEach { $0.runDiagnostics() }
                }
            } label: {
                Label("Diagnose", systemImage: "stethoscope")
                    .font(.callout)
            }
            .buttonStyle(.borderless)

            Spacer()

            Button("Beenden") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Diagnose")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button("Kopieren") { copyDiagnostics() }
                    .font(.caption)
                    .buttonStyle(.borderless)
                Button("Aktualisieren") { store.displays.forEach { $0.runDiagnostics() } }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if store.displays.allSatisfy({ $0.diagnostics.isEmpty }) {
                        Text("Wird ermittelt …")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.displays) { display in
                        ForEach(Array(display.diagnostics.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 9, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            .frame(height: 140)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
        }
    }

    private func copyDiagnostics() {
        var lines: [String] = []
        lines.append("MonDial \(MonDialVersion.string)")
        lines.append("System: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Architektur: \(Diagnostics.architecture)")
        lines.append("Backend: \(Diagnostics.ddcBackendDescription)")
        lines.append("")
        for display in store.displays {
            lines.append(contentsOf: display.diagnostics)
            lines.append("")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct DisplaySection: View {
    @ObservedObject var display: DisplayController
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(display.name)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if display.hasDDC {
                    Button {
                        display.setForceSoftwareDimming(!display.forceSoftwareDimming)
                    } label: {
                        Text("Gamma")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(display.forceSoftwareDimming ? accent.opacity(0.25) : Color.primary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.borderless)
                    .help("Helligkeit über die Gamma-Tabelle dimmen, wenn der Monitor DDC-Befehle ignoriert")
                }
                if !display.statusMessage.isEmpty {
                    Text(display.statusMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if !display.isReady {
                ProgressView().controlSize(.small)
            } else {
                if display.supportsBrightness || display.usesSoftwareDimming {
                    ControlRow(
                        icon: "sun.max",
                        value: Binding(get: { display.brightness },
                                       set: { display.setBrightness($0) }),
                        isEnabled: true
                    )
                } else {
                    UnavailableRow(title: "Helligkeit ohne DDC nicht steuerbar")
                }

                if display.supportsVolume {
                    HStack(spacing: 6) {
                        ControlRow(
                            icon: display.isMuted ? "speaker.slash" : "speaker.wave.2",
                            value: Binding(get: { display.volume },
                                           set: { display.setVolume($0) }),
                            isEnabled: true
                        )
                        if display.supportsMute {
                            Button {
                                display.toggleMute()
                            } label: {
                                Image(systemName: display.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                            .help(display.isMuted ? "Ton einschalten" : "Stummschalten")
                        }
                    }
                } else if display.hasDDC {
                    UnavailableRow(title: "Lautstärke wird von diesem Bildschirm nicht gemeldet")
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.05)))
        .onAppear { display.refresh() }
    }
}

private struct ControlRow: View {
    let icon: String
    @Binding var value: Double
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 14)
                .foregroundStyle(.secondary)
            Slider(value: $value, in: 0 ... 100, step: 1)
                .controlSize(.small)
                .disabled(!isEnabled)
            Text("\(Int(value.rounded()))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

private struct UnavailableRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
    }
}
