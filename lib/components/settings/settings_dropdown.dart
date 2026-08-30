// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/settings/settings_icon.dart';
import 'package:saber/components/theming/adaptive_toggle_buttons.dart';
import 'package:saber/pages/home/settings.dart';
import 'package:stow/stow.dart';

class SettingsDropdown<T> extends StatefulWidget {
  const SettingsDropdown({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconBuilder,
    required this.pref,
    required this.options,
    this.afterChange,
  }) : assert(
         icon == null || iconBuilder == null,
         'Cannot set both icon and iconBuilder',
       );

  final String title;
  final String? subtitle;
  final Object? icon;
  final Object? Function(T)? iconBuilder;

  final Stow<dynamic, T, dynamic> pref;
  final List<ToggleButtonsOption<T>> options;
  final ValueChanged<T>? afterChange;

  int? indexOf(T value) {
    for (int i = 0; i < options.length; i++) {
      if (options[i].value == value) return i;
    }
    return null;
  }

  @override
  State<SettingsDropdown> createState() => _SettingsDropdownState<T>();
}

class _SettingsDropdownState<T> extends State<SettingsDropdown<T>> {
  @override
  void initState() {
    widget.pref.addListener(onChanged);
    super.initState();
  }

  void onChanged() {
    widget.afterChange?.call(widget.pref.value);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.indexOf(widget.pref.value) == null) {
      if (kDebugMode)
        throw Exception(
          'SettingsDropdown (${widget.pref.key}): Value ${widget.pref.value} is not in the list of values, set it to ${widget.options.first.value}?',
        );
      widget.pref.value = widget.options.first.value;
    }

    Object? icon = widget.icon;
    icon ??= widget.iconBuilder?.call(widget.pref.value);
    icon ??= Icons.settings;

    return MergeSemantics(
      child: ListTile(
        onLongPress: () {
          SettingsPage.showResetDialog(
            context: context,
            pref: widget.pref,
            prefTitle: widget.title,
          );
        },
        contentPadding: const .symmetric(vertical: 4, horizontal: 16),
        leading: AnimatedSwitcher(
          duration: const Duration(milliseconds: 100),
          child: settingsLeadingIcon(icon, key: ValueKey(icon)),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            fontSize: 18,
            fontStyle: widget.pref.value != widget.pref.defaultValue
                ? FontStyle.italic
                : null,
          ),
        ),
        subtitle: Text(
          widget.subtitle ?? '',
          style: const TextStyle(fontSize: 13),
        ),
        trailing: PopupMenuButton<T>(
          onSelected: (value) => widget.pref.value = value,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: widget.options
                .firstWhere((option) => option.value == widget.pref.value)
                .widget,
          ),
          itemBuilder: (context) => [
            for (final option in widget.options)
              PopupMenuItem(
                value: option.value,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.45,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: option.widget,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.pref.removeListener(onChanged);
    super.dispose();
  }
}
