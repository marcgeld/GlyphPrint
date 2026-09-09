# Tiny Print and PX10 protocol references

The user supplied the app link:
<http://xwch_app.frogtosea.com/h1_tinyPrint>.
Direct HTTP and HTTPS requests timed out during this investigation. An Android
app bundle was subsequently downloaded from the APKPure mirror for static analysis
on September 9, 2026. It has not been installed or executed.

## Downloaded Android app

- Source: [APKPure download page](https://apkpure.net/tiny-print/com.frogtosea.tinyPrint/download)
- Download URL: <https://d.apkpure.net/b/XAPK/com.frogtosea.tinyPrint?version=latest>
- Bundle manifest: package `com.frogtosea.tinyPrint`, version `1.3.82`, version code `142`.
- Local bundle: `/tmp/glyphprint-tinyprint/tiny-print.xapk` (133,654,498 bytes).
- Extracted base APK: `/tmp/glyphprint-tinyprint/com.frogtosea.tinyPrint.apk`
  (92,593,064 bytes). The bundle also contains arm64, English, and display-density splits.
- XAPK SHA-256: `6fbd29a662284cdf6b12b7c3f8b1ce45a2deaf5bd6d373bdb72702206cca267a`
- Base APK SHA-256: `1f1b7889a9d6f7fbb7086a4d9aa7e5fc615e386d5cdaa2621d785d8896f454b7`

ZIP CRC checks passed for both archives. The base APK contains `AndroidManifest.xml`
and six DEX files. These checks establish archive integrity, not publisher authenticity;
the signing certificate has not been independently verified. Temporary files may be
removed by the operating system. The binaries are not included in the repository.
Protocol code in the APK has not yet been analyzed.

## Independent protocol reference

An independent open-source implementation provides a concrete model association:

- [TiMini Print model catalog](https://github.com/Dejniel/TiMini-Print/blob/02744619eedc3dc778040c92c173c4430965a71a/timiniprint/data/printer_models.json)
  associates the `Luxorp.PX10` prefix with model `pocket_printer`, profile `d1`,
  and origin package `com.frogtosea.tinyPrint`.
- [D1 profile](https://github.com/Dejniel/TiMini-Print/blob/02744619eedc3dc778040c92c173c4430965a71a/timiniprint/data/printer_profiles.json)
  uses the Tiny protocol, a 384-dot paper preset, and Tiny RLE encoding.
  Its timing and energy settings are reference values, not new settings verified
  on our physical PX10. They have not been copied into GlyphPrint.
- [Tiny runtime controller](https://github.com/Dejniel/TiMini-Print/blob/02744619eedc3dc778040c92c173c4430965a71a/timiniprint/printing/runtime/tiny.py)
  handles response opcode AE with payload 10 (pause) and 00 (resume).
  This controller does not decode A3 into cover or paper flags.

This source supports identifying the protocol family but does not resolve the
meaning of our A3 observations. Status layouts from other protocol families must
not be applied to PX10 merely because they share an opcode or packet prefix.

Next evidence to collect: whether the original Tiny Print app reports paper-out
when the cover is closed and paper is absent, and which notification or request
it uses for that decision. Keep power conditions unchanged during comparisons.
App notifications may differ from the response to our explicit A3 query.
