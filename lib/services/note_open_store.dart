// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One inflated note body kept in the Kotlin heap. Dart copies only the
/// byte ranges it parses. Null on desktop and when the channel is missing.
class NoteBodySession {
  NoteBodySession({
    required this.id,
    required this.length,
    required this.sampleHash,
  });

  final int id;
  final int length;
  final int sampleHash;
  bool _closed = false;

  Future<Uint8List> slice(int start, int end) async {
    if (_closed) {
      throw StateError('Note body session $id is closed');
    }
    final raw = await NoteOpenStore.channel.invokeMethod<Uint8List>('slice', {
      'id': id,
      'start': start,
      'end': end,
    });
    if (raw == null) {
      throw StateError('Empty note slice $start..$end');
    }
    return raw;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await NoteOpenStore.channel.invokeMethod<void>('close', {'id': id});
    } catch (_) {}
  }
}

/// Android note-body store. File IO and zlib inflate run on a Kotlin
/// background thread. The inflated bytes stay native; Dart receives slices.
abstract final class NoteOpenStore {
  static const channel = MethodChannel('com.resendeghf.notes/note_open');

  static Future<NoteBodySession?> open(String path) async {
    if (kIsWeb || path.isEmpty) return null;
    if (!Platform.isAndroid) return null;
    try {
      final raw = await channel.invokeMapMethod<Object?, Object?>('open', {
        'path': path,
      });
      if (raw == null) return null;
      final id = raw['id'];
      final length = raw['length'];
      final sampleHash = raw['sampleHash'];
      if (id is! int || length is! int || sampleHash is! int) return null;
      if (length <= 0) return null;
      return NoteBodySession(id: id, length: length, sampleHash: sampleHash);
    } catch (_) {
      return null;
    }
  }
}
