// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui';

/// Ear-clip a closed authored outline into a triangle mesh.
///
/// Returns null when the ring is degenerate, too large for [Uint16] indices,
/// or not a simple polygon (self-intersecting returns). Callers must fall
/// back to `drawPath` in that case.
class OutlineTriangulator {
  OutlineTriangulator._();

  static const int maxVertices = 65532;

  static ({Float32List positions, Uint16List indices})? triangulate(
    List<Offset> ring,
  ) {
    final pts = _cleanRing(ring);
    final n = pts.length;
    if (n < 3 || n > maxVertices) return null;

    var area2 = 0.0;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      area2 += pts[j].dx * pts[i].dy - pts[i].dx * pts[j].dy;
    }
    if (area2.abs() < 1e-8) return null;
    if (area2 < 0) {
      // Clockwise → reverse so winding is CCW for ear tests.
      for (var i = 0, j = n - 1; i < j; i++, j--) {
        final tmp = pts[i];
        pts[i] = pts[j];
        pts[j] = tmp;
      }
    }

    final rest = List<int>.generate(n, (i) => i);
    final indices = Uint16List((n - 2) * 3);
    var out = 0;
    var guard = 0;
    final guardMax = n * n + 8;

    while (rest.length >= 3) {
      if (++guard > guardMax) return null;
      final m = rest.length;
      var clipped = false;
      for (var i = 0; i < m; i++) {
        final i0 = rest[(i - 1 + m) % m];
        final i1 = rest[i];
        final i2 = rest[(i + 1) % m];
        final a = pts[i0];
        final b = pts[i1];
        final c = pts[i2];
        if (!_isConvex(a, b, c)) continue;
        if (_triangleContainsAny(a, b, c, pts, rest, i0, i1, i2)) continue;
        indices[out++] = i0;
        indices[out++] = i1;
        indices[out++] = i2;
        rest.removeAt(i);
        clipped = true;
        break;
      }
      if (!clipped) return null;
    }

    final positions = Float32List(n * 2);
    for (var i = 0; i < n; i++) {
      positions[i * 2] = pts[i].dx;
      positions[i * 2 + 1] = pts[i].dy;
    }
    if (out != indices.length) {
      return (
        positions: positions,
        indices: Uint16List.sublistView(indices, 0, out),
      );
    }
    return (positions: positions, indices: indices);
  }

  static List<Offset> _cleanRing(List<Offset> ring) {
    if (ring.isEmpty) return const [];
    final out = <Offset>[];
    Offset? last;
    for (final p in ring) {
      if (!p.dx.isFinite || !p.dy.isFinite) continue;
      if (last != null &&
          (p.dx - last.dx).abs() < 1e-6 &&
          (p.dy - last.dy).abs() < 1e-6) {
        continue;
      }
      out.add(p);
      last = p;
    }
    if (out.length >= 2) {
      final a = out.first;
      final b = out.last;
      if ((a.dx - b.dx).abs() < 1e-6 && (a.dy - b.dy).abs() < 1e-6) {
        out.removeLast();
      }
    }
    return out;
  }

  static bool _isConvex(Offset a, Offset b, Offset c) {
    final cross = (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
    return cross > 1e-10;
  }

  static bool _triangleContainsAny(
    Offset a,
    Offset b,
    Offset c,
    List<Offset> pts,
    List<int> rest,
    int i0,
    int i1,
    int i2,
  ) {
    for (final idx in rest) {
      if (idx == i0 || idx == i1 || idx == i2) continue;
      if (_pointInTriangle(pts[idx], a, b, c)) return true;
    }
    return false;
  }

  static bool _pointInTriangle(Offset p, Offset a, Offset b, Offset c) {
    const eps = 1e-10;
    final c0 = (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);
    final c1 = (c.dx - b.dx) * (p.dy - b.dy) - (c.dy - b.dy) * (p.dx - b.dx);
    final c2 = (a.dx - c.dx) * (p.dy - c.dy) - (a.dy - c.dy) * (p.dx - c.dx);
    return c0 >= -eps && c1 >= -eps && c2 >= -eps;
  }
}

/// Concatenate solid stroke meshes into as few [Vertices] as [Uint16] allows.
List<Vertices> mergeStrokeMeshes(Iterable<(Float32List, Uint16List)> meshes) {
  final out = <Vertices>[];
  var pos = <double>[];
  var idx = <int>[];

  void flush() {
    if (idx.isEmpty) return;
    out.add(
      Vertices.raw(
        VertexMode.triangles,
        Float32List.fromList(pos),
        indices: Uint16List.fromList(idx),
      ),
    );
    pos = <double>[];
    idx = <int>[];
  }

  for (final mesh in meshes) {
    final p = mesh.$1;
    final i = mesh.$2;
    if (p.isEmpty || i.isEmpty) continue;
    final vCount = p.length ~/ 2;
    if (vCount == 0) continue;
    if (pos.length ~/ 2 + vCount > OutlineTriangulator.maxVertices) {
      flush();
    }
    final base = pos.length ~/ 2;
    pos.addAll(p);
    for (var k = 0; k < i.length; k++) {
      idx.add(i[k] + base);
    }
  }
  flush();
  return out;
}
