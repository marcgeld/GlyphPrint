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

## Design notes

These printers do **not** use ESC/POS. Public reverse-engineering work consistently points to a proprietary BLE protocol using service `AE30`, write characteristic `AE01`, notify characteristic `AE02`, a `0x5178` packet format, and 384-dot raster lines. See the public repositories from lisp3r, NaitLee, and rbaron for the reverse-engineering background.

## Suggested next steps

- verify row commands against your exact printer model
- add pacing / flow-control tuning per device
- add text rendering
- add paper feed and status parsing
- add integration tests against captured BLE traces
