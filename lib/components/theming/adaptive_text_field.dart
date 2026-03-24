// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

class AdaptiveTextField extends StatefulWidget {
  const AdaptiveTextField({
    super.key,
    this.controller,
    this.autofillHints,
    this.placeholder,
    this.prefixIcon,
    this.isPassword = false,
    this.keyboardType,
    this.textInputAction,
    required this.focusOrder,
    this.validator,
  });

  final TextEditingController? controller;
  final Iterable<String>? autofillHints;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final NumericFocusOrder focusOrder;
  final String? placeholder;
  final Widget? prefixIcon;
  final bool isPassword;
  final String? Function(String?)? validator;

  @override
  State<StatefulWidget> createState() => _AdaptiveTextFieldState();
}

class _AdaptiveTextFieldState extends State<AdaptiveTextField> {
  var obscureText = false;
  Widget? get suffixIcon {
    if (!widget.isPassword) return null;
    return IconButton(
      icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility),
      iconSize: 18,
      onPressed: () {
        setState(() {
          obscureText = !obscureText;
        });
      },
    );
  }

  @override
  void initState() {
    obscureText = widget.isPassword;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    TextInputType? keyboardType = widget.keyboardType;
    if (widget.isPassword) {
      if (obscureText) {
        keyboardType = null;
      } else {
        keyboardType = TextInputType.visiblePassword;
      }
    }

    return FocusTraversalOrder(
      order: widget.focusOrder,
      child: TextFormField(
        controller: widget.controller,
        autofillHints: widget.autofillHints,
        keyboardType: keyboardType,
        textInputAction: widget.textInputAction,
        obscureText: obscureText,
        validator: widget.validator,
        decoration: InputDecoration(
          labelText: widget.placeholder,
          labelStyle: TextStyle(
            color: colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          prefixIcon: widget.prefixIcon,
          suffixIcon: suffixIcon != null
              ? FocusTraversalOrder(
                  order: NumericFocusOrder(widget.focusOrder.order + 100),
                  child: suffixIcon!,
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          border: OutlineInputBorder(
            borderSide: BorderSide(
              color: colorScheme.onSurface.withValues(alpha: 0.12),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
