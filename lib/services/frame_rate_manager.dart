import 'dart:async';
import 'dart:io';

import 'package:flutter_displaymode/flutter_displaymode.dart';

class FrameRateManager {
  static final FrameRateManager instance = FrameRateManager._();
  FrameRateManager._();

  Timer? _idleTimer;
  bool _isHighRefreshRate = false;

  Future<void> init() async {
    if (!Platform.isAndroid) return;
    await _setToLowRefreshRate();
  }

  void notifyInteraction() {
    if (!Platform.isAndroid) return;

    if (!_isHighRefreshRate) {
      _setToHighRefreshRate();
    }

    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 1), () {
      _setToLowRefreshRate();
    });
  }

  Future<void> _setToHighRefreshRate() async {
    try {
      _isHighRefreshRate = true;
      final modes = await FlutterDisplayMode.supported;
      final active = await FlutterDisplayMode.active;

      // Busca 90Hz+ mantendo a resolução atual para evitar "piscar" a tela
      final highMode = modes.where((m) => 
        m.refreshRate >= 89.0 && 
        m.width == active.width && 
        m.height == active.height
      ).toList()..sort((a, b) => b.refreshRate.compareTo(a.refreshRate));

      if (highMode.isNotEmpty) {
        await FlutterDisplayMode.setPreferredMode(highMode.first);
      }
    } catch (_) {}
  }

  Future<void> _setToLowRefreshRate() async {
    try {
      _isHighRefreshRate = false;
      final modes = await FlutterDisplayMode.supported;
      final active = await FlutterDisplayMode.active;

      // Retorna para o modo de ~60Hz
      final lowMode = modes.where((m) => 
        m.refreshRate >= 59.0 && 
        m.refreshRate <= 61.0 &&
        m.width == active.width && 
        m.height == active.height
      ).toList();

      if (lowMode.isNotEmpty) {
        await FlutterDisplayMode.setPreferredMode(lowMode.first);
      } else {
        await FlutterDisplayMode.setLowRefreshRate();
      }
    } catch (_) {}
  }
}