// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/canvas_gesture_detector.dart';
import 'package:saber/data/editor/page.dart';

/// Regression: pages ahead of the viewport must keep hydrating while the app
/// is idle — no scrolling, no rebuilds, no frames being produced. The old
/// frame-chained warm-up sweep only advanced while frames happened (an idle
/// app stopped warming entirely), so a fling or jump landed on a blank lazy
/// shell that only started parsing on arrival.
void main() {
  testWidgets('warm-up pump hydrates lazy shells with no user interaction', (
    tester,
  ) async {
    const pageCount = 16;
    final pages = List<EditorPage>.generate(
      pageCount,
      (i) => i < 2 ? EditorPage() : EditorPage(isLazyShell: true),
    );
    var started = 0;
    var completed = 0;

    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return CanvasGestureDetector(
              filePath: '/tmp/warmup-pump-note',
              isDrawGesture: (_) => false,
              onDrawStart: (_) {},
              onDrawUpdate: (_) {},
              onDrawEnd: (_) {},
              updatePointerData: (_, __, ___) {},
              onHovering: () {},
              onHoveringEnd: () {},
              onStylusButtonChanged: (_) {},
              onLongPress: (_) {},
              undo: () {},
              redo: () {},
              pages: pages,
              initialPageIndex: 0,
              pageBuilder: (context, i) => const SizedBox.expand(),
              placeholderPageBuilder: (context, i) => const SizedBox.expand(),
              isTextEditing: () => false,
              tryHydratePage: (i) {
                if (!pages[i].isLazyShell) return false;
                started++;
                // Simulated chunked parse: completes on its own timer, with
                // no frame required from the test harness.
                Timer(const Duration(milliseconds: 10), () {
                  completed++;
                  pages[i] = EditorPage();
                  rebuild(() {});
                });
                return true;
              },
              );
            },
          ),
        ),
      ),
    );

    // Drain the open frames, then stay idle. A single long advance with no
    // further interaction: frame-driven sweeps would only get one pass out
    // of this, the pump converges because it is Timer-driven.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(completed, pageCount - 2);
    expect(pages.where((page) => page.isLazyShell), isEmpty);
  });
}
