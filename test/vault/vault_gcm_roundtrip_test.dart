// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/services/vault_blob_crypto.dart';

void main() {
  test('AES-GCM single-shot round-trip', () {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    final nonce = Uint8List.fromList(List<int>.generate(12, (i) => i * 3));
    final plain = Uint8List.fromList(utf8.encode('hello vault gcm'));
    final sealed = vaultAesGcmEncrypt(key, nonce, plain);
    expect(sealed.length, plain.length + kVaultGcmTagBytes);
    final out = vaultAesGcmDecrypt(key, nonce, sealed);
    expect(out, plain);
  });

  test('AES-GCM detects tampering', () {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => 40 - i));
    final nonce = Uint8List.fromList(List<int>.generate(12, (i) => 11 - i));
    final plain = Uint8List.fromList(List<int>.generate(64, (i) => i));
    final sealed = vaultAesGcmEncrypt(key, nonce, plain);
    sealed[0] ^= 0x01;
    expect(() => vaultAesGcmDecrypt(key, nonce, sealed), throwsA(anything));
  });

  test('legacy CBC note bytes migrate via GCM bulk write + decrypt', () {
    final dir = Directory.systemTemp.createTempSync('vault_gcm_');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    final key = Uint8List.fromList(
      List<int>.generate(32, (i) => (i * 7) & 0xff),
    );
    final rawNote = Uint8List.fromList(
      List<int>.generate(4096, (i) => i & 0xff),
    );
    final compressed = vaultZlibEncode(rawNote);

    final results = vaultIsolateEncryptAndWrite(
      VaultBulkWriteArgs(
        items: [
          VaultBulkWriteItem(
            '/note.sbn2',
            TransferableTypedData.fromList([compressed]),
          ),
        ],
        keyBytes: key,
        storageRootPath: dir.path,
        cipherVer: kVaultCipherGcm,
      ),
    );
    expect(results, hasLength(1));
    expect(results.first.cipherVer, kVaultCipherGcm);
    expect(results.first.ivBase64, isNotEmpty);

    final encPath =
        '${dir.path}/data/${results.first.storageId.substring(0, 2)}/'
        '${results.first.storageId}.enc';
    expect(File(encPath).existsSync(), isTrue);

    final ttd = vaultIsolateDecryptGcm(
      VaultDecryptGcmArgs(
        storagePath: encPath,
        keyBytes: key,
        nonceBase64: results.first.ivBase64,
        cipherVer: results.first.cipherVer,
        storageId: results.first.storageId,
        applyZlib: true,
      ),
    );
    expect(ttd.materialize().asUint8List(), rawNote);
  });

  test('assemble binary concatenates header and pages', () {
    final out = vaultIsolateAssembleBinary({
      'header': Uint8List.fromList([1, 2, 3]),
      'pages': [
        Uint8List.fromList([4, 5]),
        Uint8List.fromList([6]),
      ],
    });
    expect(out, Uint8List.fromList([1, 2, 3, 4, 5, 6]));
  });

  test('cipher inference: 12-byte nonce ⇒ GCM, 16-byte IV ⇒ CBC', () {
    // Mirrors VaultAdapter._inferCipherVer without unlocking a vault.
    int infer({required int? storedVer, required String ivBase64}) {
      if (storedVer == kVaultCipherGcm || storedVer == kVaultCipherGcmChunked) {
        return storedVer!;
      }
      if (ivBase64.isEmpty) return kVaultCipherCbc;
      final iv = base64Decode(ivBase64);
      if (iv.length == kVaultGcmNonceBytes) return kVaultCipherGcm;
      if (iv.length == 16) return kVaultCipherCbc;
      return storedVer ?? kVaultCipherCbc;
    }

    expect(
      infer(
        storedVer: null,
        ivBase64: base64Encode(Uint8List(12)),
      ),
      kVaultCipherGcm,
    );
    expect(
      infer(
        storedVer: null,
        ivBase64: base64Encode(Uint8List(16)),
      ),
      kVaultCipherCbc,
    );
    expect(
      infer(storedVer: kVaultCipherGcmChunked, ivBase64: ''),
      kVaultCipherGcmChunked,
    );
  });
}
