import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('saber_folder_count_');
    FileManager.documentsDirectory = tmp.path;
    // Ensure non-vault mode
    stows.localEncryptionEnabled.value = false;
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('non-vault recursive folder count includes nested files', () async {
    final nested = Directory('${tmp.path}/A/B')..createSync(recursive: true);
    File('${nested.path}/note.sbn2').writeAsBytesSync([1, 2, 3]);
    File('${tmp.path}/A/top.sbn2').writeAsBytesSync([4, 5]);
    // Stale props saying zero should be rebuilt due to bundle version bump
    File('${tmp.path}/A/.folder_props').writeAsStringSync(
      jsonEncode({
        'file_count': 0,
        'total_size': 0,
        'bundle_size_version': 1,
        'created_at': 1,
        'last_modified': 1,
      }),
    );

    final count = await FileManager.getFolderFileCount('/A');
    expect(count, 2);

    final batch = await FileManager.getFolderFileCountsBatch(['/A']);
    expect(batch['/A/'], 2);
  });
}
