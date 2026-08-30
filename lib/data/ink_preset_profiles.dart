// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';

class InkPresetProfile {
  InkPresetProfile({
    required this.id,
    required this.name,
    required this.toolbarColorSlotsCount,
    required List<int> toolbarColorSlotsArgb,
    required Map<String, List<int>> penFavoriteColorsByToolId,
  }) : toolbarColorSlotsArgb = List<int>.from(toolbarColorSlotsArgb),
       penFavoriteColorsByToolId = penFavoriteColorsByToolId.map(
         (k, v) => MapEntry(k, List<int>.from(v)),
       );

  final String id;
  final String name;
  final int toolbarColorSlotsCount;
  final List<int> toolbarColorSlotsArgb;
  final Map<String, List<int>> penFavoriteColorsByToolId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'n': name,
    'tsc': toolbarColorSlotsCount,
    'ts': toolbarColorSlotsArgb,
    'pf': penFavoriteColorsByToolId,
  };

  factory InkPresetProfile.fromJson(Map<String, dynamic> j) {
    final ts =
        (j['ts'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ??
        const <int>[];
    final pfRaw = j['pf'];
    final pf = <String, List<int>>{};
    if (pfRaw is Map) {
      for (final e in pfRaw.entries) {
        final key = e.key.toString();
        final list = e.value;
        if (list is List) {
          pf[key] = list.map((x) => (x as num).toInt()).toList();
        }
      }
    }
    return InkPresetProfile(
      id: j['id']?.toString() ?? 'unknown',
      name: j['n']?.toString() ?? 'Preset',
      toolbarColorSlotsCount: (j['tsc'] as num?)?.toInt() ?? 5,
      toolbarColorSlotsArgb: ts,
      penFavoriteColorsByToolId: pf,
    );
  }

  InkPresetProfile normalized(Stows stows) {
    const inkKeys = [
      ToolId.ballpointPen,
      ToolId.calligraphyPen,
      ToolId.fountainPen,
      ToolId.shapePen,
      ToolId.advancedPen,
      ToolId.advancedPencil,
    ];
    const specialKeys = [
      ToolId.highlighter,
      ToolId.laserPointer,
    ];
    const targetLen = 10;
    final favOut = <String, List<int>>{};
    final live = Map<String, List<int>>.from(stows.penFavoriteColors.value);
    final profileInk = penFavoriteColorsByToolId[ToolId.ballpointPen.id];
    List<int> padded(List<int> source) {
      final base = List<int>.from(source);
      while (base.length < targetLen) {
        base.add(0xFF000000);
      }
      return base.take(targetLen).toList();
    }

    for (final tid in inkKeys) {
      final key = tid.id;
      favOut[key] = padded(
        penFavoriteColorsByToolId[key] ??
            profileInk ??
            live[key] ??
            const [],
      );
    }
    for (final tid in specialKeys) {
      final key = tid.id;
      favOut[key] = padded(
        penFavoriteColorsByToolId[key] ?? live[key] ?? const [],
      );
    }

    final count = toolbarColorSlotsCount.clamp(3, 15);
    final slots = List<int>.from(toolbarColorSlotsArgb);
    const fb = <int>[
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
    while (slots.length < count) {
      slots.add(fb[slots.length % fb.length]);
    }
    while (slots.length > count) {
      slots.removeLast();
    }

    return InkPresetProfile(
      id: id,
      name: name,
      toolbarColorSlotsCount: count,
      toolbarColorSlotsArgb: slots,
      penFavoriteColorsByToolId: favOut,
    );
  }
}

abstract final class InkPresetCodec {
  static List<InkPresetProfile> decodeList(String raw) {
    if (raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => InkPresetProfile.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String encodeList(List<InkPresetProfile> list) =>
      jsonEncode(list.map((p) => p.toJson()).toList());
}

abstract final class InkPresetLibrary {
  static List<InkPresetProfile> ensureLoaded(Stows stows) {
    var list = InkPresetCodec.decodeList(stows.inkPresetLibraryJson.value);
    if (list.isEmpty) {
      list = migrateSeedFromPrefs(stows);
      stows.inkPresetLibraryJson.value = InkPresetCodec.encodeList(list);
      if (stows.activeInkPresetId.value.isEmpty ||
          !list.any((p) => p.id == stows.activeInkPresetId.value)) {
        stows.activeInkPresetId.value = list.first.id;
      }
    } else {
      final existingIds = list.map((p) => p.id).toSet();
      final missingBuiltIns = _curatedBuiltIns()
          .where((p) => !existingIds.contains(p.id))
          .toList();
      if (missingBuiltIns.isNotEmpty) {
        list = [...list, ...missingBuiltIns.map((p) => p.normalized(stows))];
        stows.inkPresetLibraryJson.value = InkPresetCodec.encodeList(list);
      }
    }
    return list;
  }

  static List<InkPresetProfile> migrateSeedFromPrefs(Stows stows) {
    final slots = stows.toolbarColorSlots.value
        .map((s) => int.tryParse(s) ?? 0xFF374151)
        .toList();
    final fav = <String, List<int>>{};
    for (final e in stows.penFavoriteColors.value.entries) {
      fav[e.key] = List<int>.from(e.value);
    }

    final studio = InkPresetProfile(
      id: 'studio_default',
      name: 'Studio default',
      toolbarColorSlotsCount: stows.toolbarColorSlotsCount.value,
      toolbarColorSlotsArgb: slots,
      penFavoriteColorsByToolId: fav,
    );

    final curated = _curatedBuiltIns();

    return [
      studio.normalized(stows),
      ...curated.map((p) => p.normalized(stows)),
    ];
  }

  static List<InkPresetProfile> _curatedBuiltIns() {
    return <InkPresetProfile>[
      InkPresetProfile(
        id: 'starry_night',
        name: 'Starry Night',
        toolbarColorSlotsCount: 10,
        toolbarColorSlotsArgb: [
          0xFF102A54,
          0xFF1E5099,
          0xFFEAD066,
          0xFFF4F1E8,
          0xFF243046,
          0xFF0B1F44,
          0xFF38BDF8,
          0xFFC084FC,
          0xFF64748B,
          0xFF0F172A,
        ],
        penFavoriteColorsByToolId: _penInkHiLaser(
          ink: [
            0xFF0B1F44,
            0xFF1D4E89,
            0xFFC9A227,
            0xFFE8E2D5,
            0xFF4B5563,
            0xFF312E81,
            0xFF14532D,
            0xFF7F1D1D,
            0xFF422006,
            0xFF0EA5E9,
          ],
          hi: [
            0xFFBFDBFE,
            0xFFFDE68A,
            0xFFA7F3D0,
            0xFFFBCFE8,
            0xFFE9D5FF,
            0xFFFDE047,
            0xFF93C5FD,
            0xFFFACC15,
            0xFF67E8F9,
            0xFFA5B4FC,
          ],
          laser: [
            0xFF2563EB,
            0xFFEAB308,
            0xFF38BDF8,
            0xFFF97316,
            0xFFA78BFA,
            0xFFFFFFFF,
            0xFF0F172A,
            0xFF22D3EE,
            0xFFF472B6,
            0xFF94A3B8,
          ],
        ),
      ),
      InkPresetProfile(
        id: 'sunflower_field',
        name: 'Sunflower Field',
        toolbarColorSlotsCount: 10,
        toolbarColorSlotsArgb: [
          0xFFEAB308,
          0xFFB45309,
          0xFF166534,
          0xFF1E293B,
          0xFFFEF9C3,
          0xFF92400E,
          0xFF365314,
          0xFF0F766E,
          0xFFFDE68A,
          0xFF422006,
        ],
        penFavoriteColorsByToolId: _penInkHiLaser(
          ink: [
            0xFFCA8A04,
            0xFF92400E,
            0xFF15803D,
            0xFF1E293B,
            0xFFFEF08A,
            0xFF78350F,
            0xFF422006,
            0xFF365314,
            0xFF0F766E,
            0xFF000000,
          ],
        ),
      ),
      InkPresetProfile(
        id: 'almond_bloom',
        name: 'Almond Blossom',
        toolbarColorSlotsCount: 10,
        toolbarColorSlotsArgb: [
          0xFFE8F4FC,
          0xFFB8D4EE,
          0xFFD94646,
          0xFF6B8F71,
          0xFF2F4F4F,
          0xFFF8FAFC,
          0xFF93C5FD,
          0xFFBE185D,
          0xFF0D9488,
          0xFF64748B,
        ],
        penFavoriteColorsByToolId: _penInkHiLaser(
          ink: [
            0xFFF8FAFC,
            0xFF93C5FD,
            0xFFB91C1C,
            0xFF4ADE80,
            0xFF334155,
            0xFF64748B,
            0xFFBE185D,
            0xFF0D9488,
            0xFF1E293B,
            0xFFC084FC,
          ],
        ),
      ),
      InkPresetProfile(
        id: 'kyoto_sumi',
        name: 'Kyoto Sumi',
        toolbarColorSlotsCount: 10,
        toolbarColorSlotsArgb: [
          0xFF1C1917,
          0xFF44403C,
          0xFF78716C,
          0xFFB45309,
          0xFFE7E5E4,
          0xFF0C0A09,
          0xFF991B1B,
          0xFF134E4A,
          0xFF312E81,
          0xFFF5F5F4,
        ],
        penFavoriteColorsByToolId: _penInkHiLaser(
          ink: [
            0xFF0C0A09,
            0xFF292524,
            0xFF57534E,
            0xFFA16207,
            0xFFE7E5E4,
            0xFF991B1B,
            0xFF134E4A,
            0xFF312E81,
            0xFF44403C,
            0xFFF5F5F4,
          ],
        ),
      ),
      InkPresetProfile(
        id: 'nordic_minimal',
        name: 'Nordic Minimal',
        toolbarColorSlotsCount: 10,
        toolbarColorSlotsArgb: [
          0xFFF8FAFC,
          0xFFCBD5E1,
          0xFF475569,
          0xFF0F172A,
          0xFF94A3B8,
          0xFFE2E8F0,
          0xFF334155,
          0xFF0369A1,
          0xFF15803D,
          0xFF78716C,
        ],
        penFavoriteColorsByToolId: _penInkHiLaser(
          ink: [
            0xFFFFFFFF,
            0xFFE2E8F0,
            0xFF64748B,
            0xFF0F172A,
            0xFF94A3B8,
            0xFF334155,
            0xFF78716C,
            0xFF0369A1,
            0xFF15803D,
            0xFF1E293B,
          ],
        ),
      ),
      InkPresetProfile(
        id: 'terracotta_workshop',
        name: 'Terracotta Workshop',
        toolbarColorSlotsCount: 10,
        toolbarColorSlotsArgb: [
          0xFFC2410C,
          0xFF9A3412,
          0xFF78350F,
          0xFF431407,
          0xFFFDE68A,
          0xFFEA580C,
          0xFF7C2D12,
          0xFF713F12,
          0xFF14532D,
          0xFF000000,
        ],
        penFavoriteColorsByToolId: _penInkHiLaser(
          ink: [
            0xFFEA580C,
            0xFFC2410C,
            0xFF92400E,
            0xFF431407,
            0xFFFEF08A,
            0xFF7C2D12,
            0xFF713F12,
            0xFF422006,
            0xFF14532D,
            0xFF000000,
          ],
        ),
      ),
      InkPresetProfile(
        id: 'coastal_haze',
        name: 'Coastal Haze',
        toolbarColorSlotsCount: 10,
        toolbarColorSlotsArgb: [
          0xFF64748B,
          0xFF94A3B8,
          0xFFBAE6FD,
          0xFF0EA5E9,
          0xFFF1F5F9,
          0xFF475569,
          0xFF0284C7,
          0xFF0D9488,
          0xFF312E81,
          0xFFE2E8F0,
        ],
        penFavoriteColorsByToolId: _penInkHiLaser(
          ink: [
            0xFF475569,
            0xFF64748B,
            0xFF7DD3FC,
            0xFF0284C7,
            0xFFF8FAFC,
            0xFF0369A1,
            0xFF0D9488,
            0xFF312E81,
            0xFF334155,
            0xFFE2E8F0,
          ],
        ),
      ),
      InkPresetProfile(
        id: 'bauhaus_primaries',
        name: 'Bauhaus Primaries',
        toolbarColorSlotsCount: 10,
        toolbarColorSlotsArgb: [
          0xFFE11D48,
          0xFF2563EB,
          0xFFEAB308,
          0xFF18181B,
          0xFFF4F4F5,
          0xFF16A34A,
          0xFF9333EA,
          0xFFEA580C,
          0xFF52525B,
          0xFFFFFFFF,
        ],
        penFavoriteColorsByToolId: _penInkHiLaser(
          ink: [
            0xFFDC2626,
            0xFF2563EB,
            0xFFEAB308,
            0xFF09090B,
            0xFFF4F4F5,
            0xFF16A34A,
            0xFF9333EA,
            0xFFEA580C,
            0xFF52525B,
            0xFFFFFFFF,
          ],
        ),
      ),
      InkPresetProfile(
        id: 'paper_mono',
        name: 'Paper Mono',
        toolbarColorSlotsCount: 10,
        toolbarColorSlotsArgb: [
          0xFF111827,
          0xFF374151,
          0xFF4B5563,
          0xFF6B7280,
          0xFF9CA3AF,
          0xFFD1D5DB,
          0xFFF3F4F6,
          0xFF1F2937,
          0xFF78716C,
          0xFF0F172A,
        ],
        penFavoriteColorsByToolId: _penInkHiLaser(
          ink: [
            0xFF111827,
            0xFF1F2937,
            0xFF374151,
            0xFF4B5563,
            0xFF6B7280,
            0xFF9CA3AF,
            0xFFD1D5DB,
            0xFFF3F4F6,
            0xFF78716C,
            0xFF0F172A,
          ],
        ),
      ),
      InkPresetProfile(
        id: 'quiet_sage',
        name: 'Quiet Sage',
        toolbarColorSlotsCount: 10,
        toolbarColorSlotsArgb: [
          0xFF1F2937,
          0xFF365314,
          0xFF4D7C0F,
          0xFF15803D,
          0xFF0F766E,
          0xFF64748B,
          0xFFA3A380,
          0xFFE7E5E4,
          0xFF7C2D12,
          0xFF134E4A,
        ],
        penFavoriteColorsByToolId: _penInkHiLaser(
          ink: [
            0xFF1F2937,
            0xFF365314,
            0xFF4D7C0F,
            0xFF15803D,
            0xFF0F766E,
            0xFF64748B,
            0xFFA3A380,
            0xFFE7E5E4,
            0xFF7C2D12,
            0xFF134E4A,
          ],
        ),
      ),
      InkPresetProfile(
        id: 'muted_rose',
        name: 'Muted Rose',
        toolbarColorSlotsCount: 10,
        toolbarColorSlotsArgb: [
          0xFF1F2937,
          0xFF881337,
          0xFFBE123C,
          0xFF9F1239,
          0xFF7C2D12,
          0xFF57534E,
          0xFFFBCFE8,
          0xFFF5E8E4,
          0xFF7E22CE,
          0xFF334155,
        ],
        penFavoriteColorsByToolId: _penInkHiLaser(
          ink: [
            0xFF1F2937,
            0xFF881337,
            0xFFBE123C,
            0xFF9F1239,
            0xFF7C2D12,
            0xFF57534E,
            0xFFFBCFE8,
            0xFFF5E8E4,
            0xFF7E22CE,
            0xFF334155,
          ],
        ),
      ),
      InkPresetProfile(
        id: 'slate_ocean',
        name: 'Slate Ocean',
        toolbarColorSlotsCount: 10,
        toolbarColorSlotsArgb: [
          0xFF0F172A,
          0xFF1E293B,
          0xFF334155,
          0xFF0369A1,
          0xFF0284C7,
          0xFF0F766E,
          0xFF475569,
          0xFF94A3B8,
          0xFFE0F2FE,
          0xFF312E81,
        ],
        penFavoriteColorsByToolId: _penInkHiLaser(
          ink: [
            0xFF0F172A,
            0xFF1E293B,
            0xFF334155,
            0xFF0369A1,
            0xFF0284C7,
            0xFF0F766E,
            0xFF475569,
            0xFF94A3B8,
            0xFFE0F2FE,
            0xFF312E81,
          ],
        ),
      ),
      InkPresetProfile(
        id: 'warm_graphite',
        name: 'Warm Graphite',
        toolbarColorSlotsCount: 10,
        toolbarColorSlotsArgb: [
          0xFF1C1917,
          0xFF292524,
          0xFF44403C,
          0xFF57534E,
          0xFF78716C,
          0xFFA16207,
          0xFF92400E,
          0xFF991B1B,
          0xFFE7E5E4,
          0xFF0F172A,
        ],
        penFavoriteColorsByToolId: _penInkHiLaser(
          ink: [
            0xFF1C1917,
            0xFF292524,
            0xFF44403C,
            0xFF57534E,
            0xFF78716C,
            0xFFA16207,
            0xFF92400E,
            0xFF991B1B,
            0xFFE7E5E4,
            0xFF0F172A,
          ],
        ),
      ),
    ];
  }

  static Map<String, List<int>> _penInkHiLaser({
    required List<int> ink,
    List<int>? hi,
    List<int>? laser,
  }) {
    const hiDef = <int>[
      0xFFFDE047,
      0xFF86EFAC,
      0xFF93C5FD,
      0xFFF9A8D4,
      0xFFFDBA74,
      0xFFA5B4FC,
      0xFF67E8F9,
      0xFFBEF264,
      0xFFFACC15,
      0xFF34D399,
    ];
    const laserDef = <int>[
      0xFFDC2626,
      0xFFEA580C,
      0xFFEAB308,
      0xFF22C55E,
      0xFF3B82F6,
      0xFFA855F7,
      0xFFEC4899,
      0xFFFFFFFF,
      0xFF0F172A,
      0xFF64748B,
    ];
    return <String, List<int>>{
      ToolId.ballpointPen.id: List<int>.from(ink),
      ToolId.calligraphyPen.id: List<int>.from(ink),
      ToolId.fountainPen.id: List<int>.from(ink),
      ToolId.shapePen.id: List<int>.from(ink),
      ToolId.advancedPen.id: List<int>.from(ink),
      ToolId.advancedPencil.id: List<int>.from(ink),
      ToolId.highlighter.id: List<int>.from(hi ?? hiDef),
      ToolId.laserPointer.id: List<int>.from(laser ?? laserDef),
    };
  }

  static void apply(Stows stows, InkPresetProfile raw) {
    final p = raw.normalized(stows);
    stows.toolbarColorSlotsCount.value = p.toolbarColorSlotsCount;
    stows.toolbarColorSlots.value = p.toolbarColorSlotsArgb
        .map((c) => c.toString())
        .toList();
    stows.penFavoriteColors.value = Map<String, List<int>>.from(
      p.penFavoriteColorsByToolId,
    );
    stows.activeInkPresetId.value = p.id;
    stows.normalizePenSizePresetList();
  }

  /// Applies the [stows.activeInkPresetId] palette into live prefs.
  /// Used as the template for new notes and to restore globals after a note.
  static bool applyActive(Stows stows) {
    final list = ensureLoaded(stows);
    if (list.isEmpty) return false;
    final id = stows.activeInkPresetId.value;
    InkPresetProfile profile = list.first;
    for (final p in list) {
      if (p.id == id) {
        profile = p;
        break;
      }
    }
    apply(stows, profile);
    return true;
  }

  static void upsert(Stows stows, InkPresetProfile profile) {
    final list = List<InkPresetProfile>.from(ensureLoaded(stows));
    final idx = list.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      list[idx] = profile.normalized(stows);
    } else {
      list.add(profile.normalized(stows));
    }
    stows.inkPresetLibraryJson.value = InkPresetCodec.encodeList(list);
  }

  static InkPresetProfile snapshotFromPrefs(
    Stows stows,
    String id,
    String name,
  ) {
    final fav = <String, List<int>>{};
    for (final e in stows.penFavoriteColors.value.entries) {
      fav[e.key] = List<int>.from(e.value);
    }
    return InkPresetProfile(
      id: id,
      name: name,
      toolbarColorSlotsCount: stows.toolbarColorSlotsCount.value,
      toolbarColorSlotsArgb: stows.toolbarColorSlots.value
          .map((s) => int.tryParse(s) ?? 0xFF000000)
          .toList(),
      penFavoriteColorsByToolId: fav,
    ).normalized(stows);
  }

  /// Removes a palette except the built-in studio default.
  static bool deleteById(Stows stows, String id) {
    if (id == 'studio_default') return false;
    final list = List<InkPresetProfile>.from(ensureLoaded(stows));
    final idx = list.indexWhere((p) => p.id == id);
    if (idx < 0) return false;
    list.removeAt(idx);
    stows.inkPresetLibraryJson.value = InkPresetCodec.encodeList(list);
    if (stows.activeInkPresetId.value == id) {
      final fallback = list.first;
      apply(stows, fallback);
    }
    return true;
  }
}
