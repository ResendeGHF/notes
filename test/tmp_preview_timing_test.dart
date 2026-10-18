// Temporary benchmark: can we decode JPEG previews fast with dart:ui codecs,
// including inside a background isolate? (deleted after measuring)
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

Future<int> probe(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final longest = math.max(descriptor.width, descriptor.height);
  final target = longest <= 220 ? longest : 220;
  final codec = await descriptor.instantiateCodec(
    targetWidth: math.max(1, (descriptor.width * target / longest).round()),
    targetHeight: math.max(1, (descriptor.height * target / longest).round()),
  );
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final n = data?.lengthInBytes ?? 0;
  frame.image.dispose();
  codec.dispose();
  return n;
}

void main() {
  test('dart:ui preview decode timing', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = Directory('/tmp/opencode/import_test/allimg/OEBPS');
    if (!dir.existsSync()) {
      markTestSkipped('missing fixtures');
      return;
    }
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jpg'))
        .take(400)
        .toList();
    final bytes = [for (final f in files) f.readAsBytesSync()];
    await probe(bytes[0]); // warmup
    var sw = Stopwatch()..start();
    for (final b in bytes.take(100)) {
      await probe(b);
    }
    // ignore: avoid_print
    print('PROBE serial100=${sw.elapsedMilliseconds}ms');

    sw = Stopwatch()..start();
    var pending = <Future<void>>[];
    for (final b in bytes.take(400)) {
      pending.add(probe(b));
      if (pending.length == 8) {
        await Future.wait(pending);
        pending = <Future<void>>[];
      }
    }
    await Future.wait(pending);
    // ignore: avoid_print
    print('PROBE windowed8_400=${sw.elapsedMilliseconds}ms');

    sw = Stopwatch()..start();
    final counts = await Isolate.run(() async {
      final list = bytes.take(100).toList();
      for (final b in list) {
        await probe(b);
      }
      return list.length;
    });
    // ignore: avoid_print
    print('PROBE isolate100=${sw.elapsedMilliseconds}ms n=$counts');
  });
}
