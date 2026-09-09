# GlyphPrint

A Swift 6.2 package for iOS 16+ and macOS 13+ that prints QR codes, monochrome
images, photographs, and text on small BLE thermal printers using the `0x5178`
protocol. The Luxorparts PX10 has been exercised on real hardware; compatibility
and print quality are not guaranteed across firmware variants.

## Requirements

- iOS 16 or later, or macOS 13 or later.
- Swift 6.2 or later and an Xcode installation with a compatible Swift toolchain.
- A Bluetooth-capable device and a supported BLE thermal printer for printing.

## Add GlyphPrint to an Xcode app

1. Open your iOS or macOS app project in Xcode.
2. Choose **File → Add Package Dependencies**.
3. Enter `https://github.com/marcgeld/GlyphPrint.git`.
4. Choose **Up to Next Major Version**, starting from **1.0.0**, then click
   **Add Package**.
5. Select the **GlyphPrint** library product and add it to your app target.
6. Configure the app's Bluetooth permissions as described below, then use
   `import GlyphPrint` in your Swift code.

For local development, choose **Add Local** in the package dependency dialog and
select the folder containing GlyphPrint's `Package.swift`.

## Bluetooth permissions in the consuming app

**Bluetooth settings must be configured in the app that uses GlyphPrint.**
The package cannot supply the app's privacy usage description or sandbox
entitlements on its behalf.

### iOS and macOS: usage description

Add `NSBluetoothAlwaysUsageDescription` to your **app's** `Info.plist` with a
user-facing explanation of why Bluetooth is needed:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to connect to your printer.</string>
```

If Xcode generates your app's `Info.plist`, add **Privacy - Bluetooth Always Usage
Description** under the app target's **Info** tab instead. Localize the description
for your app's supported languages. For example, in Swedish:
“Appen använder Bluetooth för att ansluta till din skrivare.”

See Apple's documentation for
[`NSBluetoothAlwaysUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription).

### macOS: App Sandbox

For a macOS app with App Sandbox enabled, select the **app target**, open
**Signing & Capabilities → App Sandbox**, and enable **Bluetooth** under
**Hardware**. This adds the following entitlement to the app's entitlements file:

```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
```

This entitlement is required in addition to the usage description above for a
sandboxed macOS app. See Apple's documentation for
[`com.apple.security.device.bluetooth`](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.device.bluetooth).

## Quick start

```swift
import GlyphPrint

let printer = GlyphPrinter()
try await printer.connect()
let result = try await printer.printQRCode("https://example.com")
await printer.disconnect()
print(result)
```

Automatic discovery rejects ambiguous matches. In production, also disconnect in
your error handler; the [examples](Examples/README.md) show the complete flow.

## Discover and select a printer

```swift
let devices = try await PrinterDiscovery.discoverPrinters(
    duration: .seconds(5),
    verify: true
)
// Display the results and let the user choose a device.
let selected = try PrinterSelection.select(from: devices, matching: "Luxorp.PX10")
let printer = GlyphPrinter(config: selected.config)
```

Discovery is shared by the library, CLI, and examples. Results include a UUID,
name, signal strength, advertised services, profile, and compatibility:

- `candidate`: advertisements or the name match a supported profile.
- `verified`: a connection found the required write/notify capabilities and enabled notifications.
- `unverified`: verification failed; `verificationError` contains the reason.
- `unknown`: no profile matched (included with `printersOnly: false`).

Verification sends no print data and does not establish physical print quality.
It runs sequentially with an eight-second connection timeout per candidate.
Scanning accepts durations greater than zero and no longer than 60 seconds and
supports task cancellation. Names and advertised services are merged across updates.

The PX10 advertises `AF30` but exposes `AE30`, `AE01`, and `AE02` after connection.
`PrinterProfile` keeps advertisement hints separate from transport UUIDs.
An `AF30` advertisement alone identifies a possible protocol family, not an exact model.

The facade collects candidates before selecting one. Names are matched without
case sensitivity; multiple matches raise `ambiguousPrinters` with their UUIDs.
An explicitly selected UUID or required name bypasses the default −80 dBm cutoff.
Signal strength remains a useful warning, not a reason to reject an explicit choice.

Low-level `GlyphPrinterClient` performs bounded candidate attempts and avoids
retrying the same candidate within one connection operation. Prefer the facade or
`PrinterSelection.configuration(for:)` for user-facing automatic selection.

## CLI

Run from the project root:

```sh
swift run gprint --scan --printers --verify
swift run gprint --scan --name Luxorp --seconds 10
swift run gprint --connect Luxorp.PX10
swift run gprint --printer Luxorp.PX10 "https://example.com"
swift run gprint --printer Luxorp.PX10 --image photo.jpg --dither
swift run gprint --printer Luxorp.PX10 --image photo.jpg --dither --brightness 0.12 --contrast 1.1
```

Use a UUID when multiple devices share a name. Printer selection follows this order:
explicit `--printer`, saved default UUID, then unambiguous discovery.

```sh
swift run gprint --set-default Luxorp.PX10
swift run gprint --show-default
swift run gprint --clear-default
```

Setting a default verifies its transport and saves its UUID and name in
`Application Support/GlyphPrint/default-printer.json` for the current user.
Nothing is saved automatically. CLI and examples share this preference through
`PrinterPreferences`; application code decides whether to use those preferences.

`--connect` only tests the transport. `--status` sends a device-state query:

```sh
swift run gprint --status --printer Luxorp.PX10 --trace /tmp/px10-status.json
```

`--trace` exports the received, CRC-validated notifications as JSON (Data fields
are Base64). It does not capture over-the-air BLE traffic. Each connection keeps
at most the latest 256 decoded notifications. Unknown response commands remain
available with their raw payloads. Use `--help` for the command summary.

## Photos and text

See [the photo example](Examples/PrintImageAndText/README.md) for a bundled JPEG,
printed credit, and exact monochrome PNG preview.

- `MonochromeRasterizer(mode: .floydSteinberg, brightness: 0.12, contrast: 1.1)`
  preserves photographic tones using error diffusion.
- Brightness ranges from −1 to 1 (default 0), contrast from 0 to 4 (default 1).
  Adjustments are applied to grayscale before thresholding or dithering.
- `TextRenderer(fontName: "Helvetica", fontSize: 22)` supports wrapped text,
  alignment, and padding. Font sizes are in printer pixels.
- `RasterImage.stacking(_:spacing:)` combines differently rendered sections.
- `GlyphPrinter.print(raster:)` sends the completed layout as one job.

Keep threshold rendering for text and QR codes. The photo example applies image
adjustments only to the photograph, leaving the credit crisp and unchanged.

## Reliability and print results

Complete jobs on the same facade are serialized, including their final readiness
wait. Cancelling a queued job removes it; cancelling an active job stops further
packets. Already transmitted data cannot be recalled. If cancellation interrupts
a packet, reconnect before retrying. Failed prints are never automatically replayed.

`PrinterConfig` exposes an eight-second candidate timeout, fifteen-second send
timeout, and ten-millisecond write interval by default. Writes honor both
CoreBluetooth backpressure and recognized `AE` pause/receive-ready notifications.
These are reference-protocol signals; all firmware behaviors are not yet established.

Print calls return `PrintResult`:

- `submittedToBluetooth`: all bytes were accepted by CoreBluetooth; physical
  completion remains unknown. This is also the fallback when no fresh readiness
  signal arrives within three seconds.
- `printerReportedReady`: a recognized receive-ready notification arrived after
  the final write. This is not a guarantee of correct physical output.

The bounded wait is centralized in the transport, not copied into the examples.
Applications may inspect `GlyphPrinterClient.notifications()` or call
`queryStatus()` when no print job is in progress.

A PX10 state query captured on 2026-09-09 returned payload `00 0A 27`. Its bit
meanings have not been established. The library deliberately does not label it
“paper present”, “idle”, or “print complete”. Mapping paper-out, overheating,
and other states still needs controlled hardware observations.

## Architecture and protocol

- `BLE/`: CoreBluetooth discovery and transport.
- `Protocol/`: packet framing, CRC, raster encoding, and notification decoding.
- `Image/`: QR/text generation, tone adjustment, dithering, and raster layouts.
- `GlyphPrinter`: the small public facade; transports remain injectable for tests.

A2 packets contain bitmap bytes only (48 bytes for 384 dots). The leftmost pixel
is in the least significant bit on the wire. `RasterImage` stores it in the most
significant bit; the protocol layer performs the conversion. Row numbers are not
transmitted. The old `makeRasterRowPacket(rowBytes:rowIndex:)` overload is deprecated.
QR codes use integer module scaling and at least four white modules of margin.

Protocol references: [rbaron/catprinter](https://github.com/rbaron/catprinter),
[lisp3r/bluetooth-thermal-printer](https://github.com/lisp3r/bluetooth-thermal-printer).

## Tests and hardware evidence

```sh
swift test
```

Tests cover framing, image and text output, QR decoding, discovery matching,
ambiguous selection, persisted preferences, cancellation, job ordering, CLI input,
and fragmented/corrupt notifications. [Fixtures](Tests/GlyphPrintTests/Fixtures)
distinguish actual PX10 captures from independently sourced reference vectors.
Physical print quality, paper-out meanings, and full firmware compatibility still
require hardware verification.

## Photo credit

Photo by <a href="https://unsplash.com/@markuswinkler?utm_source=unsplash&amp;utm_medium=referral&amp;utm_content=creditCopyText">Markus Winkler</a> on <a href="https://unsplash.com/photos/a-box-with-a-key-chain-and-a-key-chain-on-it-Z8yWSsx8OWE?utm_source=unsplash&amp;utm_medium=referral&amp;utm_content=creditCopyText">Unsplash</a>.
