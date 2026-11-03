# ScreenMix

Helligkeit **und** Lautstärke externer Bildschirme direkt aus macOS steuern – so wie es
BetterDisplay Pro macht, nur als kleines, quelloffenes Werkzeug für den Mac mini.

Auf einem Mac mini gibt es keinen integrierten Bildschirm, deshalb hat macOS für die
Helligkeits- und Lautstärketasten kein Ziel. Externe Monitore lassen sich aber über
**DDC/CI** steuern – ein kleiner I²C-Bus, der im DisplayPort-/HDMI-/USB-C-Kabel mitläuft.
Genau das nutzt ScreenMix.

Inhalt:

* **ScreenMix.app** – Menüleisten-App mit Reglern, globalen Tastenkürzeln und optionalem
  Abfangen der echten Medientasten (F1/F2, F10–F12)
* **screenmixctl** – Kommandozeilenwerkzeug für Skripte, Shortcuts, Alfred, Raycast …

---

## 1. Voraussetzungen

| | |
|---|---|
| macOS | 13 (Ventura) oder neuer |
| Mac | Apple Silicon (M1–M4) **oder** Intel – beide Pfade sind implementiert |
| Monitor | DDC/CI muss im OSD des Monitors **aktiviert** sein (meist unter „Sonstiges“ / „System“) |
| Werkzeuge | Xcode Command Line Tools: `xcode-select --install` |

Verbinden mit **DisplayPort, USB-C/Thunderbolt oder HDMI**. Reine USB-Hubs, KVM-Switches und
manche Dockingstations schlucken DDC – dann hilft nur ein direkter Anschluss.

---

## 2. Bauen

Fertiger Build (Apple Silicon): im Repository unter **Releases** →
`ScreenMix-app.zip` herunterladen, entpacken, nach `/Programme` ziehen. Da die App nur
ad-hoc signiert ist, muss die Quarantäne-Markierung einmal entfernt werden:

```bash
xattr -dr com.apple.quarantine /Applications/ScreenMix.app
```

Selbst bauen (empfohlen, funktioniert auch auf Intel-Macs):

```bash
cd screenmix
./build.sh --install
```

Das Skript

1. kompiliert `ScreenMix` und `screenmixctl` (Release),
2. baut `dist/ScreenMix.app` inklusive Icon und Info.plist,
3. signiert ad-hoc (reicht lokal, kein Developer-Account nötig),
4. kopiert bei `--install` die App nach `/Applications`, verlinkt `screenmixctl` nach
   `/usr/local/bin` und startet die App.

Ohne Installation:

```bash
./build.sh          # nur bauen -> dist/
./build.sh --run    # bauen und starten
```

Da die App nicht notarisiert ist, fragt macOS beim ersten Start evtl. nach. Falls die App
blockiert wird: **Systemeinstellungen → Datenschutz & Sicherheit → „Dennoch öffnen“**.

---

## 3. Menüleisten-App

Nach dem Start erscheint ein Sonnensymbol in der Menüleiste. Ein Klick öffnet:

* pro Bildschirm einen **Helligkeitsregler** und – falls der Monitor Lautsprecher hat –
  einen **Lautstärkeregler** samt Stummschalt-Taste,
* **Neu scannen**, wenn ein Monitor an- oder abgesteckt wurde,
* ein Zahnrad mit den Einstellungen.

### Tastenkürzel (standardmässig aktiv)

| Kürzel | Funktion |
|---|---|
| `⌃⌥↑` / `⌃⌥↓` | Helligkeit des Hauptbildschirms ± 6,25 % |
| `⌃⌥⇧↑` / `⌃⌥⇧↓` | Lautstärke ± 6,25 % |
| `⌃⌥M` | Stummschalten |

Diese Kürzel funktionieren systemweit und brauchen **keine** Sonderberechtigung.

### Medientasten abfangen (optional)

Die echten Helligkeits- und Lautstärketasten (`F1`, `F2`, `F10`–`F12`) kann ScreenMix
ebenfalls übernehmen. Dafür ist die Berechtigung **Bedienungshilfen** nötig:

1. Zahnrad → „Medientasten abfangen“ einschalten
2. Im Dialog (oder über den erscheinenden Button) ScreenMix in
   **Datenschutz & Sicherheit → Bedienungshilfen** aktivieren
3. App einmal neu starten

Ohne diese Berechtigung bleiben die Tasten einfach wirkungslos – es geht nichts kaputt.

### Autostart

Zahnrad → „Beim Anmelden öffnen“. ScreenMix legt dafür ein LaunchAgent unter
`~/Library/LaunchAgents/ch.dropflow.screenmix.agent.plist` an.

---

## 4. Kommandozeile

```bash
screenmixctl list                  # alle Bildschirme + aktuelle Werte
screenmixctl doctor                # Diagnose: Backend, Transport, Antwortzeiten
screenmixctl get brightness        # 62
screenmixctl set brightness 40     # 40 %
screenmixctl step brightness -6    # relativ
screenmixctl set volume 35
screenmixctl mute toggle
screenmixctl set brightness 30 -d "LG"     # bestimmter Monitor (Namens-Teilstring)
screenmixctl set volume 20 -d 2            # ... oder Index aus "list"
screenmixctl list --json                   # für Skripte
```

Attribute: `brightness` (`helligkeit`), `volume` (`lautstaerke`), `contrast`, `mute`.
Alle Werte werden in Prozent angegeben; die Rohwerte (0–100 oder 0–255, je nach Monitor)
rechnet das Tool selbst um.

Exit-Codes: `0` = ok, `1` = Aufruf-/Auswahlfehler, `2` = Monitor antwortet nicht.

### Beispiele für Skripte

```bash
# Abend-Dimmung um 20 Uhr (launchd/cron)
screenmixctl set brightness 25
screenmixctl set volume 15

# In Raycast/Alfred: Bildschirm dunkler
screenmixctl step brightness -10
```

---

## 5. Wie es funktioniert

DDC/CI ist ein I²C-Protokoll. Ein „Get VCP Feature“-Paket fragt z. B. VCP-Code `0x10`
(Helligkeit) oder `0x62` (Lautstärke) ab, ein „Set VCP Feature“-Paket schreibt sie.

**Apple Silicon.** Der klassische `IOI2CInterface`-Weg existiert nicht mehr. Die Pakete
laufen stattdessen über den Display-Coprozessor: `IOAVServiceCreateWithService` +
`IOAVServiceReadI2C` / `IOAVServiceWriteI2C` – private, aber stabile IOKit-Funktionen.
ScreenMix sucht im IORegistry alle `DCPAVServiceProxy`-Einträge mit `Location = External`,
ordnet sie über Pfad, Produktname und Seriennummer den `CGDirectDisplayID`s zu und benutzt
pro Monitor einen eigenen Transport. Bei HDMI-Ports mit `AppleDCPMCDP29XX`-Controller wird
automatisch die abweichende Chip-Adresse `0xB7` verwendet.

**Intel.** Über `IOFramebuffer` + `IOI2CInterfaceOpen` / `IOI2CSendRequest`, wie es `ddcctl`
macht.

**Lesestrategien.** Monitore und macOS-Versionen sind hier inkonsistent: manche erwarten den
Reply am I²C-Offset `0x51` (12 Byte, Prüfsumme inkl. Adresse), andere an Offset `0` (11 Byte).
ScreenMix probiert beide Varianten, prüft Antworttyp, VCP-Code und Plausibilität und merkt
sich die funktionierende Variante. `screenmixctl doctor` zeigt, welche benutzt wird.

**Software-Dimmung.** Antwortet ein Monitor gar nicht auf DDC (oder ist es der interne
Bildschirm eines iMacs), dimmt ScreenMix ersatzweise über die Gamma-Tabelle
(`CGSetDisplayTransferByFormula`). Das sieht aus wie Helligkeit, spart aber keinen Strom –
deshalb steht in der App dann „kein DDC“ bzw. „DDC ohne Rückmeldung“.

Alles läuft ohne Kernel-Extension, ohne SIP-Eingriff und ohne Root-Rechte.

---

## 6. Bekannte Geräte

### Samsung ViewFinity S6 S65TC (S34C650TAU / LS34C650TAUXEN)

34" Ultra-WQHD (3440 × 1440) mit 100 Hz, USB-C mit 90 W Ladeleistung, Thunderbolt-4-Ausgang,
RJ45 und **2 × 5 W Lautsprecher**. Damit sind beide Achsen über DDC erreichbar:

| Funktion | VCP | Anmerkung |
|---|---|---|
| Helligkeit | `0x10` | Wertebereich 0–100, entspricht direkt Prozent |
| Lautstärke | `0x62` | steuert die eingebauten Lautsprecher |
| Stummschaltung | `0x8D` | 1 = stumm, 2 = Ton an |

**Anschluss.** Über USB-C/Thunderbolt läuft DDC über die Chip-Adresse `0x37`. Hängt der
Monitor am HDMI-Port eines Mac mini, verwendet macOS den MCDP29xx-Pfad mit `0xB7` –
ScreenMix erkennt das am IORegistry und schaltet automatisch um, du musst nichts einstellen.

**Was im Monitor-Menü aus sein sollte**, sonst überschreibt der Monitor die per DDC
gesetzte Helligkeit wieder:

* `Bild → Eco Saving Plus` → **Aus**
* `Bild → Eye Saver Mode` → **Aus**
* `Bild → Adaptive Picture` bzw. HDR → **Aus** (bei aktivem HDR ignoriert der Monitor VCP `0x10`)

**Lautstärke.** `Ton → Lautstärke` sollte nicht auf 0 stehen und `Ton → Tonquelle` auf dem
gerade benutzten Eingang (USB-C bzw. HDMI). Der Ton läuft über DisplayPort-Audio, deshalb
lässt sich die macOS-Systemlautstärke dafür nicht benutzen – DDC ist hier der einzige Weg.

Erwartete `screenmixctl doctor`-Ausgabe für dieses Gerät: Helligkeit und Lautstärke jeweils
mit `(max 100)` und Antwortzeiten unter 100 ms. Meldet der Monitor nur bei der Helligkeit
„keine Antwort“, schreibt ScreenMix trotzdem (Modus „DDC (nur schreiben)“) statt auf
Gamma-Dimmung auszuweichen.

---

## 7. Fehlersuche

**Es passiert nichts / „DDC ohne Rückmeldung“**

1. `screenmixctl doctor` ausführen. Wichtig sind die Zeilen `Transport` und die Antwortzeiten.
2. Im Monitor-OSD `DDC/CI` einschalten (bei Dell, LG, BenQ, Eizo unterschiedlich benannt).
3. Direkt anschliessen: kein Hub, kein KVM, kein Adapter zwischen Mac und Monitor.
4. Monitor kurz stromlos machen (DDC-Controller hängen sich gerne auf).
5. Bei HDMI an Apple Silicon: manche Ports laufen über den MCDP29xx-Pfad. ScreenMix erkennt
   das automatisch – wenn nicht, bitte `doctor`-Ausgabe anschauen.

**Lautstärkeregler fehlt**

Der Monitor meldet VCP `0x62` nicht. Das ist bei vielen Geräten ohne Lautsprecher normal.
Bei Monitoren mit Lautsprechern over HDMI/DisplayPort liefert DDC die Lautstärke; die
macOS-Systemlautstärke bleibt bei digitalen Ausgängen bewusst nicht regelbar.

**Medientasten reagieren nicht**

Berechtigung „Bedienungshilfen“ fehlt (siehe Abschnitt 3). Nach dem Erteilen die App neu
starten.

**Nach dem Abstecken eines Monitors hängt die App an einem alten Gerät**

Zahnrad → „Neu scannen“, oder die App neu starten. Ein Display-Wechsel wird automatisch
erkannt, ein verschwundener Monitor wird aus der Liste entfernt.

**`swift build` schlägt fehl**

`xcode-select --install` ausführen und `xcode-select -p` prüfen. ScreenMix braucht kein
volles Xcode, die Command Line Tools genügen.

---

## 8. Grenzen

* **Keine HDR-Helligkeit.** DDC steuert die Hintergrundbeleuchtung, nicht das Tone-Mapping.
* **Keine Apple-Displays.** Beim Studio Display / Pro Display XDR übernimmt macOS die
  Helligkeit selbst; DDC gibt es dort nicht.
* **AirPlay-/Sidecar-Displays** haben keinen DDC-Kanal und werden nur per Software-Dimmung
  unterstützt.
* **Private API.** `IOAVService*` ist undokumentiert. Es funktioniert seit macOS 11 stabil,
  ist aber nichts für den Mac App Store und kann von Apple jederzeit angepasst werden.
* **Ein Monitor pro DDC-Kanal.** Bei mehreren Monitoren an einem Hub kann DDC unzuverlässig
  werden – das ist eine Einschränkung der Hardware, nicht der App.

---

## 9. Projektstruktur

```
Package.swift
build.sh                     Bauen + App-Bundle + Icon + Ad-hoc-Signatur
Resources/Info.plist         Bundle-Definition (LSUIElement = Menüleisten-App)
Resources/AppIcon.png        Icon (erzeugt von tools/make_icon.py)
Sources/ScreenMixKit/        Kernbibliothek
  PrivateAPI.swift           dlsym-Zugriff auf IOAVService/CoreDisplay
  DDC.swift                  VCP-Codes, Transport-Protokoll, PhysicalDisplay
  Arm64Transport.swift       Apple Silicon (IOAVService), beide Lesestrategien
  IntelTransport.swift       Intel (IOI2CInterface)
  DisplayManager.swift       Display-Enumeration, IORegistry-Matching, Cache
  DisplayController.swift    Observable-Wrapper mit Write-Coalescing
  SoftwareBrightness.swift   Gamma-Dimmung als Fallback
  Preferences.swift          UserDefaults + Diagnose
Sources/screenmixctl/        CLI
Sources/ScreenMixApp/        Menüleisten-App (SwiftUI MenuBarExtra + AppKit)
```

## 10. Danke

Die DDC/CI-Details auf Apple Silicon und Intel basieren auf den offenen Projekten
[m1ddc](https://github.com/waydabber/m1ddc) (MIT), [MonitorControl](https://github.com/MonitorControl/MonitorControl)
(MIT) und [ddcctl](https://github.com/kfix/ddcctl) (GPLv3) – dort lässt sich nachlesen, wie
viel Reverse Engineering in diesen 40 Bytes pro Paket steckt. Der Code hier ist eigenständig
geschrieben, die Protokollkenntnis stammt aus diesen Quellen.
