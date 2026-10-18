#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Regenerates the EPUB conversion fixtures. Run from the repository root:
#
#   python3 test/data/document_conversion/fixtures/epub/generate.py
#
# The fixtures are hand-built on purpose: small, deterministic and covering
# exactly the parser/converter behaviours the tests pin (EPUB3 nav and EPUB2
# NCX tables of contents, nested sections, a table-of-contents fragment that
# does not exist, external links, a stylesheet with an @import, an image and a
# paragraph long enough to span pages).

import os
import struct
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
DATE_TIME = (2026, 1, 1, 0, 0, 0)


def write_zip(path, entries):
    """Writes a deterministic ZIP; `entries` is a list of (name, bytes)."""
    with zipfile.ZipFile(path, "w") as archive:
        for name, data in entries:
            info = zipfile.ZipInfo(name, date_time=DATE_TIME)
            info.compress_type = (
                zipfile.ZIP_STORED if name == "mimetype" else zipfile.ZIP_DEFLATED
            )
            info.external_attr = 0o644 << 16
            archive.writestr(info, data)
    print(f"wrote {path}")


def png(width, height, pixel):
    """A tiny solid-colour PNG encoder (no PIL dependency)."""

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    row = b"\x00" + bytes(pixel) * width
    idat = zlib.compress(row * height)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", idat)
        + chunk(b"IEND", b"")
    )


def paragraphs(count, seed):
    """Deterministic filler paragraphs with a few accented characters."""
    return "\n".join(f"<p>{text_of(1, seed + i)}</p>" for i in range(count))


def text_of(groups, seed):
    """A single run of deterministic filler text (48 words per group)."""
    words = (
        "lorem ipsum dolor sit amet consectetur adipiscing elit sed do "
        "eiusmod tempor incididunt ut labore et dolore magna aliqua caf\u00e9 "
        "na\u00efve \u2014 qu\u2019on".split()
    )
    out = []
    for i in range(groups):
        start = (seed + i * 7) % len(words)
        out.append(" ".join(words[(start + j) % len(words)] for j in range(48)))
    return " ".join(out) + "."


CONTAINER = """<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""


def book_epub():
    """EPUB3 book: nav TOC, three chapters, CSS with @import, image, links."""
    opf = """<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:saber-test-book</dc:identifier>
    <dc:title>The Test Book</dc:title>
    <dc:creator>A. Author</dc:creator>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="c1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="c3" href="text/ch3.xhtml" media-type="application/xhtml+xml"/>
    <item id="css" href="styles/main.css" media-type="text/css"/>
    <item id="css2" href="styles/extra.css" media-type="text/css"/>
    <item id="pic" href="images/pic.png" media-type="image/png"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
    <itemref idref="c2"/>
    <itemref idref="c3"/>
  </spine>
</package>
"""

    nav = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Contents</title></head>
<body>
<nav epub:type="toc">
  <h1>Contents</h1>
  <ol>
    <li><a href="text/ch1.xhtml">Chapter 1 \u2014 Start</a>
      <ol>
        <li><a href="text/ch1.xhtml#sec-1-1">Section 1.1</a></li>
        <li><a href="text/ch1.xhtml#sec-1-2">Section 1.2</a></li>
      </ol>
    </li>
    <li><a href="text/ch2.xhtml">Chapter 2 \u2014 Middle</a></li>
    <li><a href="text/ch3.xhtml#does-not-exist">Chapter 3 \u2014 Unknown Fragment</a></li>
    <li><a href="https://example.com/">External Entry</a></li>
  </ol>
</nav>
</body>
</html>
"""

    ch1 = f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
  <title>Chapter One</title>
  <link rel="stylesheet" type="text/css" href="../styles/main.css"/>
</head>
<body>
  <h1>Chapter One</h1>
  <p class="lead" id="sec-1-1">{text_of(60, 1)}</p>
  <h2 id="sec-1-2">Section 1.2</h2>
  {paragraphs(6, 3)}
  <p id="linker">See <a href="#sec-1-2">the second section</a>, then
  <a href="ch2.xhtml#ch2">chapter two</a>, the
  <a href="../styles/main.css">stylesheet</a>, or
  <a href="https://example.com/read">the web</a>.</p>
  <p><img src="../images/pic.png" alt="Picture" width="120" height="80"/></p>
  {paragraphs(4, 5)}
</body>
</html>
"""

    ch2 = f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Chapter Two</title></head>
<body>
  <h1 id="ch2">Chapter Two</h1>
  {paragraphs(12, 7)}
  <ul>
    <li>First item</li>
    <li>Second item</li>
  </ul>
  {paragraphs(6, 9)}
</body>
</html>
"""

    ch3 = f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Chapter Three</title></head>
<body>
  <h1 id="ch3">Chapter Three</h1>
  {paragraphs(8, 11)}
</body>
</html>
"""

    main_css = """@import "extra.css";

body { margin: 0; padding: 0; }
.lead { text-indent: 1.2em; }
h1, h2 { color: #112233; }
"""
    extra_css = """p { margin-top: 0.4em; margin-bottom: 0.4em; }
em { font-style: italic; }
"""

    write_zip(
        os.path.join(HERE, "book.epub"),
        [
            ("mimetype", b"application/epub+zip"),
            ("META-INF/container.xml", CONTAINER.encode()),
            ("EPUB/package.opf", opf.encode()),
            ("EPUB/nav.xhtml", nav.encode()),
            ("EPUB/text/ch1.xhtml", ch1.encode()),
            ("EPUB/text/ch2.xhtml", ch2.encode()),
            ("EPUB/text/ch3.xhtml", ch3.encode()),
            ("EPUB/styles/main.css", main_css.encode()),
            ("EPUB/styles/extra.css", extra_css.encode()),
            ("EPUB/images/pic.png", png(4, 3, (40, 80, 160))),
        ],
    )


def ncx_epub():
    """EPUB2 book: the table of contents comes from the NCX file."""
    opf = """<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:saber-test-ncx</dc:identifier>
    <dc:title>NCX Book</dc:title>
    <dc:creator>B. Author</dc:creator>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="c1"/>
  </spine>
</package>
"""
    ncx = """<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head><meta name="dtb:uid" content="urn:uuid:saber-test-ncx"/></head>
  <docTitle><text>NCX Book</text></docTitle>
  <navMap>
    <navPoint id="np1" playOrder="1">
      <navLabel><text>Only Chapter</text></navLabel>
      <content src="ch1.xhtml"/>
    </navPoint>
  </navMap>
</ncx>
"""
    ch1 = f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Only Chapter</title></head>
<body>
  <h1>Only Chapter</h1>
  {paragraphs(10, 2)}
</body>
</html>
"""
    write_zip(
        os.path.join(HERE, "ncx.epub"),
        [
            ("mimetype", b"application/epub+zip"),
            ("META-INF/container.xml", CONTAINER.encode()),
            ("EPUB/package.opf", opf.encode()),
            ("EPUB/toc.ncx", ncx.encode()),
            ("EPUB/ch1.xhtml", ch1.encode()),
        ],
    )


if __name__ == "__main__":
    book_epub()
    ncx_epub()
