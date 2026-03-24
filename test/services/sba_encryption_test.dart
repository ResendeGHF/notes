import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/services/sba_encryption.dart';

void main() {
  group('SbaEncryption (backups & encrypted export)', () {
    test('roundtrip encrypt / decrypt', () {
      final plain = Uint8List.fromList(utf8.encode('hello backup payload'));
      final enc = SbaEncryption.encrypt(plain, 'secret-password');
      expect(SbaEncryption.isEncrypted(enc), isTrue);
      final out = SbaEncryption.decrypt(enc, 'secret-password');
      expect(utf8.decode(out), 'hello backup payload');
    });

    test('wrong password throws', () {
      final enc = SbaEncryption.encrypt(
        Uint8List.fromList([1, 2, 3, 4]),
        'good',
      );
      expect(
        () => SbaEncryption.decrypt(enc, 'wrong'),
        throwsArgumentError,
      );
    });

    test('plain bytes are not encrypted format', () {
      expect(SbaEncryption.isEncrypted(Uint8List(4)), isFalse);
    });
  });
}
