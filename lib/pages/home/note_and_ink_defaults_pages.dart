// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/home/home_toolbar_chrome.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/note_tool_settings.dart';
import 'package:saber/data/ink_preset_profiles.dart';
import 'package:saber/data/pen_stroke_preset_scaling.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor_page_settings_body.dart';

/// Settings route — global defaults for **new notes** (full-screen like editor Page Settings).
class GlobalNoteDefaultsSettingsPage extends StatefulWidget {
  const GlobalNoteDefaultsSettingsPage({super.key});

  @override
  State<GlobalNoteDefaultsSettingsPage> createState() =>
      _GlobalNoteDefaultsSettingsPageState();
}

class _GlobalNoteDefaultsSettingsPageState
    extends State<GlobalNoteDefaultsSettingsPage> {
  late EditorCoreInfo _carrier;

  @override
  void initState() {
    super.initState();
    _carrier = EditorCoreInfo.globalDefaultsPreviewCarrier();
  }

  void _refreshCarrier() {
    setState(() {
      _carrier = EditorCoreInfo.globalDefaultsPreviewCarrier();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: homeAppBarBackgroundColor(context),
      appBar: AppBar(
        backgroundColor: homeAppBarBackgroundColor(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.settings.noteInkDefaults.noteDefaultsTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.35,
              ),
            ),
            Text(
              t.settings.noteInkDefaults.noteDefaultsSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: EditorPageSettingsBody(
          coreInfo: _carrier,
          currentPageIndex: 0,
          configureGlobalNoteDefaults: true,
          onSetPattern: (pattern) {
            stows.lastBackgroundPattern.value = pattern;
            _refreshCarrier();
          },
          onSetLineHeight: (height) {
            stows.lastLineHeight.value = height;
            _refreshCarrier();
          },
          onSetLineThickness: (thick) {
            stows.lastLineThickness.value = thick.round();
            _refreshCarrier();
          },
          onSetColor: (color) {
            stows.defaultPageColor.value = color.toARGB32();
            _refreshCarrier();
          },
          onSetLineColor: (color) {
            stows.defaultLineColor.value = color.toARGB32();
            _refreshCarrier();
          },
          onSetPageOrientation: (orientation) {
            stows.defaultNotePageOrientationIndex.value = orientation.index;
            _refreshCarrier();
          },
          onToggleGlobalBackgroundInversion: (_) {},
          onSetMargins: (left, right, top, bottom) {
            stows.defaultMarginLeft.value = left;
            stows.defaultMarginRight.value = right;
            stows.defaultMarginTop.value = top;
            stows.defaultMarginBottom.value = bottom;
            _refreshCarrier();
          },
          onSetBorderColor: (color) {
            stows.defaultMarginColor.value = color.toARGB32();
            _refreshCarrier();
          },
        ),
      ),
    );
  }
}

/// Settings route — toolbar colors, pen stroke-width presets (pen-modal scale), and palettes.
///
/// Edits here always update the global ink preset library. When opened from an
/// editor session, pass [noteSessionBackup] so canceling without edits restores
/// that note's local toolbar/pen prefs (toolbar color-bar edits never upsert
/// presets; only this screen does).
class InkDefaultsSettingsPage extends StatefulWidget {
  const InkDefaultsSettingsPage({
    super.key,
    this.onChanged,
    this.noteSessionBackup,
  });

  final VoidCallback? onChanged;

  /// Snapshot of the open note's tool prefs before this screen applied the
  /// active preset for editing. Restored on back if the user made no changes.
  final NoteToolSettings? noteSessionBackup;

  @override
  State<InkDefaultsSettingsPage> createState() =>
      _InkDefaultsSettingsPageState();
}

class _InkDefaultsSettingsPageState extends State<InkDefaultsSettingsPage> {
  var _dirty = false;

  @override
  void initState() {
    super.initState();
    // Always edit the active preset — never the live note-polluted prefs.
    InkPresetLibrary.applyActive(stows);
  }

  void _onChanged() {
    _dirty = true;
    widget.onChanged?.call();
  }

  void _restoreNoteIfNeeded() {
    final backup = widget.noteSessionBackup;
    if (!_dirty && backup != null) {
      applyNoteToolSettings(backup);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _restoreNoteIfNeeded();
      },
      child: Scaffold(
        backgroundColor: homeAppBarBackgroundColor(context),
        appBar: AppBar(
          backgroundColor: homeAppBarBackgroundColor(context),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.settings.noteInkDefaults.inkDefaultsTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.35,
                ),
              ),
              Text(
                t.settings.noteInkDefaults.inkDefaultsSubtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        body: SafeArea(child: InkDefaultsSettingsBody(onChanged: _onChanged)),
      ),
    );
  }
}

class InkDefaultsSettingsBody extends StatefulWidget {
  const InkDefaultsSettingsBody({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(22, 18, 22, 36),
    this.onChanged,
  });

  final EdgeInsetsGeometry padding;
  final VoidCallback? onChanged;

  @override
  State<InkDefaultsSettingsBody> createState() =>
      _InkDefaultsSettingsBodyState();
}

class _InkDefaultsSettingsBodyState extends State<InkDefaultsSettingsBody> {
  bool _pendingInkPresetMigrationTick = false;

  static final List<Listenable> _inkDefaultListenables = [
    stows.activeInkPresetId,
    stows.toolbarColorSlotsCount,
    stows.toolbarColorSlots,
    stows.penSizePresetCount,
    stows.penSizePresetSizes,
    stows.inkPresetLibraryJson,
  ];

  static const _fallbackToolbarArgb = [
    0xFF374151,
    0xFF1E3A5F,
    0xFF1F2937,
    0xFF134E4A,
    0xFF15803D,
    0xFF7F1D1D,
    0xFF422006,
    0xFF312E81,
    0xFF607D8B,
    0xFF0F172A,
  ];

  @override
  void initState() {
    super.initState();
    InkPresetLibrary.ensureLoaded(stows);
    stows.normalizePenSizePresetList();
  }

  late final Listenable _inkRebuild = Listenable.merge(_inkDefaultListenables);

  void _notifyChanged() {
    widget.onChanged?.call();
  }

  void _normalizeToolbarSlotsLength() {
    final count = stows.toolbarColorSlotsCount.value.clamp(3, 15);
    if (count != stows.toolbarColorSlotsCount.value) {
      stows.toolbarColorSlotsCount.value = count;
    }
    final slots = List<String>.from(stows.toolbarColorSlots.value);
    while (slots.length < count) {
      final argb =
          _fallbackToolbarArgb[slots.length % _fallbackToolbarArgb.length];
      slots.add(argb.toString());
    }
    while (slots.length > count) {
      slots.removeLast();
    }
    stows.toolbarColorSlots.value = slots;
  }

  void _snapshotActivePalette(List<InkPresetProfile> presets) {
    InkPresetLibrary.upsert(
      stows,
      InkPresetLibrary.snapshotFromPrefs(
        stows,
        stows.activeInkPresetId.value,
        _presetNameForId(presets, stows.activeInkPresetId.value),
      ),
    );
  }

  String _presetNameForId(List<InkPresetProfile> list, String id) {
    for (final p in list) {
      if (p.id == id) return p.name;
    }
    return list.isEmpty ? 'Palette' : list.first.name;
  }

  Future<void> _pickToolbarSlotColor(BuildContext context, int index) async {
    final slots = List<String>.from(stows.toolbarColorSlots.value);
    if (index < 0 || index >= slots.length) return;
    final current = Color(int.tryParse(slots[index]) ?? 0xFF374151);
    final picked = await showColorPickerDialog(
      context,
      current,
      title: Text(
        t.settings.noteInkDefaults.toolbarSlotColor(index: index + 1),
      ),
      pickersEnabled: const {
        ColorPickerType.wheel: true,
        ColorPickerType.primary: true,
        ColorPickerType.accent: false,
      },
      enableShadesSelection: false,
      showColorCode: true,
      colorCodeHasColor: true,
    );
    if (picked == current) return;
    slots[index] = picked.toARGB32().toString();
    stows.toolbarColorSlots.value = slots;
    _snapshotActivePalette(InkPresetLibrary.ensureLoaded(stows));
    _notifyChanged();
  }

  Future<void> _promptNameThen({
    required String title,
    required String hint,
    required void Function(String name) onOk,
  }) async {
    final ctrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AdaptiveAlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(labelText: hint),
            onSubmitted: (_) => Navigator.pop(ctx, true),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t.common.done),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final name = ctrl.text.trim();
      if (name.isEmpty) return;
      onOk(name);
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _saveNewPalette() async {
    await _promptNameThen(
      title: t.settings.noteInkDefaults.savePaletteAsNewTitle,
      hint: t.settings.noteInkDefaults.paletteNameHint,
      onOk: (name) {
        final id =
            'custom_${DateTime.now().millisecondsSinceEpoch}_${name.hashCode & 0x7fffffff}';
        final snap = InkPresetLibrary.snapshotFromPrefs(stows, id, name);
        InkPresetLibrary.upsert(stows, snap);
        InkPresetLibrary.apply(stows, snap);
        _normalizeToolbarSlotsLength();
        _snapshotActivePalette(InkPresetLibrary.ensureLoaded(stows));
        _notifyChanged();
        setState(() {});
      },
    );
  }

  Future<void> _updateCurrentPaletteName() async {
    await _promptNameThen(
      title: t.settings.noteInkDefaults.renamePaletteTitle,
      hint: t.settings.noteInkDefaults.paletteNameHint,
      onOk: (name) {
        final snap = InkPresetLibrary.snapshotFromPrefs(
          stows,
          stows.activeInkPresetId.value,
          name,
        );
        InkPresetLibrary.upsert(stows, snap);
        _notifyChanged();
        setState(() {});
      },
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 10, left: 2),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.35,
      ),
    ),
  );

  Widget _softCard(BuildContext context, {required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .2)),
        color: scheme.surfaceContainerHighest.withValues(alpha: .22),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: .035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }

  Widget _palettePreviewOrbs(BuildContext context, List<int> argbBytes) {
    final scheme = Theme.of(context).colorScheme;
    final colors = argbBytes
        .take(10)
        .map((a) => Color(a))
        .toList(growable: false);
    if (colors.isEmpty) return const SizedBox(height: 64);
    return SizedBox(
      height: 66,
      child: Center(
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            for (final color in colors)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    width: 1.5,
                    color: scheme.surface.withValues(alpha: .9),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: .10),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const SizedBox(width: 22, height: 22),
              ),
          ],
        ),
      ),
    );
  }

  Widget _minimalIntPicker({
    required BuildContext context,
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    Widget chip(String n, bool sel) => Material(
      color: sel
          ? scheme.primary.withValues(alpha: .2)
          : scheme.surface.withValues(alpha: .2),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => onChanged(int.parse(n)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            n,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
    final items = [for (var i = min; i <= max; i++) i];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final i in items) chip('$i', i == value)],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: _inkRebuild,
      builder: (context, _) {
        // Decode only here: [InkPresetLibrary.ensureLoaded] writes to stows
        // merged into [_inkRebuild], so calling it synchronously inside this
        // builder can recurse (freeze / ANR) when palettes are seeded.
        final presets = InkPresetCodec.decodeList(
          stows.inkPresetLibraryJson.value,
        );
        if (presets.isEmpty) {
          if (!_pendingInkPresetMigrationTick) {
            _pendingInkPresetMigrationTick = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _pendingInkPresetMigrationTick = false;
              if (!mounted) return;
              InkPresetLibrary.ensureLoaded(stows);
            });
          }
          return ListView(
            padding: widget.padding,
            children: const [
              SizedBox(height: 120),
              Center(child: CircularProgressIndicator.adaptive()),
            ],
          );
        }

        final activeIdOk = presets.any(
          (p) => p.id == stows.activeInkPresetId.value,
        );

        final listChildren = <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primaryContainer.withValues(alpha: .36),
                  theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: .22,
                  ),
                ],
              ),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: .18),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: .12),
                      shape: BoxShape.circle,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.brush_outlined),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      t.settings.noteInkDefaults.inkDefaultsSubtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle(context, t.settings.noteInkDefaults.activePalette),
          const SizedBox(height: 4),
          _softCard(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 154,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: presets.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (ctx, idx) {
                      final p = presets[idx];
                      final selected = activeIdOk
                          ? stows.activeInkPresetId.value == p.id
                          : idx == 0;
                      final scheme = Theme.of(ctx).colorScheme;
                      return GestureDetector(
                        onTap: () {
                          InkPresetLibrary.apply(stows, p);
                          _normalizeToolbarSlotsLength();
                          _notifyChanged();
                          setState(() {});
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 148,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              width: selected ? 2 : 1,
                              color: selected
                                  ? scheme.primary.withValues(alpha: .75)
                                  : scheme.outlineVariant.withValues(
                                      alpha: .32,
                                    ),
                            ),
                            color: selected
                                ? scheme.primaryContainer.withValues(alpha: .22)
                                : scheme.surface.withValues(alpha: .64),
                            boxShadow: [
                              BoxShadow(
                                color: scheme.shadow.withValues(
                                  alpha: selected ? .10 : .045,
                                ),
                                blurRadius: selected ? 24 : 14,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    color: scheme.surfaceContainerHighest
                                        .withValues(alpha: .35),
                                  ),
                                  child: _palettePreviewOrbs(
                                    ctx,
                                    p.toolbarColorSlotsArgb,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                p.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saveNewPalette,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(
                          t.settings.noteInkDefaults.savePaletteAsNewShort,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      tooltip: t.settings.noteInkDefaults.renamePalette,
                      onPressed: _updateCurrentPaletteName,
                      icon: const Icon(Icons.edit_outlined, size: 20),
                    ),
                    if (stows.activeInkPresetId.value != 'studio_default')
                      IconButton(
                        tooltip: t.common.delete,
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AdaptiveAlertDialog(
                              title: Text(t.common.delete),
                              content: Text(
                                t.settings.noteInkDefaults.deletePaletteConfirm,
                              ),
                              actions: [
                                CupertinoDialogAction(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text(
                                    MaterialLocalizations.of(
                                      context,
                                    ).cancelButtonLabel,
                                  ),
                                ),
                                CupertinoDialogAction(
                                  isDestructiveAction: true,
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text(t.common.delete),
                                ),
                              ],
                            ),
                          );
                          if (ok ?? false) {
                            if (InkPresetLibrary.deleteById(
                              stows,
                              stows.activeInkPresetId.value,
                            )) {
                              _normalizeToolbarSlotsLength();
                              _notifyChanged();
                              setState(() {});
                            }
                          }
                        },
                        icon: Icon(
                          Icons.delete_outline,
                          color: theme.colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _sectionTitle(context, t.settings.prefLabels.toolbarColorSlotsCount),
          const SizedBox(height: 10),
          _softCard(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _minimalIntPicker(
                  context: context,
                  label: t.settings.prefDescriptions.toolbarColorSlotsCount,
                  value: stows.toolbarColorSlotsCount.value.clamp(3, 15),
                  min: 3,
                  max: 15,
                  onChanged: (v) {
                    stows.toolbarColorSlotsCount.value = v;
                    _normalizeToolbarSlotsLength();
                    _snapshotActivePalette(presets);
                    _notifyChanged();
                  },
                ),
                const Divider(height: 34),
                Text(
                  t.settings.noteInkDefaults.toolbarSlotsHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  alignment: WrapAlignment.start,
                  children: [
                    for (
                      var i = 0;
                      i < stows.toolbarColorSlotsCount.value.clamp(3, 15);
                      i++
                    )
                      GestureDetector(
                        onTap: () => _pickToolbarSlotColor(context, i),
                        child: Tooltip(
                          message: t.settings.noteInkDefaults.toolbarSlotColor(
                            index: i + 1,
                          ),
                          child: SizedBox(
                            width: 54,
                            height: 54,
                            child: Material(
                              color: Color(
                                int.tryParse(
                                      i < stows.toolbarColorSlots.value.length
                                          ? stows.toolbarColorSlots.value[i]
                                          : '0xff000000',
                                    ) ??
                                    0xff000000,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                                side: BorderSide(
                                  color: theme.colorScheme.outlineVariant
                                      .withValues(alpha: .4),
                                ),
                              ),
                              elevation: 1.5,
                              shadowColor: theme.colorScheme.shadow.withValues(
                                alpha: .16,
                              ),
                              clipBehavior: Clip.antiAlias,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _sectionTitle(context, t.settings.prefLabels.penSizePresetCount),
          const SizedBox(height: 10),
          _softCard(
            context,
            child: Builder(
              builder: (innerCtx) {
                final count = stows.penSizePresetCount.value.clamp(3, 7);

                Widget strokeSlidersInner() => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < count; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${t.settings.prefLabels.penSizePresetSlot} ${i + 1}',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  PenStrokePresetScaling.formatModalStrokeLabel(
                                    PenStrokePresetScaling.parseStored(
                                      i < stows.penSizePresetSizes.value.length
                                          ? stows.penSizePresetSizes.value[i]
                                          : '2',
                                    ),
                                  ),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              value: PenStrokePresetScaling.parseStored(
                                i < stows.penSizePresetSizes.value.length
                                    ? stows.penSizePresetSizes.value[i]
                                    : '2',
                              ),
                              min: PenStrokePresetScaling.internalMin,
                              max: PenStrokePresetScaling.internalMax,
                              divisions: PenStrokePresetScaling.sliderDivisions,
                              label:
                                  PenStrokePresetScaling.formatModalStrokeLabel(
                                    PenStrokePresetScaling.parseStored(
                                      i < stows.penSizePresetSizes.value.length
                                          ? stows.penSizePresetSizes.value[i]
                                          : '2',
                                    ),
                                  ),
                              onChanged: (nv) {
                                final next = List<String>.from(
                                  stows.penSizePresetSizes.value,
                                );
                                if (i >= next.length) return;
                                next[i] = PenStrokePresetScaling.snapInternal(
                                  nv,
                                ).toString();
                                stows.penSizePresetSizes.value = next;
                                _notifyChanged();
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _minimalIntPicker(
                      context: innerCtx,
                      label: t.settings.prefDescriptions.penSizePresetCount,
                      value: count,
                      min: 3,
                      max: 7,
                      onChanged: (v) {
                        stows.penSizePresetCount.value = v;
                        stows.normalizePenSizePresetList();
                        _notifyChanged();
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.editor.penSizePresets.sameAsPenSlider,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    strokeSlidersInner(),
                  ],
                );
              },
            ),
          ),
        ];

        return ListView(padding: widget.padding, children: listChildren);
      },
    );
  }
}
