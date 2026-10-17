// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/document_conversion/djvu/djvu_zp.dart';

import 'djvu/djvu_fixture.dart';

void main() {
  group('ZpDecoder', () {
    test('replays the reference encoder script bit for bit', () {
      final data = File(
        '$djvuFixtureRoot/zp/stream.zp',
      ).readAsBytesSync();
      final steps =
          jsonDecode(
                File('$djvuFixtureRoot/zp/steps.json').readAsStringSync(),
              )
              as List<dynamic>;
      expect(steps, hasLength(400));

      final zp = ZpDecoder(data);
      final ctx = Uint8List(80);

      for (var stepIndex = 0; stepIndex < steps.length; stepIndex++) {
        final step = steps[stepIndex] as List<dynamic>;
        final kind = step[0] as String;
        switch (kind) {
          case 'bit':
            final ctxIndex = step[1] as int;
            final expected = (step[2] as int) != 0;
            expect(
              zp.decodeBitAt(ctx, ctxIndex),
              expected,
              reason: 'step $stepIndex: bit(ctx $ctxIndex)',
            );
          case 'run':
            final ctxIndex = step[1] as int;
            final expected = (step[2] as int) != 0;
            final count = step[3] as int;
            for (var i = 0; i < count; i++) {
              expect(
                zp.decodeBitAt(ctx, ctxIndex),
                expected,
                reason: 'step $stepIndex: run bit $i/$count (ctx $ctxIndex)',
              );
            }
          case 'pt':
            expect(
              zp.decodePassthrough(),
              (step[1] as int) != 0,
              reason: 'step $stepIndex: passthrough',
            );
          case 'pt44':
            expect(
              zp.decodePassthroughIw44(),
              (step[1] as int) != 0,
              reason: 'step $stepIndex: IW44 passthrough',
            );
          default:
            fail('unknown step kind "$kind" at step $stepIndex');
        }
      }

      // The encoder's flush leaves a handful of synthetic padding bytes, but
      // the decoder must not still be spinning on the end of the input.
      expect(zp.syntheticBytes, lessThanOrEqualTo(16));
    });

    test('rejects inputs shorter than two bytes', () {
      expect(() => ZpDecoder(Uint8List(0)), throwsA(isA<ZpInitException>()));
      expect(() => ZpDecoder(Uint8List(1)), throwsA(isA<ZpInitException>()));
    });

    test('reads 0xFF past the end of the input', () {
      final zp = ZpDecoder(Uint8List.fromList([0x00, 0x00]));
      // Drive the coder until it has consumed synthetic padding; every decoded
      // bit is deterministic and the overshoot is accounted for.
      final ctx = Uint8List(1);
      for (var i = 0; i < 1000; i++) {
        zp.decodeBitAt(ctx, 0);
      }
      expect(zp.isExhausted, isTrue);
      expect(zp.syntheticBytes, greaterThan(0));
    });
  });
}
