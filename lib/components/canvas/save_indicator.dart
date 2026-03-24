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
      icon: ValueListenableBuilder(
        valueListenable: savingState,
        builder: (context, state, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.arrow_back),

              if (state == SavingState.waitingToSave)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _onPressed(BuildContext context) {
    switch (savingState.value) {
      case SavingState.waitingToSave:
        triggerSave();
        return;
      case SavingState.saving:
        _back(context);
        return;
      case SavingState.saved:
        _back(context);
        return;
    }
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
