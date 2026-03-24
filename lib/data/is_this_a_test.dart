// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/foundation.dart';

@pragma('vm:platform-const-if', !kDebugMode)
final isThisATest =
    kDebugMode && Platform.environment.containsKey('FLUTTER_TEST');
