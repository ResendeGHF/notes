// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

class SaveIndicator extends StatelessWidget {
  const SaveIndicator({
    super.key,
    required this.savingState,
    required this.triggerSave,
    this.onBackOverride,
  });

  final ValueNotifier<SavingState> savingState;
  final VoidCallback triggerSave;

  final VoidCallback? onBackOverride;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: () => _onPressed(context),
      icon: const Icon(Icons.arrow_back),
    );
  }

  void _onPressed(BuildContext context) {
    if (savingState.value == SavingState.waitingToSave) triggerSave();
    _back(context);
  }

  void _back(BuildContext context) {
    if (onBackOverride != null) {
      onBackOverride!();
    } else {
      Navigator.of(context).pop();
    }
  }
}

enum SavingState { waitingToSave, saving, saved }
