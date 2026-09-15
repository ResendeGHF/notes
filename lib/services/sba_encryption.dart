// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:isolate' show Isolate;
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart' as pc;

/// Password-based encryption for `.sba` exports and backup archives.
///
/// Current format ([_gcmMagic] / `\x03`): AES-256-GCM after Scrypt.
/// Chunked file format ([_chunkedMagic] / `\x04`): same keying, 1 MiB GCM
/// blocks written to disk so large monolith backups never hold the whole
/// archive in RAM.
/// Still decrypts legacy CBC (`\x01`) and CBC+HMAC (`\x02`) payloads.
class SbaEncryption {
  SbaEncryption._();

  static const _legacyMagic = 'SABER_SBA_ENC\x01';
  static const _hmacMagic = 'SABER_SBA_ENC\x02';
  static const _gcmMagic = 'SABER_SBA_ENC\x03';
  static const _chunkedMagic = 'SABER_SBA_ENC\x04';

  static const _saltLen = 16;
  static const _ivLen = 16;
  static const _nonceLen = 12;
  static const _tagLen = 16;
  static const _macLen = 32;
  static const _scryptN = 16384;
  static const _scryptR = 8;
  static const _scryptP = 1;
  static const _keyLen = 32;
  static const _authKeyLen = 64;
  static const chunkSize = 1024 * 1024;

  /// Associated data binds ciphertext to the GCM container magic.
  static final Uint8List _gcmAad = Uint8List.fromList(utf8.encode(_gcmMagic));
  static final Uint8List _chunkedAad = Uint8List.fromList(
    utf8.encode(_chunkedMagic),
  );

  static bool isEncrypted(Uint8List bytes) {
    return _hasMagic(bytes, _chunkedMagic) ||
        _hasMagic(bytes, _gcmMagic) ||
        _hasMagic(bytes, _hmacMagic) ||
        _hasMagic(bytes, _legacyMagic);
  }

  static bool isChunkedEncryptedFile(String path) {
    final raf = File(path).openSync(mode: FileMode.read);
    try {
      final header = raf.readSync(_chunkedMagic.length);
      return _hasMagic(Uint8List.fromList(header), _chunkedMagic);
    } finally {
      raf.closeSync();
    }
  }

  /// Encrypts [plainBytes] with AES-256-GCM (current generation).
  static Uint8List encrypt(Uint8List plainBytes, String password) {
    final session = SbaEncryptSession(password);
    try {
      return session.encrypt(plainBytes);
    } finally {
      session.dispose();
    }
  }

  /// Runs [encrypt] on a background isolate when the plaintext is large enough
  /// that Scrypt + AES would hitch the UI on mid-range Android devices.
  static Future<Uint8List> encryptForExport(
    Uint8List plainBytes,
    String password,
  ) async {
    const threshold = 40 * 1024;
    if (plainBytes.length < threshold) {
      return encrypt(plainBytes, password);
    }
    return Isolate.run(() => encrypt(plainBytes, password));
  }

  static Uint8List decrypt(Uint8List encryptedBytes, String password) {
    if (!isEncrypted(encryptedBytes)) {
      throw ArgumentError('Not an encrypted SBA file');
    }
    if (_hasMagic(encryptedBytes, _chunkedMagic)) {
      throw ArgumentError(
        'Chunked SBA payload must be decrypted with decryptFile',
      );
    }
    if (_hasMagic(encryptedBytes, _gcmMagic)) {
      return _decryptGcm(encryptedBytes, password);
    }
    if (_hasMagic(encryptedBytes, _hmacMagic)) {
      return _decryptHmacCbc(encryptedBytes, password);
    }
    return _decryptLegacy(encryptedBytes, password);
  }

  /// Encrypts [sourcePath] to [destPath] in [chunkSize] AES-256-GCM blocks.
  /// Peak RAM is roughly one chunk, not the whole file.
  static void encryptFile(String sourcePath, String destPath, String password) {
    final session = SbaEncryptSession(password);
    try {
      session.encryptFile(sourcePath, destPath);
    } finally {
      session.dispose();
    }
  }

  /// Decrypts a `\x03` or `\x04` encrypted file to [destPath] without loading
  /// the full ciphertext into RAM for the chunked format.
  static void decryptFile(String sourcePath, String destPath, String password) {
    if (isChunkedEncryptedFile(sourcePath)) {
      _decryptChunkedFile(sourcePath, destPath, password);
      return;
    }
    final sealed = File(sourcePath).readAsBytesSync();
    final plain = decrypt(Uint8List.fromList(sealed), password);
    final dest = File(destPath);
    dest.parent.createSync(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final tmp = File('$destPath.tmp_$stamp');
    tmp.writeAsBytesSync(plain, flush: true);
    if (dest.existsSync()) dest.deleteSync();
    tmp.renameSync(destPath);
  }

  static void _decryptChunkedFile(
    String sourcePath,
    String destPath,
    String password,
  ) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final tmp = '$destPath.sba_dec_$stamp';
    final raf = File(sourcePath).openSync(mode: FileMode.read);
    final out = File(tmp).openSync(mode: FileMode.write);
    Uint8List? keyBytes;
    try {
      final magic = raf.readSync(_chunkedMagic.length);
      if (!_hasMagic(Uint8List.fromList(magic), _chunkedMagic)) {
        throw ArgumentError('Not a chunked SBA file');
      }
      final salt = Uint8List.fromList(raf.readSync(_saltLen));
      if (salt.length != _saltLen) {
        throw ArgumentError('Chunked SBA payload is truncated');
      }
      final chunkSizeBytes = raf.readSync(4);
      if (chunkSizeBytes.length != 4) {
        throw ArgumentError('Chunked SBA payload is truncated');
      }
      final declaredChunk = ByteData.sublistView(
        Uint8List.fromList(chunkSizeBytes),
      ).getUint32(0, Endian.little);
      if (declaredChunk == 0 || declaredChunk > 16 * 1024 * 1024) {
        throw ArgumentError('Invalid chunk size');
      }
      keyBytes = _deriveKey(password, salt, length: _keyLen);
      while (true) {
        final nonce = raf.readSync(_nonceLen);
        if (nonce.isEmpty) break;
        if (nonce.length != _nonceLen) {
          throw ArgumentError('Chunked SBA payload is truncated');
        }
        final lenBytes = raf.readSync(4);
        if (lenBytes.length != 4) {
          throw ArgumentError('Chunked SBA payload is truncated');
        }
        final sealedLen = ByteData.sublistView(
          Uint8List.fromList(lenBytes),
        ).getUint32(0, Endian.little);
        if (sealedLen < _tagLen || sealedLen > declaredChunk + _tagLen + 64) {
          throw ArgumentError('Invalid chunk length');
        }
        final sealed = raf.readSync(sealedLen);
        if (sealed.length != sealedLen) {
          throw ArgumentError('Chunked SBA payload is truncated');
        }
        final plain = _aesGcmDecrypt(
          keyBytes,
          Uint8List.fromList(nonce),
          Uint8List.fromList(sealed),
          aad: _chunkedAad,
        );
        out.writeFromSync(plain);
      }
      out.closeSync();
      final dest = File(destPath);
      dest.parent.createSync(recursive: true);
      if (dest.existsSync()) dest.deleteSync();
      File(tmp).renameSync(destPath);
    } catch (e) {
      try {
        out.closeSync();
      } catch (_) {}
      try {
        final f = File(tmp);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      if (e is ArgumentError) rethrow;
      throw ArgumentError('Decryption failed. Wrong password?');
    } finally {
      raf.closeSync();
      if (keyBytes != null) _zero(keyBytes);
    }
  }

  @visibleForTesting
  static Uint8List encryptLegacyForTest(Uint8List plainBytes, String password) {
    final salt = enc.IV.fromSecureRandom(_saltLen);
    final iv = enc.IV.fromSecureRandom(_ivLen);
    final keyBytes = _deriveKey(password, salt.bytes);
    try {
      final encrypter = enc.Encrypter(
        enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc),
      );
      final encrypted = encrypter.encryptBytes(plainBytes, iv: iv);
      final out = BytesBuilder()
        ..add(utf8.encode(_legacyMagic))
        ..add(salt.bytes)
        ..add(iv.bytes)
        ..add(encrypted.bytes);
      return out.toBytes();
    } finally {
      _zero(keyBytes);
    }
  }

  @visibleForTesting
  static Uint8List encryptHmacCbcForTest(
    Uint8List plainBytes,
    String password,
  ) {
    final salt = enc.IV.fromSecureRandom(_saltLen);
    final iv = enc.IV.fromSecureRandom(_ivLen);
    final keyMaterial = _deriveKey(password, salt.bytes, length: _authKeyLen);
    try {
      final encryptionKey = Uint8List.fromList(keyMaterial.sublist(0, _keyLen));
      final macKey = Uint8List.fromList(keyMaterial.sublist(_keyLen));
      final encrypter = enc.Encrypter(
        enc.AES(enc.Key(encryptionKey), mode: enc.AESMode.cbc),
      );
      final encrypted = encrypter.encryptBytes(plainBytes, iv: iv);
      final body = BytesBuilder()
        ..add(utf8.encode(_hmacMagic))
        ..add(salt.bytes)
        ..add(iv.bytes)
        ..add(encrypted.bytes);
      final bodyBytes = body.toBytes();
      final tag = _hmacSha256(macKey, bodyBytes);
      final out = BytesBuilder()
        ..add(bodyBytes)
        ..add(tag);
      return out.toBytes();
    } finally {
      _zero(keyMaterial);
    }
  }

  static Uint8List _decryptGcm(Uint8List encryptedBytes, String password) {
    final minLen = _gcmMagic.length + _saltLen + _nonceLen + _tagLen;
    if (encryptedBytes.length < minLen) {
      throw ArgumentError('Encrypted SBA payload is truncated');
    }
    var offset = _gcmMagic.length;
    final salt = encryptedBytes.sublist(offset, offset + _saltLen);
    offset += _saltLen;
    final nonce = encryptedBytes.sublist(offset, offset + _nonceLen);
    offset += _nonceLen;
    final sealed = encryptedBytes.sublist(offset);
    final keyBytes = _deriveKey(
      password,
      Uint8List.fromList(salt),
      length: _keyLen,
    );
    try {
      return _aesGcmDecrypt(
        keyBytes,
        Uint8List.fromList(nonce),
        Uint8List.fromList(sealed),
      );
    } catch (_) {
      throw ArgumentError('Decryption failed. Wrong password?');
    } finally {
      _zero(keyBytes);
    }
  }

  static Uint8List _decryptHmacCbc(Uint8List encryptedBytes, String password) {
    if (encryptedBytes.length <
        _hmacMagic.length + _saltLen + _ivLen + _macLen) {
      throw ArgumentError('Encrypted SBA payload is truncated');
    }
    var offset = _hmacMagic.length;
    final salt = encryptedBytes.sublist(offset, offset + _saltLen);
    offset += _saltLen;
    final iv = encryptedBytes.sublist(offset, offset + _ivLen);
    offset += _ivLen;
    final ciphertext = encryptedBytes.sublist(
      offset,
      encryptedBytes.length - _macLen,
    );
    final expectedTag = encryptedBytes.sublist(encryptedBytes.length - _macLen);
    final keyMaterial = _deriveKey(
      password,
      Uint8List.fromList(salt),
      length: _authKeyLen,
    );
    try {
      final encryptionKey = Uint8List.fromList(keyMaterial.sublist(0, _keyLen));
      final macKey = Uint8List.fromList(keyMaterial.sublist(_keyLen));
      final actualTag = _hmacSha256(
        macKey,
        encryptedBytes.sublist(0, encryptedBytes.length - _macLen),
      );
      if (!_constantTimeEquals(actualTag, expectedTag)) {
        throw ArgumentError('Authentication failed. Wrong password?');
      }
      final encrypter = enc.Encrypter(
        enc.AES(enc.Key(encryptionKey), mode: enc.AESMode.cbc),
      );
      final decrypted = encrypter.decryptBytes(
        enc.Encrypted(ciphertext),
        iv: enc.IV(iv),
      );
      return Uint8List.fromList(decrypted);
    } catch (e) {
      throw ArgumentError('Decryption failed. Wrong password?');
    } finally {
      _zero(keyMaterial);
    }
  }

  static Uint8List _decryptLegacy(Uint8List encryptedBytes, String password) {
    var offset = _legacyMagic.length;
    final salt = encryptedBytes.sublist(offset, offset + _saltLen);
    offset += _saltLen;
    final iv = encryptedBytes.sublist(offset, offset + _ivLen);
    offset += _ivLen;
    final ciphertext = encryptedBytes.sublist(offset);
    final keyBytes = _deriveKey(password, Uint8List.fromList(salt));
    try {
      final encrypter = enc.Encrypter(
        enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc),
      );
      final decrypted = encrypter.decryptBytes(
        enc.Encrypted(ciphertext),
        iv: enc.IV(iv),
      );
      return Uint8List.fromList(decrypted);
    } catch (e) {
      throw ArgumentError('Decryption failed. Wrong password?');
    } finally {
      _zero(keyBytes);
    }
  }

  static Uint8List _aesGcmEncrypt(
    Uint8List key,
    Uint8List nonce,
    Uint8List plain, {
    Uint8List? aad,
  }) {
    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(
        true,
        pc.AEADParameters(
          pc.KeyParameter(key),
          _tagLen * 8,
          nonce,
          aad ?? _gcmAad,
        ),
      );
    return cipher.process(plain);
  }

  static Uint8List _aesGcmDecrypt(
    Uint8List key,
    Uint8List nonce,
    Uint8List sealed, {
    Uint8List? aad,
  }) {
    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(
        false,
        pc.AEADParameters(
          pc.KeyParameter(key),
          _tagLen * 8,
          nonce,
          aad ?? _gcmAad,
        ),
      );
    return cipher.process(sealed);
  }

  static bool _hasMagic(Uint8List bytes, String magic) {
    if (bytes.length < magic.length) return false;
    final magicBytes = Uint8List.fromList(utf8.encode(magic));
    for (var i = 0; i < magicBytes.length; i++) {
      if (bytes[i] != magicBytes[i]) return false;
    }
    return true;
  }

  static Uint8List _deriveKey(
    String password,
    Uint8List salt, {
    int length = _keyLen,
  }) {
    final passBytes = Uint8List.fromList(utf8.encode(password));
    try {
      final scrypt = pc.Scrypt()
        ..init(pc.ScryptParameters(_scryptN, _scryptR, _scryptP, length, salt));
      return Uint8List.fromList(scrypt.process(passBytes));
    } finally {
      _zero(passBytes);
    }
  }

  static Uint8List _hmacSha256(Uint8List key, List<int> data) {
    final hmac = pc.HMac(pc.SHA256Digest(), 64)..init(pc.KeyParameter(key));
    return hmac.process(Uint8List.fromList(data));
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static void _zero(Uint8List bytes) {
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  }
}

/// One Scrypt derivation, many AES-256-GCM payloads.
///
/// Each [encrypt] still writes `SABER_SBA_ENC\x03` (salt + unique nonce +
/// ciphertext+tag) so [SbaEncryption.decrypt] can open every block. Reusing
/// the salt/key across a backup session avoids repeating Scrypt (N=16384)
/// per file — that was the incremental backup bottleneck.
class SbaEncryptSession {
  SbaEncryptSession(String password) {
    _salt = enc.IV.fromSecureRandom(SbaEncryption._saltLen).bytes;
    _key = SbaEncryption._deriveKey(
      password,
      _salt,
      length: SbaEncryption._keyLen,
    );
  }

  late final Uint8List _salt;
  late final Uint8List _key;
  bool _disposed = false;

  Uint8List encrypt(Uint8List plainBytes) {
    if (_disposed) {
      throw StateError('SbaEncryptSession used after dispose');
    }
    final nonce = enc.IV.fromSecureRandom(SbaEncryption._nonceLen);
    final sealed = SbaEncryption._aesGcmEncrypt(_key, nonce.bytes, plainBytes);
    return (BytesBuilder(copy: false)
          ..add(utf8.encode(SbaEncryption._gcmMagic))
          ..add(_salt)
          ..add(nonce.bytes)
          ..add(sealed))
        .toBytes();
  }

  /// Streams [sourcePath] into [destPath] as `SABER_SBA_ENC\x04` chunks.
  void encryptFile(String sourcePath, String destPath) {
    if (_disposed) {
      throw StateError('SbaEncryptSession used after dispose');
    }
    final dest = File(destPath);
    dest.parent.createSync(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final tmpPath = '$destPath.tmp_$stamp';
    final out = File(tmpPath).openSync(mode: FileMode.write);
    final raf = File(sourcePath).openSync(mode: FileMode.read);
    try {
      out.writeFromSync(utf8.encode(SbaEncryption._chunkedMagic));
      out.writeFromSync(_salt);
      final chunkSizeData = ByteData(4)
        ..setUint32(0, SbaEncryption.chunkSize, Endian.little);
      out.writeFromSync(chunkSizeData.buffer.asUint8List());
      while (true) {
        final chunk = raf.readSync(SbaEncryption.chunkSize);
        if (chunk.isEmpty) break;
        final plain = Uint8List.fromList(chunk);
        final nonce = enc.IV.fromSecureRandom(SbaEncryption._nonceLen);
        final sealed = SbaEncryption._aesGcmEncrypt(
          _key,
          nonce.bytes,
          plain,
          aad: SbaEncryption._chunkedAad,
        );
        out.writeFromSync(nonce.bytes);
        final lenData = ByteData(4)
          ..setUint32(0, sealed.length, Endian.little);
        out.writeFromSync(lenData.buffer.asUint8List());
        out.writeFromSync(sealed);
      }
      out.closeSync();
      if (dest.existsSync()) dest.deleteSync();
      File(tmpPath).renameSync(destPath);
    } catch (_) {
      try {
        out.closeSync();
      } catch (_) {}
      try {
        final f = File(tmpPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      rethrow;
    } finally {
      raf.closeSync();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    SbaEncryption._zero(_key);
  }
}

/// Password decrypt with a salt→key cache so incremental restore/verify does
/// not re-run Scrypt (N=16384) for every AES-GCM block from the same session.
class SbaDecryptSession {
  SbaDecryptSession(this._password);

  final String _password;
  final Map<String, Uint8List> _keysBySaltHex = {};
  bool _disposed = false;

  Uint8List decrypt(Uint8List encryptedBytes) {
    if (_disposed) {
      throw StateError('SbaDecryptSession used after dispose');
    }
    if (!SbaEncryption.isEncrypted(encryptedBytes)) {
      throw ArgumentError('Not an encrypted SBA file');
    }
    if (SbaEncryption._hasMagic(encryptedBytes, SbaEncryption._chunkedMagic)) {
      throw ArgumentError(
        'Chunked SBA payload must be decrypted with decryptFile',
      );
    }
    if (SbaEncryption._hasMagic(encryptedBytes, SbaEncryption._gcmMagic)) {
      return _decryptGcmCached(encryptedBytes);
    }
    // Legacy formats: rare in incremental archives; fall back to one-shot.
    return SbaEncryption.decrypt(encryptedBytes, _password);
  }

  Uint8List _decryptGcmCached(Uint8List encryptedBytes) {
    final minLen = SbaEncryption._gcmMagic.length +
        SbaEncryption._saltLen +
        SbaEncryption._nonceLen +
        SbaEncryption._tagLen;
    if (encryptedBytes.length < minLen) {
      throw ArgumentError('Encrypted SBA payload is truncated');
    }
    var offset = SbaEncryption._gcmMagic.length;
    final salt = encryptedBytes.sublist(
      offset,
      offset + SbaEncryption._saltLen,
    );
    offset += SbaEncryption._saltLen;
    final nonce = encryptedBytes.sublist(
      offset,
      offset + SbaEncryption._nonceLen,
    );
    offset += SbaEncryption._nonceLen;
    final sealed = encryptedBytes.sublist(offset);
    final saltKey = base64Encode(salt);
    var keyBytes = _keysBySaltHex[saltKey];
    if (keyBytes == null) {
      keyBytes = SbaEncryption._deriveKey(
        _password,
        Uint8List.fromList(salt),
        length: SbaEncryption._keyLen,
      );
      _keysBySaltHex[saltKey] = keyBytes;
    }
    try {
      return SbaEncryption._aesGcmDecrypt(
        keyBytes,
        Uint8List.fromList(nonce),
        Uint8List.fromList(sealed),
      );
    } catch (_) {
      throw ArgumentError('Decryption failed. Wrong password?');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final key in _keysBySaltHex.values) {
      SbaEncryption._zero(key);
    }
    _keysBySaltHex.clear();
  }
}
