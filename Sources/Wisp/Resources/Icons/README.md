# Native icons in Wisp

The 21 collection/action icons are unmodified **Phosphor Regular** artwork from
the official [Phosphor core repository](https://github.com/phosphor-icons/core).
Retrieved October 28, 2026. Copyright (c) 2023 Phosphor Icons; MIT licensed.
The complete license is included as `LICENSE.txt`.

Each original SVG is retained in `Sources/`. Its exact upstream path is
`https://github.com/phosphor-icons/core/blob/main/assets/regular/<filename>.svg`.
Wisp loads the same artwork as native template PDF images. Conversion preserves
the paths, aspect ratio, transparent background, and regular weight. No traced
or generated replacement artwork is used.

The PDFs were produced using librsvg 2.61.3 / Cairo 1.18.4:

    rsvg-convert --format pdf --width 256 --height 256 --output icon.pdf Sources/icon.svg

Regular was selected for readability at Wisp's 12–14 point navigation sizes.
`WispIcon.swift` defines the mapping from UI meaning to the supplied artwork.
The Collection Music row uses `wisp.music`. Origin media types use the seven
Lucide icons documented below; their existing SF Symbol names are semantic
aliases and fallbacks, so stored library metadata does not change.

## Lucide media origins

Seven official SVGs were fetched from the [Lucide repository](https://github.com/lucide-icons/lucide)
through the connected GitHub file API on October 28, 2026. Exact source files are
retained in `Sources/LucideOriginal/`; `provenance.json` records each upstream URL
and verified Git blob SHA. The complete upstream ISC license, including its
Feather-derived icon MIT notice, is retained in `LICENSE-LUCIDE.txt`.

The render copies in `Sources/lucide-*.svg` change only `stroke-width="2"` to
`stroke-width="1.5"`. All paths, proportions, joins, round caps, and transparent
backgrounds remain unchanged. This is Lucide's supported configurable stroke
width, chosen for a light neutral presence at 12-point display size.

| Origin alias | Official Lucide artwork |
| --- | --- |
| `gamecontroller` | `gamepad-2` |
| `film` | `film` |
| `tv` | `tv` |
| `book.closed` | `book-open` |
| `mic` | `mic` |
| `music.note` | `eighth-notes` |
| `square.stack` | `layers` |

Lucide's current `eighth-notes.json` lists `music` as its deprecated alias; this
metadata is included with the original sources. Native PDFs were generated with:

    rsvg-convert --format pdf --dpi-x 72 --dpi-y 72 --output lucide-name.pdf Sources/lucide-name.svg

Each PDF has a 24-point canvas. `WispIconResources` preserves the 14-point native
image intrinsic size and template rendering, so small menus never grow to the
source artwork size. Both track origin rows and sidebar origins use these images.
