# QR codes with GlyphPrint

[PrintQRCode/PrintQRCode.swift](PrintQRCode/PrintQRCode.swift) is a small example
with an `@main` entry point that imports the library, connects to the printer,
and prints a QR code. It disconnects even if printing fails.

Run from the project root on macOS with Swift 6.2 or later:

```sh
swift run qr-example
swift run qr-example "https://example.com"
```

Without arguments, the QR code contains the text `GlyphPrint Test`.
Turn on the printer and enable Bluetooth. Allow Bluetooth access if macOS prompts
you. The example selects `Luxorp.PX10-1673`; change `advertisedNameSubstring` in
the Swift file if you are using a different printer.

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
