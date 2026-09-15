import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/services/sba_encryption.dart';

void main() {
  group('SbaEncryption (backups & encrypted export)', () {
    test('GCM roundtrip encrypt / decrypt', () {
      final plain = Uint8List.fromList(utf8.encode('hello backup payload'));
      final enc = SbaEncryption.encrypt(plain, 'secret-password');
      expect(SbaEncryption.isEncrypted(enc), isTrue);
      // Current generation magic is SABER_SBA_ENC\x03 (byte index 13).
      expect(enc[13], 0x03);
      final out = SbaEncryption.decrypt(enc, 'secret-password');
      expect(utf8.decode(out), 'hello backup payload');
    });

    test('wrong password throws', () {
      final enc = SbaEncryption.encrypt(
        Uint8List.fromList([1, 2, 3, 4]),
        'good',
      );
      expect(() => SbaEncryption.decrypt(enc, 'wrong'), throwsArgumentError);
    });

    test('tampered ciphertext throws before plaintext is returned', () {
      final enc = SbaEncryption.encrypt(
        Uint8List.fromList(utf8.encode('important backup payload')),
        'good',
      );
      enc[enc.length - 8] ^= 0x7f;

      expect(() => SbaEncryption.decrypt(enc, 'good'), throwsArgumentError);
    });

    test('legacy CBC payloads remain readable', () {
      final plain = Uint8List.fromList(utf8.encode('legacy backup payload'));
      final enc = SbaEncryption.encryptLegacyForTest(plain, 'old-key');

      expect(SbaEncryption.isEncrypted(enc), isTrue);
      expect(
        utf8.decode(SbaEncryption.decrypt(enc, 'old-key')),
        'legacy backup payload',
      );
    });

    test('v2 CBC+HMAC payloads remain readable', () {
      final plain = Uint8List.fromList(utf8.encode('hmac backup payload'));
      final enc = SbaEncryption.encryptHmacCbcForTest(plain, 'hmac-key');

      expect(SbaEncryption.isEncrypted(enc), isTrue);
      expect(enc[13], 0x02);
      expect(
        utf8.decode(SbaEncryption.decrypt(enc, 'hmac-key')),
        'hmac backup payload',
      );
    });

    test('SbaEncryptSession reuses Scrypt and decrypts each GCM block', () {
      final session = SbaEncryptSession('session-password');
      late Uint8List a;
      late Uint8List b;
      try {
        a = session.encrypt(Uint8List.fromList(utf8.encode('block-one')));
        b = session.encrypt(Uint8List.fromList(utf8.encode('block-two')));
      } finally {
        session.dispose();
      }

      expect(a[13], 0x03);
      expect(b[13], 0x03);
      // Same salt (one derivation), unique nonces.
      expect(a.sublist(14, 30), b.sublist(14, 30));
      expect(a.sublist(30, 42), isNot(equals(b.sublist(30, 42))));
      expect(
        utf8.decode(SbaEncryption.decrypt(a, 'session-password')),
        'block-one',
      );
      expect(
        utf8.decode(SbaEncryption.decrypt(b, 'session-password')),
        'block-two',
      );
    });
  });
}
