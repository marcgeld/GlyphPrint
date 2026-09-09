# GlyphPrint

GlyphPrint is a Swift Package for talking to small BLE thermal printers that use the proprietary `0x5178` protocol commonly seen in "cat printer" style devices.

This baseline targets iOS and macOS and is intentionally split into layers:

- `BLE/` transport over CoreBluetooth
- `Protocol/` packet building for the `0x5178` protocol
- `Image/` QR generation and monochrome rasterization
- `GlyphPrinter` as the public API

## Current status

`v0.1` is a real baseline, not a finished driver.

It includes:

- BLE service / characteristic UUIDs for `AE30`, `AE01`, `AE02`
- async/await connection flow built on top of CoreBluetooth
- preamble commands seen across multiple public reverse-engineering efforts
- QR generation with Core Image
- monochrome rasterization to `384` dots width
- line packet generation for image rows
- unit tests for core protocol and bit-packing helpers

It does **not** yet claim verified compatibility with every printer firmware variant.

## Public API

```swift
import GlyphPrint

let printer = GlyphPrinter()
try await printer.connect()
try await printer.printQRCode("https://example.com")
```

## CLI

For a small standalone `@main` example using the library, see [Examples](Examples/README.md).

```sh
swift run gprint --scan
swift run gprint --scan --printers
swift run gprint --scan --name print
swift run gprint --scan --printers --name print --seconds 10
swift run gprint --connect <device-uuid-or-name>
swift run gprint "https://example.com"
```

## Design notes

These printers do **not** use ESC/POS. Public reverse-engineering work consistently points to a proprietary BLE protocol using service `AE30`, write characteristic `AE01`, notify characteristic `AE02`, a `0x5178` packet format, and 384-dot raster lines. See the public repositories from lisp3r, NaitLee, and rbaron for the reverse-engineering background.

## Suggested next steps

- verify row commands against your exact printer model
- add pacing / flow-control tuning per device
- add text rendering
- add paper feed and status parsing
- add integration tests against captured BLE traces

## Reliability and cancellation

Print calls on the same `GlyphPrinter` are queued as complete jobs so their packets
cannot interleave. Cancelling a waiting job removes it from the queue; cancelling
an active job stops further packets. Data already sent cannot be recalled. If BLE
cancellation interrupts a packet, the connection is closed; reconnect before retrying.
Connection timeouts and task cancellation complete even if no BLE callback arrives.

`gprint --connect <name>` requires a matching name. Library discovery keeps its
service-or-name default; set `PrinterConfig(requiresNameMatch: true)` with an
`advertisedNameSubstring` to require a name match. UUID selection remains exact.
Transparent images are composited onto white before monochrome conversion.

Tests exercise the asynchronous BLE continuation bridge, print-job serialization,
cancellation, discovery matching, and rasterization. Actual CoreBluetooth callbacks,
printer status decoding, and firmware compatibility still need hardware verification.

## Raster protocol and QR rendering

A2 rows contain only bitmap data (48 bytes at 384 dots), with the leftmost pixel
in the least significant bit on the wire. `RasterImage` retains its MSB-first
representation; packet encoding reverses bits within each byte. Row numbers are
not transmitted. The old `makeRasterRowPacket(rowBytes:rowIndex:)` overload is
deprecated and ignores the row index.

QR printing uses whole pixels per module and a white margin of at least four
modules. Protocol framing and lattice commands are checked against
[rbaron/catprinter](https://github.com/rbaron/catprinter/blob/main/catprinter/cmds.py),
and a Vision regression test decodes the image reconstructed from wire bytes.

## Photos and text

See [the photo example](Examples/PrintImageAndText/README.md) for a bundled JPEG
with a printed credit and optional PNG preview. The library provides:

- `MonochromeRasterizer(mode: .floydSteinberg)` for photographic tones.
- `TextRenderer(fontName: "Helvetica", fontSize: 22)` for wrapped text, alignment,
  and padding. Font sizes are measured in printer pixels.
- `RasterImage.stacking(_:spacing:)` to combine sections with different raster modes.
- `GlyphPrinter.print(raster:)` to send the finished layout as a single job.

Keep threshold rendering for text and QR codes; use dithering for photographs.

## Photo credit

Photo by <a href="https://unsplash.com/@markuswinkler?utm_source=unsplash&amp;utm_medium=referral&amp;utm_content=creditCopyText">Markus Winkler</a> on <a href="https://unsplash.com/photos/a-box-with-a-key-chain-and-a-key-chain-on-it-Z8yWSsx8OWE?utm_source=unsplash&amp;utm_medium=referral&amp;utm_content=creditCopyText">Unsplash</a>.
