# Changelog

Versions follow `MAJOR.MINOR.PATCH`. The app is a menu bar utility, so minor versions are
feature work and patch versions are fixes.

## 1.2.1 — 2026-11-03

- **Fix: the settings section could not be closed again.** `MenuBarExtra` keeps the window
  height it had when it first appeared, so opening the settings grew the content but not the
  panel — the header with the gear slid out of view above the screen edge. The panel is now
  an `NSPopover` owned by `StatusItemController`, which sets `contentSize` from the SwiftUI
  content whenever the content changes, so it grows and shrinks with what is in it.

## 1.2.0 — 2026-11-03

- **Bilingual interface.** German strings stay the original, English is the translation;
  the language follows the system setting. `MONDIAL_LANG=de|en` forces one, which is handy
  for testing a translation without changing the Mac's language.
- Every user-facing string is now a `L(german, english)` pair: panel, status messages,
  diagnostics, VCP names, audio output labels, and the CLI with its usage text, `list` and
  `doctor` output.

## 1.1.2 — 2026-11-03

- **Matching by probing.** Displays are now bound to a DCP proxy by sending a single
  Get VCP request and checking whether anything answers, instead of comparing registry
  paths, product names and serial numbers. The text based comparison never matched on real
  two-monitor setups; it only appeared to work because leftovers were handed out in order.
  This restores hardware DDC control for setups that lost it in 1.1.1 while keeping the
  guarantee that a slider only ever moves its own monitor.
- Verified assignments are cached until the display configuration changes, so opening the
  panel does not probe the bus every time.

## 1.1.1 — 2026-11-03

- **A DCP proxy is claimed exclusively.** Two displays can no longer attach to the same
  transport, which previously made the slider of one monitor change the backlight of
  another.
- The leftover assignment in the matcher only runs when the situation is unambiguous:
  exactly one proxy and exactly one external display without one.
- Diagnostics show the service pointer (`svc=0x…`), so a shared transport is visible.

## 1.1.0 — 2026-11-03

- Renamed from the working name *ScreenMix* to **MonDial**: bundle `MonDial.app`,
  identifier `ch.dropflow.mondial`, CLI `mondialctl`, module `MonDialKit`.
- First public release: English README, comparison with MonitorControl and BetterDisplay,
  section on why the builds are not notarised, MIT licence.
- `tools/reinstall.sh` added later in the same line of work.

## 1.0.4 — 2026-11-03

- Audio output switcher in the panel (CoreAudio HAL), so the monitor's speakers can be
  selected without opening System Settings.

## 1.0.3 — 2026-11-03

- Detect DDC writes that the I²C layer accepts but the panel ignores, and fall back to
  gamma dimming.
- Manual switch to software dimming per display.

## 1.0.2 — 2026-11-03

- Diagnostics panel and `mondialctl doctor`.
- `mondialctl` shipped inside the app bundle.

## 1.0.1 — 2026-11-03

- Read retries for slow panels.
- Write-only DDC support for displays that acknowledge writes but never answer reads.

## 1.0.0 — 2026-11-03

- First build: brightness, volume and mute over DDC/CI, global hotkeys, optional media key
  takeover, login item, CLI.
