// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// GPU-budget regression tests: every bitmap size the PDF pipeline can
// request (base layer, deep-zoom tiles, thumbnail probes) must stay within
// hard per-axis caps for any zoom up to kMaxScale (10x) and any DPR up to 4.
// Oversized or zero-sized allocations trip Impeller FBO checks on the raster
// thread and abort the process (native crash, uncatchable from Dart), so
// these caps are load-bearing. See PdfTexturePlugin (SurfaceProducer path).
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/services/pdf_viewport.dart';

void main() {
  group('PDF GPU budget caps', () {
    // A large textbook page in displayed points.
    const page = Size(800, 1100);

    test('baseBitmap never exceeds its edge cap (dpr 1..4)', () {
      for (final cap in [1536, 2048, 3072]) {
        for (final dpr in [1.0, 2.0, 2.625, 3.0, 4.0]) {
          final bmp = PdfTileMath.baseBitmap(
            boxSize: page,
            devicePixelRatio: dpr,
            edgeCap: cap,
          );
          expect(bmp.width, inInclusiveRange(1, cap.toDouble()));
          expect(bmp.height, inInclusiveRange(1, cap.toDouble()));
        }
      }
    });

    test('tilePlan never exceeds its cap at any zoom to 10x', () {
      for (final cap in [1536, 2048, 3072]) {
        for (final zoom in [1.5, 2.0, 4.0, 6.0, 8.0, 10.0]) {
          // Visible region shrinks as zoom grows; physical need is what the
          // screen shows (2304x1440 panel @ dpr 2.625, worst case full-bleed).
          const need = Size(2304 * 2.625, 1440 * 2.625);
          final plan = PdfTileMath.tilePlan(
            want: Rect.fromLTWH(
              100,
              100,
              (page.width - 200) / zoom,
              (page.height - 200) / zoom,
            ),
            pageSize: page,
            needPhysical: need,
            baseDensity: 2.625,
            cap: cap,
          );
          expect(plan.width, inInclusiveRange(1, cap));
          expect(plan.height, inInclusiveRange(1, cap));
        }
      }
    });

    test('bitmapSizeFor never exceeds its cap for huge viewports', () {
      for (final cap in [1536, 2048, 3072]) {
        final bmp = PdfTileMath.bitmapSizeFor(
          clipPt: const Rect.fromLTWH(0, 0, 800, 1100),
          // Pathological: whole 4x-downscaled panel claimed visible.
          visibleGlobalSize: const Size(9000, 9000),
          devicePixelRatio: 1.0,
          cap: cap,
        );
        expect(bmp.width, inInclusiveRange(1, cap));
        expect(bmp.height, inInclusiveRange(1, cap));
      }
    });

    test('withTileMargin stays inside the page and expands coverage', () {
      const want = Rect.fromLTWH(100, 100, 400, 500);
      final m = PdfTileMath.withTileMargin(want, page);
      expect(m.left, lessThan(want.left));
      expect(m.top, lessThan(want.top));
      expect(m.right, greaterThan(want.right));
      expect(m.bottom, greaterThan(want.bottom));
      expect(m.left, greaterThanOrEqualTo(0));
      expect(m.top, greaterThanOrEqualTo(0));
      expect(m.right, lessThanOrEqualTo(page.width));
      expect(m.bottom, lessThanOrEqualTo(page.height));
      // Degenerate input passes through.
      expect(PdfTileMath.withTileMargin(Rect.zero, page), Rect.zero);
    });

    test('fitBitmapToBox matches the painted box aspect within caps', () {
      // Box aspect differs from clip aspect (layout rounding): the bitmap
      // must follow the box, so BoxFit.fill is a uniform scale.
      const clip = Rect.fromLTWH(100, 100, 400, 500);
      const box = Size(820, 1140); // ~2.5% off the page aspect
      final bmp = PdfTileMath.fitBitmapToBox(
        clipPt: clip,
        width: 1600,
        boxSize: box,
        pageSizePt: page,
        cap: 2048,
      );
      expect(bmp.width, 1600);
      final boxAspect = (clip.width * (box.width / page.width)) /
          (clip.height * (box.height / page.height));
      expect(bmp.width / bmp.height, closeTo(boxAspect, 0.002));
      expect(bmp.height, inInclusiveRange(1, 2048));
      // Uniform mapping preserves the clip aspect exactly.
      final sq = PdfTileMath.fitBitmapToBox(
        clipPt: const Rect.fromLTWH(0, 0, 400, 400),
        width: 1000,
        boxSize: const Size(800, 1100),
        pageSizePt: page,
        cap: 2048,
      );
      expect(sq.height, 1000);
    });

    test('degenerate inputs yield 1x1, never zero or NaN', () {
      final a = PdfTileMath.baseBitmap(
        boxSize: Size.zero,
        devicePixelRatio: 3.0,
      );
      expect(a.width, 1);
      expect(a.height, 1);
      final b = PdfTileMath.bitmapSizeFor(
        clipPt: Rect.zero,
        visibleGlobalSize: const Size(100, 100),
        devicePixelRatio: 3.0,
      );
      expect(b.width, 1);
      expect(b.height, 1);
      final c = PdfTileMath.tilePlan(
        want: Rect.zero,
        pageSize: page,
        needPhysical: const Size(100, 100),
        baseDensity: 2.0,
      );
      expect(c.width, 1);
      expect(c.height, 1);
    });
  });
}
