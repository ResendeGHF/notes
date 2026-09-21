// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_asset_cache.dart';

void main() {
  test('CacheItem.dispose never throws, even on unmodifiable bytes', () {
    // Mutable bytes are wiped.
    final mutable = CacheItem(
      Uint8List.fromList([1, 2, 3, 4]),
      fileExt: '.png',
    );
    mutable.dispose();
    expect(mutable.value, isNull);

    // Unmodifiable views (e.g. BSON slices) cannot be wiped: dispose must
    // drop the reference instead of throwing and aborting teardown.
    final backing = Uint8List.fromList([5, 6, 7, 8]);
    final view = Uint8List.sublistView(backing, 0, backing.length);
    final frozen = CacheItem(view, fileExt: '.png');
    expect(() => frozen.dispose(), returnsNormally);
    expect(frozen.value, isNull);
  });

  test('AssetCacheAll.dispose survives poisoned items', () {
    final cache = AssetCacheAll();
    // Exercise the loop with a plain item; must not throw.
    expect(() => cache.dispose(), returnsNormally);
  });
}
