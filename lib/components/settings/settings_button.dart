// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

class SettingsButton extends StatelessWidget {
  const SettingsButton({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.onPressed,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: ListTile(
        contentPadding: const .symmetric(vertical: 4, horizontal: 16),
        leading: AnimatedSwitcher(
          duration: const Duration(milliseconds: 100),
          child: Icon(icon, key: ValueKey(icon)),
        ),
        title: Text(title, style: const TextStyle(fontSize: 18)),
        subtitle: Text(subtitle ?? '', style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}
