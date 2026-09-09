# QR codes with GlyphPrint

[PrintQRCode/PrintQRCode.swift](PrintQRCode/PrintQRCode.swift) is a small example
with an `@main` entry point that imports the library, connects to the printer,
and prints a QR code. It disconnects even if printing fails.

Run from the project root on macOS with Swift 6.2 or later:

```sh
swift run qr-example
swift run qr-example --printer Luxorp.PX10 "https://example.com"
```

Without arguments, the QR code contains the text `GlyphPrint Test`.
Turn on the printer and enable Bluetooth. Allow Bluetooth access if macOS prompts
you. Both examples use `--printer UUID|name`, then the saved default from
`gprint --set-default`, then unambiguous discovery. No printer name is hardcoded.
Multiple matches require an explicit UUID.

To build the example without printing:

```sh
swift build --product qr-example
```

## Photos and text

[PrintImageAndText](PrintImageAndText/README.md) prints the bundled photo
with dithering and a photo credit using a configurable font:

```sh
swift run photo-example --preview /tmp/glyphprint-photo.png
swift run photo-example
```

Both examples report `submittedToBluetooth` or `printerReportedReady`; neither
result proves physical print quality. Readiness waiting is handled by the library.
