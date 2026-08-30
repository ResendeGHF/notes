// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/export.dart' as pc;

/// Legacy vault blob cipher (AES-256-CBC + PKCS7).
const int kVaultCipherCbc = 0;

/// AES-256-GCM single message (nonce in SQLCipher `files.iv`).
const int kVaultCipherGcm = 1;

/// AES-256-GCM chunked on-disk format (magic SBV2).
const int kVaultCipherGcmChunked = 2;

const int kVaultGcmNonceBytes = 12;
const int kVaultGcmTagBytes = 16;
const int kVaultGcmChunkPlainBytes = 1024 * 1024;
const int kVaultGcmChunkThresholdBytes = 4 * 1024 * 1024;

final _sbv2Magic = Uint8List.fromList([0x53, 0x42, 0x56, 0x32]);

bool vaultLooksLikeZlib(Uint8List data) {
  if (data.length < 2) return false;
  final cmf = data[0];
  final flg = data[1];
  return cmf == 0x78 && ((cmf << 8) + flg) % 31 == 0;
}

Uint8List vaultZlibEncode(Uint8List bytes) {
  if (vaultLooksLikeZlib(bytes)) return bytes;
  return Uint8List.fromList(const ZLibEncoder().encode(bytes));
}

Uint8List vaultZlibDecodeBestEffort(Uint8List bytes) {
  try {
    return Uint8List.fromList(const ZLibDecoder().decodeBytes(bytes));
  } catch (_) {
    return bytes;
  }
}

Uint8List vaultAesGcmEncrypt(Uint8List key, Uint8List nonce, Uint8List plain, {Uint8List? aad}) {
  final cipher = pc.GCMBlockCipher(pc.AESEngine())
    ..init(
      true,
      pc.AEADParameters(
        pc.KeyParameter(key),
        kVaultGcmTagBytes * 8,
        nonce,
        aad ?? Uint8List(0),
      ),
    );
  return cipher.process(plain);
}

Uint8List vaultAesGcmDecrypt(Uint8List key, Uint8List nonce, Uint8List sealed, {Uint8List? aad}) {
  final cipher = pc.GCMBlockCipher(pc.AESEngine())
    ..init(
      false,
      pc.AEADParameters(
        pc.KeyParameter(key),
        kVaultGcmTagBytes * 8,
        nonce,
        aad ?? Uint8List(0),
      ),
    );
  return cipher.process(sealed);
}

class VaultBulkWriteItem {
  VaultBulkWriteItem(this.path, this.data, {this.compressZlib = false});
  final String path;
  final TransferableTypedData data;
  final bool compressZlib;
}

class VaultBulkWriteArgs {
  VaultBulkWriteArgs({
    required this.items,
    required this.keyBytes,
    required this.storageRootPath,
    this.cipherVer = kVaultCipherGcm,
  });
  final List<VaultBulkWriteItem> items;
  final Uint8List keyBytes;
  final String storageRootPath;
  final int cipherVer;
}

class VaultBulkWriteResult {
  VaultBulkWriteResult(
    this.virtualPath,
    this.storageId,
    this.ivBase64,
    this.size, {
    this.cipherVer = kVaultCipherGcm,
  });
  final String virtualPath;
  final String storageId;
  final String ivBase64;
  final int size;
  final int cipherVer;
}

/// zlib (optional) + AES encrypt + write `.enc` for each item. Runs in a worker.
List<VaultBulkWriteResult> vaultIsolateEncryptAndWrite(VaultBulkWriteArgs args) {
  const uuid = UuidLike();
  final results = <VaultBulkWriteResult>[];
  final dataDir = Directory('${args.storageRootPath}/data');
  if (!dataDir.existsSync()) dataDir.createSync(recursive: true);

  final useGcm = args.cipherVer == kVaultCipherGcm ||
      args.cipherVer == kVaultCipherGcmChunked;
  final key = enc.Key(args.keyBytes);
  final cbcEncrypter = useGcm
      ? null
      : enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

  for (final item in args.items) {
    final material = item.data.materialize();
    var plain = Uint8List.view(material, 0, material.lengthInBytes);
    if (item.compressZlib) {
      plain = vaultZlibEncode(plain);
    }
    final plainSize = plain.length;
    final storageId = uuid.v4();
    final prefix = storageId.substring(0, 2);
    final fileDir = Directory('${dataDir.path}/$prefix');
    if (!fileDir.existsSync()) fileDir.createSync();
    final outFile = File('${fileDir.path}/$storageId.enc');

    if (useGcm && plainSize >= kVaultGcmChunkThresholdBytes) {
      final aadPrefix = Uint8List.fromList(utf8.encode(storageId));
      _writeChunkedGcmFile(outFile, args.keyBytes, plain, aadPrefix);
      results.add(
        VaultBulkWriteResult(
          item.path,
          storageId,
          '',
          plainSize,
          cipherVer: kVaultCipherGcmChunked,
        ),
      );
    } else if (useGcm) {
      final nonce = Uint8List(kVaultGcmNonceBytes);
      final random = Random.secure();
      for (var i = 0; i < nonce.length; i++) {
        nonce[i] = random.nextInt(256);
      }
      final sealed = vaultAesGcmEncrypt(args.keyBytes, nonce, plain);
      outFile.writeAsBytesSync(sealed, flush: false);
      results.add(
        VaultBulkWriteResult(
          item.path,
          storageId,
          base64Encode(nonce),
          plainSize,
          cipherVer: kVaultCipherGcm,
        ),
      );
    } else {
      final iv = enc.IV.fromSecureRandom(16);
      final encrypted = cbcEncrypter!.encryptBytes(plain, iv: iv);
      outFile.writeAsBytesSync(encrypted.bytes, flush: false);
      results.add(
        VaultBulkWriteResult(
          item.path,
          storageId,
          iv.base64,
          plainSize,
          cipherVer: kVaultCipherCbc,
        ),
      );
    }
  }
  return results;
}

void _writeChunkedGcmFile(
  File outFile,
  Uint8List key,
  Uint8List plain,
  Uint8List aadPrefix,
) {
  final raf = outFile.openSync(mode: FileMode.write);
  try {
    raf.writeFromSync(_sbv2Magic);
    raf.writeByteSync(2);
    final chunkCount = plain.isEmpty
        ? 1
        : ((plain.length + kVaultGcmChunkPlainBytes - 1) ~/
            kVaultGcmChunkPlainBytes);
    final countBytes = ByteData(4)..setUint32(0, chunkCount, Endian.little);
    raf.writeFromSync(countBytes.buffer.asUint8List());

    final random = Random.secure();
    var offset = 0;
    for (var chunkIndex = 0; chunkIndex < chunkCount; chunkIndex++) {
      final end = plain.isEmpty
          ? 0
          : min(offset + kVaultGcmChunkPlainBytes, plain.length);
      final chunk = plain.isEmpty
          ? Uint8List(0)
          : Uint8List.sublistView(plain, offset, end);
      final nonce = Uint8List(kVaultGcmNonceBytes);
      for (var i = 0; i < nonce.length; i++) {
        nonce[i] = random.nextInt(256);
      }
      final aad = Uint8List(aadPrefix.length + 4);
      aad.setAll(0, aadPrefix);
      ByteData.sublistView(aad, aadPrefix.length)
          .setUint32(0, chunkIndex, Endian.little);
      final sealed = vaultAesGcmEncrypt(key, nonce, chunk, aad: aad);

      final plainLenBytes = ByteData(4)
        ..setUint32(0, chunk.length, Endian.little);
      final cipherLenBytes = ByteData(4)
        ..setUint32(0, sealed.length, Endian.little);
      raf.writeFromSync(plainLenBytes.buffer.asUint8List());
      raf.writeFromSync(nonce);
      raf.writeFromSync(cipherLenBytes.buffer.asUint8List());
      raf.writeFromSync(sealed);
      offset = end;
    }
  } finally {
    raf.closeSync();
  }
}

Uint8List vaultReadChunkedGcmFile(String path, Uint8List key, Uint8List aadPrefix) {
  final raf = File(path).openSync(mode: FileMode.read);
  try {
    final magic = raf.readSync(4);
    if (magic.length != 4 ||
        magic[0] != 0x53 ||
        magic[1] != 0x42 ||
        magic[2] != 0x56 ||
        magic[3] != 0x32) {
      throw StateError('Not a chunked GCM vault blob');
    }
    final ver = raf.readByteSync();
    if (ver != 2) throw StateError('Unsupported chunked GCM version: $ver');
    final countBytes = raf.readSync(4);
    final chunkCount = ByteData.sublistView(countBytes).getUint32(0, Endian.little);
    final out = BytesBuilder(copy: false);
    for (var chunkIndex = 0; chunkIndex < chunkCount; chunkIndex++) {
      final plainLen = ByteData.sublistView(raf.readSync(4)).getUint32(0, Endian.little);
      final nonce = raf.readSync(kVaultGcmNonceBytes);
      final cipherLen = ByteData.sublistView(raf.readSync(4)).getUint32(0, Endian.little);
      final sealed = raf.readSync(cipherLen);
      final aad = Uint8List(aadPrefix.length + 4);
      aad.setAll(0, aadPrefix);
      ByteData.sublistView(aad, aadPrefix.length)
          .setUint32(0, chunkIndex, Endian.little);
      final plain = vaultAesGcmDecrypt(key, nonce, sealed, aad: aad);
      if (plain.length != plainLen) {
        throw StateError('Plain length mismatch');
      }
      out.add(plain);
    }
    return out.toBytes();
  } finally {
    raf.closeSync();
  }
}

class VaultJoinDecryptArgs {
  VaultJoinDecryptArgs({
    required this.chunks,
    required this.applyZlib,
  });
  final List<TransferableTypedData> chunks;
  final bool applyZlib;
}

/// Join decrypted shards and optionally zlib-inflate — runs in a worker.
TransferableTypedData vaultIsolateJoinAndMaybeZlib(VaultJoinDecryptArgs args) {
  final builder = BytesBuilder(copy: false);
  for (final chunk in args.chunks) {
    builder.add(chunk.materialize().asUint8List());
  }
  var bytes = builder.toBytes();
  if (args.applyZlib) {
    bytes = vaultZlibDecodeBestEffort(bytes);
  }
  return TransferableTypedData.fromList([bytes]);
}

class VaultDecryptGcmArgs {
  VaultDecryptGcmArgs({
    required this.storagePath,
    required this.keyBytes,
    required this.nonceBase64,
    required this.cipherVer,
    required this.storageId,
    required this.applyZlib,
  });
  final String storagePath;
  final Uint8List keyBytes;
  final String nonceBase64;
  final int cipherVer;
  final String storageId;
  final bool applyZlib;
}

TransferableTypedData vaultIsolateDecryptGcm(VaultDecryptGcmArgs args) {
  late Uint8List plain;
  if (args.cipherVer == kVaultCipherGcmChunked) {
    plain = vaultReadChunkedGcmFile(
      args.storagePath,
      args.keyBytes,
      Uint8List.fromList(utf8.encode(args.storageId)),
    );
  } else {
    final nonce = base64Decode(args.nonceBase64);
    final sealed = File(args.storagePath).readAsBytesSync();
    plain = vaultAesGcmDecrypt(args.keyBytes, Uint8List.fromList(nonce), sealed);
  }
  if (args.applyZlib) {
    plain = vaultZlibDecodeBestEffort(plain);
  }
  return TransferableTypedData.fromList([plain]);
}

/// Minimal UUID v4 without importing package:uuid into isolate entry surface.
class UuidLike {
  const UuidLike();
  String v4() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String h(int b) => b.toRadixString(16).padLeft(2, '0');
    final s = bytes.map(h).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-'
        '${s.substring(16, 20)}-${s.substring(20)}';
  }
}

/// Assemble note binary from a prebuilt header and page blobs off the UI isolate.
Uint8List vaultIsolateAssembleBinary(Map<String, dynamic> args) {
  final header = args['header'] as Uint8List;
  final pages = (args['pages'] as List).cast<Uint8List>();
  final builder = BytesBuilder(copy: false);
  builder.add(header);
  for (final page in pages) {
    builder.add(page);
  }
  return builder.toBytes();
}
