// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/services/pdf_native_texture.dart';
import 'package:saber/services/pdf_open_helper.dart';
import 'package:saber/services/pdf_page_thumbnail_cache.dart';
import 'package:saber/services/pdf_viewport.dart';

void main() {
  group('PdfPageThumbnailCache keys', () {
    test('stable for identical identity', () {
      final a = PdfPageThumbnailCache.cacheKeyFor(
        fileSize: 123456,
        mtimeMs: 789,
        pageIndex: 3,
        targetWidth: 360,
      );
      final b = PdfPageThumbnailCache.cacheKeyFor(
        fileSize: 123456,
        mtimeMs: 789,
        pageIndex: 3,
        targetWidth: 360,
      );
      expect(a, b);
      expect(PdfPageThumbnailCache.looksLikeCacheKey(a), isTrue);
    });

    test('edits / page / width invalidate', () {
      String key({int size = 1, int mtime = 1, int page = 0, int w = 360}) =>
          PdfPageThumbnailCache.cacheKeyFor(
            fileSize: size,
            mtimeMs: mtime,
            pageIndex: page,
            targetWidth: w,
          );
      expect(key(size: 1), isNot(key(size: 2)));
      expect(key(mtime: 1), isNot(key(mtime: 2)));
      expect(key(page: 0), isNot(key(page: 1)));
      expect(key(w: 360), isNot(key(w: 720)));
    });
  });

  group('PdfOpenHelper.spillBytesToTempFile', () {
    test('round-trips bytes to a temp mmap file', () async {
      final bytes = Uint8List.fromList(List.generate(256, (i) => i & 0xFF));
      final path = await PdfOpenHelper.spillBytesToTempFile(
        bytes,
        sourceName: 'test',
      );
      expect(path, isNotNull);
      try {
        expect(File(path!).existsSync(), isTrue);
        expect(File(path).lengthSync(), bytes.length);
      } finally {
        try {
          File(path!).deleteSync();
        } catch (_) {}
      }
    });
  });
  _pdfTileMathTests();
  _pdfTileBoxTests();
  _pdfTilingPolicyTests();
  _pdfClipTests();
  _pdfTilePlanTests();
}

void _pdfTileMathTests() {
  group('PdfTileMath.displaySize', () {
    test('unrotated and 180 stay as-is, 90/270 swap', () {
      const natural = Size(595, 842);
      expect(PdfTileMath.displaySize(natural, 0), natural);
      expect(PdfTileMath.displaySize(natural, 2), natural);
      expect(
        PdfTileMath.displaySize(natural, 1),
        const Size(842, 595),
      );
      expect(
        PdfTileMath.displaySize(natural, 3),
        const Size(842, 595),
      );
    });

    test('tiling only for unrotated pages', () {
      expect(PdfTileMath.supportsTiling(0), isTrue);
      expect(PdfTileMath.supportsTiling(1), isFalse);
      expect(PdfTileMath.supportsTiling(2), isFalse);
      expect(PdfTileMath.supportsTiling(3), isFalse);
    });
  });

  group('PdfTileMath.bitmapSizeFor', () {
    test('deep-zoom tile stays small but exact', () {
      // 500% zoom paragraph: 200x150pt visible, shown at 1000x750 CSS px
      // on a 3x panel = 3000x2250 physical. Capped to 3072 edge.
      final out = PdfTileMath.bitmapSizeFor(
        clipPt: const Rect.fromLTWH(100, 200, 200, 150),
        visibleGlobalSize: const Size(1000, 750),
        devicePixelRatio: 3.0,
      );
      expect(out.width <= 3072, isTrue);
      expect(out.height <= 3072, isTrue);
      // Aspect preserved: 200x150 -> 4:3.
      expect(out.width / out.height, closeTo(4 / 3, 0.02));
      // Full physical need fits under the cap: rendered exact, razor sharp.
      expect(out.width, 3000);
      expect(out.height, 2250);
    });

    test('oversized need is capped, aspect preserved', () {
      final out = PdfTileMath.bitmapSizeFor(
        clipPt: const Rect.fromLTWH(0, 0, 100, 200),
        visibleGlobalSize: const Size(2000, 4000),
        devicePixelRatio: 3.0,
      );
      expect(out.width <= 3072, isTrue);
      expect(out.height <= 3072, isTrue);
      expect(out.width / out.height, closeTo(0.5, 0.02));
    });

    test('degenerate input collapses to 1x1, never zero/negative', () {
      final out = PdfTileMath.bitmapSizeFor(
        clipPt: Rect.zero,
        visibleGlobalSize: const Size(100, 100),
        devicePixelRatio: 2.0,
      );
      expect(out.width, 1);
      expect(out.height, 1);
    });
  });

  group('PdfOpenHelper thresholds', () {
    test('small-bytes threshold is sane', () {
      expect(PdfOpenHelper.smallBytesDirectOpenThreshold, 4 * 1024 * 1024);
    });
  });
}
void _pdfTileBoxTests() {
  group('PdfTileMath.tileBox', () {
    test('maps clip points to local units (document space)', () {
      // Page displayed at 2x (box 1190x1684 for 595x842pt page).
      final pos = PdfTileMath.tileBox(
        clipPt: const Rect.fromLTWH(100, 200, 200, 150),
        boxSize: const Size(1190, 1684),
        pageSizePt: const Size(595, 842),
      );
      expect(pos.left, closeTo(200, 0.001));
      expect(pos.top, closeTo(400, 0.001));
      expect(pos.width, closeTo(400, 0.001));
      expect(pos.height, closeTo(300, 0.001));
    });

    test('1:1 mapping when box matches page points', () {
      const clip = Rect.fromLTWH(10, 20, 100, 50);
      final pos = PdfTileMath.tileBox(
        clipPt: clip,
        boxSize: const Size(595, 842),
        pageSizePt: const Size(595, 842),
      );
      expect(pos, clip);
    });

    test('degenerate input yields zero (never NaN/negative)', () {
      expect(
        PdfTileMath.tileBox(
          clipPt: Rect.zero,
          boxSize: const Size(100, 100),
          pageSizePt: const Size(595, 842),
        ),
        Rect.zero,
      );
      expect(
        PdfTileMath.tileBox(
          clipPt: const Rect.fromLTWH(0, 0, 10, 10),
          boxSize: Size.zero,
          pageSizePt: const Size(595, 842),
        ),
        Rect.zero,
      );
    });
  });
}

void _pdfTilingPolicyTests() {
  group('PdfTileMath tiling policy', () {
    test('hysteresis band prevents mode flapping', () {
      expect(PdfTileMath.tiledZoomThreshold, 2.0);
      expect(PdfTileMath.tiledZoomExit, 1.8);
      expect(PdfTileMath.tiledZoomExit, lessThan(PdfTileMath.tiledZoomThreshold));
    });

    test('tile bitmaps stay within the VRAM cap', () {
      // Worst-case tile: fullscreen need on a 3x panel, capped at 3072.
      final out = PdfTileMath.bitmapSizeFor(
        clipPt: const Rect.fromLTWH(0, 0, 595, 842),
        visibleGlobalSize: const Size(2000, 3000),
        devicePixelRatio: 3.0,
      );
      expect(out.width <= 3072, isTrue);
      expect(out.height <= 3072, isTrue);
    });

    test('full-page fraction threshold keeps near-full pages whole', () {
      expect(PdfTileMath.fullPageFractionThreshold, 0.8);
    });
  });

  group('PdfViewportBus', () {
    test('tick and settle bump independent epochs', () {
      final e0 = PdfViewportBus.epoch.value;
      final s0 = PdfViewportBus.settleEpoch.value;
      PdfViewportBus.tick();
      expect(PdfViewportBus.epoch.value, e0 + 1);
      expect(PdfViewportBus.settleEpoch.value, s0);
      PdfViewportBus.settle();
      expect(PdfViewportBus.settleEpoch.value, s0 + 1);
    });
  });
}

void _pdfClipTests() {
  group('PdfClip', () {
    test('equality, hash and validity gate channel payloads', () {
      const a = PdfClip(
        Rect.fromLTWH(10, 20, 100, 50),
        pageSize: Size(595, 842),
      );
      const b = PdfClip(
        Rect.fromLTWH(10, 20, 100, 50),
        pageSize: Size(595, 842),
      );
      const c = PdfClip(
        Rect.fromLTWH(10, 20, 100, 50),
        pageSize: Size(842, 595),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a.isValid, isTrue);
      expect(
        const PdfClip(Rect.zero, pageSize: Size(10, 10)).isValid,
        isFalse,
      );
    });
  });
}

void _pdfTilePlanTests() {
  group('PdfTileMath.tilePlan', () {
    test('density is an integer multiple of base; origin on grid', () {
      const page = Size(595, 842);
      const baseDensity = 3.5;
      final plan = PdfTileMath.tilePlan(
        want: const Rect.fromLTWH(100.3, 200.7, 200, 150),
        pageSize: page,
        needPhysical: const Size(1000, 750),
        baseDensity: baseDensity,
      );
      expect(plan.clip.isEmpty, isFalse);
      expect(
        plan.clip.left,
        closeTo((100.3 * baseDensity).floor() / baseDensity, 1e-9),
      );
      expect(
        plan.clip.top,
        closeTo((200.7 * baseDensity).floor() / baseDensity, 1e-9),
      );
      final k = plan.density / baseDensity;
      expect(k, closeTo(k.roundToDouble(), 1e-9));
      expect(plan.width, ((plan.clip.width) * plan.density).round());
      expect(plan.height, ((plan.clip.height) * plan.density).round());
      expect(plan.clip.left, lessThanOrEqualTo(100.3));
      expect(plan.clip.top, lessThanOrEqualTo(200.7));
      expect(plan.clip.right, greaterThanOrEqualTo(300.3));
      expect(plan.clip.bottom, greaterThanOrEqualTo(350.7));
    });

    test('degenerate input collapses safely', () {
      final out = PdfTileMath.tilePlan(
        want: Rect.zero,
        pageSize: const Size(595, 842),
        needPhysical: const Size(100, 100),
        baseDensity: 3.0,
      );
      expect(out.width, 1);
      expect(out.clip.isEmpty, isTrue);
    });

    test('baseBitmap is layout x dpr capped at edge', () {
      final b = PdfTileMath.baseBitmap(
        boxSize: const Size(400, 565),
        devicePixelRatio: 3.0,
      );
      expect(b.width <= 2048, isTrue);
      expect(b.width / b.height, closeTo(400 / 565, 0.01));
    });
  });
}
