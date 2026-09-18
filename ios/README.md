# AIM-X Controller — iOS

Native iOS (SwiftUI + WKWebView) companion app that mirrors the Android
`ApkController` app (MainActivity.kt + bundle assets) so you can drive the same
cheat PC over the LAN from an iPhone/iPad.

The iOS app talks the **exact same binary protocol and ports** as the Android
app, and reuses the **byte-identical** `controller.html` / `bridge_shim.js`
assets from the Android project — the Web UI is not rewritten, it is hosted
verbatim inside a `WKWebView`.

> No Android APK is modified or required. This is a clean-room iOS port of the
> control logic only.

---

## What it does

- **Native connect screen** (`ConnectScreenView.swift`) — glassmorphism UI
  (purple `#5B6EF5` theme, matching the Android Compose screen) with a PC IP
  field, LAN discovery, manual connect, and a live log.
- **Auto-discovery** over UDP broadcast (port **1213**) + a **LAN subnet
  sweep** (TCP port **1212**, 180 ms timeout, chunked) so the PC is found
  without typing an IP — same as Android's `autoConnect()`.
- **TCP control channel** (port **1212**, `tcpNoDelay`, 5 s connect timeout,
  auto-reconnect) carrying the SAME binary packets:
  - **State packet** — 60-byte little-endian blob (`AC DC 01 00` header)
    encoding aimbot/ESP settings, mirrored field-for-field from Android's
    `transmitJsonState`.
  - **Plain command** — 10-byte packet (`AC DC 04 00`) for
    refresh-ESP / refresh-entities / bypass-on / bypass-off / memory-init,
    mirrored from `transmitPlainCommand`.
- **Controller WebView** — hosts the unmodified `controller.html` and injects
  `window.AndroidBridge.*` (via `bridge_shim.js`) that forwards to native
  `WKScriptMessageHandler` handlers, so the page's existing
  `sendStateToPC` / `onControlAction` / `sendBypassRequest` JS calls work
  unchanged.

---

## Project layout

```
ios/
└── AIMXController/
    ├── App/            AIMXControllerApp.swift        (SwiftUI @main + AppDelegate)
    ├── Bundle/         controller.html                (verbatim from Android assets)
    ├── Models/         ConnectionAndScreen.swift      (enum ConnectionState/AppScreen)
    ├── ViewModels/     MainViewModel.swift            (bridge + auto-connect copy)
    ├── Views/          ConnectScreenView / ControllerWebView / RootView
    ├── Web/            NativeBridge.swift (WK bridge) + bridge_shim.js (JS shim)
    ├── Network/        PCConnectionManager / LANScanner / LocalIP /
    │                   PacketEncoder / UDPBroadcastListener
    └── Resources/      Info.plist, Assets.xcassets
```

## Requirements

- Xcode 15.0+ (iOS 15.0 deployment target)
- iPhone / iPad with **local-network access on the same Wi-Fi as the PC**
- iOS 15.0+

## Build & run

1. Open `ios/AIMXController.xcodeproj` in Xcode.
2. Select the `AIMXController` scheme / target.
3. **Signing:** set your team under *Signing & Capabilities* →
   `co.aimx.controller` (or change `PRODUCT_BUNDLE_IDENTIFIER`).
4. In *Info → Custom iOS Target Properties*, confirm
   `NSLocalNetworkUsageDescription` (drives the local-network prompt) and
   `NSBonjourServices` are present — they ship in `Info.plist`.
5. Plug in a device, select it as the run destination (local networking and
   UDP broadcast require a real device, not the simulator), and hit **Run**.

> Local-network access: on first launch iOS prompts for local-network
> permission — grant it or the UDP discovery / TCP connect won't work.

## Device → PC protocol cheat-sheet

| Item        | Value                                              |
|-------------|----------------------------------------------------|
| TCP port    | 1212 (tcpNoDelay, 5 s connect timeout)             |
| UDP         | 1213 broadcast listener (`#1_CONTROLLER_SERVER`)    |
| LAN sweep   | 1212, 180 ms timeout, 25-IP chunks                 |
| State pk    | 60-byte LE, magic `AC DC 01 00`, then int32 len     |
| Aimbot map  | head=2, fair=3, collider=4, external=5              |
| Plain cmd   | 10-byte, magic `AC DC 04 00`, action byte           |

Packet building lives in `Network/PacketEncoder.swift` — change it there, not
inside the WebView.

## Android parity notes

- Auto-connect runs on launch (login/bypass is dev-skipped, matching Android's
  bypass mode).
- The WebView is created once and kept alive across screen switches
  (`ControllerWebView.swift`), mirroring Android's `keepWebView`.
- Backgrounding triggers re-discovery on foreground
  (`applicationWillEnterForeground`), matching Android's reconnect-on-resume.
