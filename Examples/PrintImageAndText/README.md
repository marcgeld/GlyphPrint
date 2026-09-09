# Photo with attribution

Run from the project root on macOS:

```sh
swift run photo-example --preview /tmp/glyphprint-photo.png
swift run photo-example --printer Luxorp.PX10
```

The first command creates a PNG containing the exact monochrome pixels to be
printed, without connecting to Bluetooth. The second selects a printer whose name contains `Luxorp.PX10`.
The JPEG is bundled as a Swift Package resource, so the compiled example works
regardless of the current working directory.

The photo is scaled proportionally to 384 dots wide and converted using
Floyd–Steinberg dithering. The credit uses threshold conversion for sharp text,
Helvetica at 22 printer pixels, and center alignment. Change `fontName` and
`fontSize` in the example to use a different font or size. Core Text uses
installed or registered fonts with automatic fallback; the host app registers
any custom fonts.

`RasterImage.stacking` combines the photo and text with 12 white rows between them.
`printer.print(raster:)` sends everything as a single print job without rescaling
or additional paper feed between sections.

The printed credit reads “Photo by Markus Winkler” and “on Unsplash”. Attribution links:

Photo by [Markus Winkler](https://unsplash.com/@markuswinkler?utm_source=unsplash&utm_medium=referral&utm_content=creditCopyText)
on [Unsplash](https://unsplash.com/photos/a-box-with-a-key-chain-and-a-key-chain-on-it-Z8yWSsx8OWE?utm_source=unsplash&utm_medium=referral&utm_content=creditCopyText).

Physical sharpness and darkness also depend on the printer's heat settings,
paper, and firmware.

## Printer and tone settings

Without `--printer`, the example uses the saved default UUID, or discovers a
single matching printer. Multiple matches require an explicit UUID.

```sh
swift run photo-example --preview /tmp/brighter-photo.png --brightness 0.12 --contrast 1.1
swift run photo-example --printer Luxorp.PX10 --brightness 0.12 --contrast 1.1
```

Brightness is −1...1 (default 0); contrast is 0...4 (default 1). These affect only
the photo. Preview mode never accesses Bluetooth or printer preferences.
The printed result is reported by the library; no fixed sleep is needed here.
