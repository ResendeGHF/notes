// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/export.dart' as pc;

class SbaEncryption {
  SbaEncryption._();

  static const _magic = 'SABER_SBA_ENC\x01';
  static const _saltLen = 16;
  static const _ivLen = 16;
  static const _scryptN = 16384;
  static const _scryptR = 8;
  static const _scryptP = 1;
  static const _keyLen = 32;

  static bool isEncrypted(Uint8List bytes) {
    if (bytes.length < _magic.length) return false;
    final magicBytes = Uint8List.fromList(utf8.encode(_magic));
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != magicBytes[i]) return false;
    }
    return true;
  }

  static Uint8List encrypt(Uint8List plainBytes, String password) {
    final salt = enc.IV.fromSecureRandom(_saltLen);
    final iv = enc.IV.fromSecureRandom(_ivLen);
    final keyBytes = _deriveKey(password, salt.bytes);
    try {
      final encrypter = enc.Encrypter(
        enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc),
      );
      final encrypted = encrypter.encryptBytes(plainBytes, iv: iv);
      final out = BytesBuilder();
      out.add(utf8.encode(_magic));
      out.add(salt.bytes);
      out.add(iv.bytes);
      out.add(encrypted.bytes);
      return out.toBytes();
    } finally {
      for (var i = 0; i < keyBytes.length; i++) keyBytes[i] = 0;
    }
  }

  static Uint8List decrypt(Uint8List encryptedBytes, String password) {
    if (!isEncrypted(encryptedBytes)) {
      throw ArgumentError('Not an encrypted SBA file');
    }
    var offset = _magic.length;
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
      for (var i = 0; i < keyBytes.length; i++) keyBytes[i] = 0;
    }
  }

  static Uint8List _deriveKey(String password, Uint8List salt) {
    final passBytes = Uint8List.fromList(utf8.encode(password));
    try {
      final scrypt = pc.Scrypt()
        ..init(
          pc.ScryptParameters(_scryptN, _scryptR, _scryptP, _keyLen, salt),
        );
      return Uint8List.fromList(scrypt.process(passBytes));
    } finally {
      for (var i = 0; i < passBytes.length; i++) passBytes[i] = 0;
    }
  }
}
