# DjVu conversion test corpus

Fixtures and reference outputs for the pure-Dart DjVu → PDF converter
(`lib/data/document_conversion/djvu/`). They were generated with the Rust
reference implementation (`djvu-rs`, MIT) and the reference `djvu` encoder, and
every decoder port is tested against them bit for bit.

## Documents

| File | What it exercises |
| --- | --- |
| `bilevel.djvu` | 3-page bundled `FORM:DJVM`, shared `Djbz` symbol dictionary + page `INCL`, bilevel `Sjbz` only |
| `layered.djvu` | 2-page bundled DJVM, `Sjbz` + 10 progressive `BG44` slices + `FGbz` palette + `TH44` thumbnails |
| `archival.djvu` | single page `DJVU`, `Sjbz` + subsampled `BG44` background + `FGbz` |
| `photo.djvu` | single page, `BG44`-only colour page (no mask) |
| `gray.djvu` | single page, `BG44`-only grayscale-*content* page (the stream itself is colour-format, as the reference encoder writes; see `djvu_iw44_test.dart`) |
| `grayscale.djvu` | single page, `BG44`-only **grayscale-format** IW44 page (header grayscale bit set), from `djvu encode -q photo` |
| `bgjp.djvu` | hand-built `INFO` + JPEG (`BGjp`) background |
| `annotated.djvu` | bilevel pages + `NAVM` bookmarks + `ANTz` links on page 0 |

`refs/<name>/` contains, per fixture:

- `manifest.json` — page count, root chunk list, per-page geometry/DPI/rotation,
  reported chunk lists (payload byte lengths), decoded plane sizes, bookmarks,
  link counts. Note: the oracle skips `INCL` and `TH44` in chunk lists.
- `p<i>.INFO.bin` / `root.*.bin` — raw chunk payloads.
- `*.dec.bin` — BZZ-decoded metadata (`DIRM` tail, `NAVM`, `ANTz`).
- `p<i>.mask.png` — reference 1-bit mask, raw packed bits, **sample 0 = mask bit
  set** (PNG 1-bit grayscale maps 0 to black).
- `p<i>.bg.png`, `p<i>.fg.png` — 8-bit RGB reference planes; `bg` may be
  subsampled (see `manifest.json`).
- `p<i>.fgbz.json` — FGbz palette: `colors` (RGB triples) and `indices`
  (per-pixel palette index, row-major, mask-sized).
- `p<i>.links.json` — reference annotations for `annotated.djvu`.

`zp/stream.zp` + `zp/steps.json` is a synthetic ZP stream with a 400-step
encode script (`bit`/`run` with context indexes, `pt`/`pt44` passthrough) used
to test the ZP decoder against the reference encoder.

## Regeneration

The fixture generation scripts live outside the repo (`/tmp/opencode/fixtures`
during development). Roughly:

1. Draw source images with PIL and encode them with the reference `djvu` CLI
   from <https://github.com/matyushkin/djvu-rs>:

   ```sh
   djvu encode --quality lossless src/bilevel.png bilevel.djvu
   djvu encode --quality archival --thumbnails src/layered.png layered.djvu
   # etc. per fixture
   ```

   `bgjp.djvu` is assembled by hand (INFO + JPEG `BGjp` chunk in a `FORM:DJVU`),
   and `annotated.djvu` is `bilevel.djvu` + NAVM/ANTz chunks added by a small
   Rust helper (`mkfix.rs`).

2. Generate the reference dump with the `oracle` helper binary
   (`djvu-rs/src/bin/oracle.rs`):

   ```sh
   oracle dump bilevel.djvu refs/bilevel
   oracle zp-encode zp/stream.zp zp/steps.json
   rm refs/*/*.composite.png
   ```

   The oracle writes the manifest (valid JSON), raw and BZZ-decoded chunks, and
   the reference PNG planes. It also offers `bzz-dump`, `iw44-decode`,
   `jb2-decode`, and `iw44-decode` commands for stage-by-stage debugging
   against a single chunk.

The PNG planes are the source of truth for pixel-exact tests; the manifests are
the source of truth for container metadata.
