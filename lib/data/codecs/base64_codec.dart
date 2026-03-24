// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:stow_codecs/stow_codecs.dart';

class Base64StowCodec extends AbstractCodec<Uint8List, String> {
  const Base64StowCodec();

  @override
  String encode(Uint8List input) => base64.encode(input);

  @override
  Uint8List decode(String encoded) => base64.decode(encoded);
}
