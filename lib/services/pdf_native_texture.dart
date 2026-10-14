// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:saber/components/canvas/invert_widget.dart';
import 'package:saber/services/pdf_viewport.dart';
import 'package:saber/services/vault_adapter.dart';
import 'package:logging/logging.dart';

/// Hardware texture rendering (zero-copy path).
///
/// Standard pdfrx rendering copies `width*height*4` bytes per page across the
/// FFI boundary (native malloc -> Dart `Uint8List` -> `ui.Image` -> GPU).
/// Native note apps skip all of that: the OS PDF stack (`PdfRenderer` on
/// Android, PDFKit on iOS) memory-maps the file and composites directly into
/// a GPU `SurfaceTexture`/`CVPixelBuffer`. Flutter then shows the GPU handle
/// via a [Texture] widget — zero pixel copies through Dart.
///
/// This file is the Dart half of that bridge. The native half lives in
/// `android/.../PdfTexturePlugin.kt` (PdfRenderer -> SurfaceTexture). When the
/// native plugin is unavailable (wrong platform, old device, encrypted PDF,
/// vault RAM-only plaintext that must not touch a file descriptor), every
/// entry point falls back to null/false and callers must use pdfrx
/// instead. Fallback is silent by design: a missing texture must never blank
/// a page.
///
/// Native lifecycle (mirrors the Kotlin side):
/// - Single-call open: Dart passes the file path straight to
///   `openPageTexture` (no preliminary `openDocument` roundtrip). One
///   `PdfRenderer` per document path is refcounted natively and kept open
///   while any texture uses it.
/// - Each session holds TWO SurfaceTexture slots (ping-pong). Updates render
///   into the inactive back-buffer and return its textureId; Dart swaps the
///   id AND the [Positioned] box in the same setState frame, so position and
///   pixels can never desync across VSync frames.
/// - [closeTexture] destroys both slots and drops the doc ref immediately —
///   native VRAM never waits on Dart garbage collection.
abstract final class PdfNativeTexture {
  static const MethodChannel _channel = MethodChannel(
    'com.resendeghf.notes/pdf_texture',
  );
  static final _log = Logger('PdfNativeTexture');

  /// Native texture rendering is currently implemented on Android via
  /// `android.graphics.pdf.PdfRenderer` (API 21+). iOS (PDFKit +
  /// FlutterTexture/CVPixelBuffer) follows the same channel contract.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Whether attempting the native path makes sense for [filePath].
  ///
  /// - Missing/unreadable files are excluded (pdfrx error paths own them).
  /// - Vault-unlocked documents are excluded UNLESS [filePath] is an
  ///   already-decrypted, vault-tracked plaintext temp (Temp mode): the
  ///   native renderer needs a file descriptor, and RAM-only policy forbids
  ///   materialising plaintext for it — but a tracked temp is plaintext on
  ///   disk already, so PdfRenderer can open it directly with zero copies.
  ///   A vault (encrypted) asset path itself is never eligible.
  static bool shouldAttemptFor(String? filePath, {bool vaultUnlocked = false}) {
    if (!isSupported) return false;
    if (filePath == null || filePath.isEmpty) return false;
    try {
      final f = File(filePath);
      if (!f.existsSync()) return false;
      if (f.lengthSync() <= 0) return false;
    } catch (_) {
      return false;
    }
    if (!vaultUnlocked) return true;
    try {
      if (VaultAdapter.instance.isTrackedPlaintextDecryptTemp(filePath)) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Renders [pageIndex] of [filePath] into a new native GPU texture of
  /// [widthPx]x[heightPx]. With [clip], only that page-points rect renders
  /// (viewport tile at native vector resolution); without it the full page
  /// renders. Returns the Flutter texture id, or null when the native side
  /// cannot serve it (caller falls back to pdfrx).
  static Future<int?> openPageTexture({
    required String filePath,
    required int pageIndex,
    required int widthPx,
    required int heightPx,
    PdfClip? clip,
  }) async {
    if (!isSupported) return null;
    if (widthPx <= 0 || heightPx <= 0) return null;
    // Bound native bitmap cost: same budget as the pdfrx path.
    final w = widthPx.clamp(1, 3072);
    final h = heightPx.clamp(1, 3072);
    try {
      final args = <String, dynamic>{
        'path': filePath,
        'pageIndex': pageIndex,
        'width': w,
        'height': h,
      };
      if (clip != null && clip.isValid) {
        args['clipL'] = clip.rect.left;
        args['clipT'] = clip.rect.top;
        args['clipR'] = clip.rect.right;
        args['clipB'] = clip.rect.bottom;
        args['pageW'] = clip.pageSize.width;
        args['pageH'] = clip.pageSize.height;
      }
      final id = await _channel
          .invokeMethod<int>('openPageTexture', args)
          .timeout(const Duration(seconds: 15));
      if (id == null || id < 0) return null;
      return id;
    } catch (e, st) {
      _log.fine('pdf_texture.openPageTexture failed', e, st);
      return null;
    }
  }

  /// Re-renders into the session's inactive back-buffer slot.
  ///
  /// Returns the newly rendered back-buffer textureId (swap to it
  /// atomically with its clip), null when superseded (keep showing the
  /// current texture), or -1 on error (fall back to pdfrx).
  static Future<int?> updatePageTexture({
    required int textureId,
    required int pageIndex,
    required int widthPx,
    required int heightPx,
    PdfClip? clip,
    int gen = 0,
  }) async {
    try {
      final args = <String, dynamic>{
        'textureId': textureId,
        'pageIndex': pageIndex,
        'width': widthPx.clamp(1, 3072),
        'height': heightPx.clamp(1, 3072),
        // Generation fencing: superseded queued renders abort before
        // touching the renderer instead of backlogging the executor.
        'gen': gen,
      };
      if (clip != null && clip.isValid) {
        args['clipL'] = clip.rect.left;
        args['clipT'] = clip.rect.top;
        args['clipR'] = clip.rect.right;
        args['clipB'] = clip.rect.bottom;
        args['pageW'] = clip.pageSize.width;
        args['pageH'] = clip.pageSize.height;
      }
      final newId = await _channel
          .invokeMethod<int>('updatePageTexture', args)
          .timeout(const Duration(seconds: 15));
      return newId;
    } catch (e, st) {
      _log.fine('pdf_texture.updatePageTexture failed', e, st);
      return -1;
    }
  }

  static Future<void> closeTexture(int textureId) async {
    try {
      await _channel.invokeMethod<void>('closeTexture', {
        'textureId': textureId,
      }).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best effort: the native side drops the whole session (both slots),
      // so a missed close only costs a transient GPU allocation.
    }
  }
}

/// Clip rect for viewport-tiled renders: [rect] in displayed page points
/// against the full displayed [pageSize] (lets the native side map into
/// renderer page space exactly, no size roundtrip needed).
@immutable
class PdfClip {
  const PdfClip(this.rect, {required this.pageSize});

  final Rect rect;
  final Size pageSize;

  bool get isValid =>
      rect.width > 0 &&
      rect.height > 0 &&
      pageSize.width > 0 &&
      pageSize.height > 0;

  @override
  bool operator ==(Object other) =>
      other is PdfClip && other.rect == rect && other.pageSize == pageSize;

  @override
  int get hashCode => Object.hash(rect, pageSize);
}

/// Shows one PDF page via a native GPU texture, falling back to [fallback]
/// (pdfrx) whenever the texture cannot be provided.
///
/// Tiling contract: when [clip] is set, this view positions ITSELF with
/// `Positioned.fromRect` using [_committedClip] mapped through [boxSize] —
/// the clip the currently displayed pixels were rendered for — never the
/// live requested clip. The box and the pixels swap atomically in one
/// setState, so pans glide the old tile along the document instead of
/// teleporting stale pixels into the new box (no displacement flicker).
/// Therefore this view must be a DIRECT child of a [Stack], with [boxSize]
/// (the page box in local units, measured by an ancestor) passed in.
class PdfNativeTextureView extends StatefulWidget {
  const PdfNativeTextureView({
    super.key,
    required this.filePath,
    required this.pageIndex,
    required this.widthPx,
    required this.heightPx,
    required this.fallback,
    this.clip,
    this.boxSize,
    this.invert = false,
    this.resizeDebounce = Duration.zero,
    this.onFirstFrame,
    this.onFallback,
  }) : assert(
          clip == null || boxSize != null,
          'boxSize is required for clip (tiled) mode positioning',
        );

  final String filePath;
  final int pageIndex;
  final int widthPx;
  final int heightPx;

  /// Viewport tile (with displayed page size), or null for full-page.
  final PdfClip? clip;

  /// Page box size in local units, for mapping the committed clip to a
  /// [Positioned] rect. Required when [clip] is set.
  final Size? boxSize;

  /// Dark-mode inversion, applied INSIDE the positioned box (an InvertWidget
  /// above the [Positioned] would break Stack parent-data).
  final bool invert;
  final Widget fallback;

  /// Debounce before dispatching a resize re-render. Defaults to zero: the
  /// owning renderer already debounces viewport motion and flushes on
  /// settle, so any extra delay here is pure perceptual lag.
  final Duration resizeDebounce;

  /// Fired once the first frame is posted (render-event binding: background
  /// streaming can start; the texture job is provably complete).
  final VoidCallback? onFirstFrame;
  final VoidCallback? onFallback;

  @override
  State<PdfNativeTextureView> createState() => _PdfNativeTextureViewState();
}

class _PdfNativeTextureViewState extends State<PdfNativeTextureView> {
  int? _textureId;

  /// Clip the displayed pixels were rendered for. Updated in the same
  /// setState as [_textureId]: box and pixels are never out of sync.
  PdfClip? _committedClip;
  bool _useFallback = false;
  Timer? _resizeTimer;
  bool _firstFrameFired = false;

  /// Monotonic generation for update fencing (see channel `gen`).
  int _updateGen = 0;
  String _lastSentKey = '';

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(covariant PdfNativeTextureView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_useFallback) return;
    if (widget.filePath != oldWidget.filePath ||
        widget.pageIndex != oldWidget.pageIndex) {
      _reopen();
      return;
    }
    if (widget.widthPx != oldWidget.widthPx ||
        widget.heightPx != oldWidget.heightPx ||
        widget.clip != oldWidget.clip) {
      _resizeTimer?.cancel();
      if (widget.resizeDebounce == Duration.zero) {
        _applyResize();
      } else {
        _resizeTimer = Timer(widget.resizeDebounce, _applyResize);
      }
    } else if (widget.boxSize != oldWidget.boxSize) {
      // Layout-only change: reposition the committed box without
      // re-rendering (pixels are unchanged).
      setState(() {});
    }
  }

  Future<void> _open() async {
    Logger('PDFTIMING').info('PDFTIMING nativeview._open start page=${widget.pageIndex} clip=${widget.clip != null}');
    final t0 = DateTime.now();
    final reqClip = widget.clip;
    final reqW = widget.widthPx;
    final reqH = widget.heightPx;
    final id = await PdfNativeTexture.openPageTexture(
      filePath: widget.filePath,
      pageIndex: widget.pageIndex,
      widthPx: reqW,
      heightPx: reqH,
      clip: reqClip,
    );
    if (!mounted) {
      if (id != null) await PdfNativeTexture.closeTexture(id);
      return;
    }
    if (id == null) {
      Logger('PDFTIMING').info('PDFTIMING nativeview.FALLBACK elapsed=${DateTime.now().difference(t0).inMilliseconds}ms');
      _fallBack();
      return;
    }
    _lastSentKey = '${widget.pageIndex}:${reqW}x$reqH:$reqClip';
    Logger('PDFTIMING').info('PDFTIMING nativeview.texture-opened id=$id elapsed=${DateTime.now().difference(t0).inMilliseconds}ms');
    setState(() {
      _textureId = id;
      _committedClip = reqClip;
    });
    _fireFirstFrame();
    // Props changed while _open() was in flight: apply immediately so the
    // texture never idles on a stale request.
    if (widget.widthPx != reqW ||
        widget.heightPx != reqH ||
        widget.clip != reqClip) {
      unawaited(_applyResize());
    }
  }

  Future<void> _reopen() async {
    await _release();
    if (!mounted) return;
    setState(() {});
    await _open();
  }

  Future<void> _applyResize() async {
    final id = _textureId;
    if (id == null || !mounted) return;
    final reqClip = widget.clip;
    final reqW = widget.widthPx;
    final reqH = widget.heightPx;
    // Coalesce: an identical request already in flight or painted needs no
    // new render (settle often re-fires the same quantized clip).
    final key = '${widget.pageIndex}:${reqW}x$reqH:$reqClip';
    if (key == _lastSentKey) return;
    _lastSentKey = key;
    final gen = ++_updateGen;
    final newId = await PdfNativeTexture.updatePageTexture(
      textureId: id,
      pageIndex: widget.pageIndex,
      widthPx: reqW,
      heightPx: reqH,
      clip: reqClip,
      gen: gen,
    );
    if (!mounted) return;
    if (newId == -1) {
      await _release();
      if (!mounted) return;
      setState(() => _useFallback = true);
      widget.onFallback?.call();
      return;
    }
    if (newId != null && newId >= 0) {
      // Atomic swap: back-buffer textureId and committedClip update in the
      // exact same Flutter frame, preventing any displacement or flicker.
      setState(() {
        _textureId = newId;
        _committedClip = reqClip;
      });
    }
    // newId == null: superseded, keep showing the current texture.
  }

  void _fireFirstFrame() {
    if (_firstFrameFired) return;
    _firstFrameFired = true;
    widget.onFirstFrame?.call();
  }

  void _fallBack() {
    if (!mounted) return;
    setState(() => _useFallback = true);
    widget.onFallback?.call();
  }

  /// Releases the session (both ping-pong slots) immediately. VRAM
  /// discipline: never waits on GC.
  Future<void> _release() async {
    _resizeTimer?.cancel();
    final id = _textureId;
    _textureId = null;
    _committedClip = null;
    if (id != null) await PdfNativeTexture.closeTexture(id);
  }

  @override
  void dispose() {
    unawaited(_release());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_useFallback) return widget.fallback;
    final id = _textureId;
    if (id == null) return widget.fallback;
    final committed = _committedClip;
    if (committed == null) {
      // Full-page texture: fills the parent box (Texture scales to fit).
      return InvertWidget(
        invert: widget.invert,
        child: Texture(textureId: id, filterQuality: FilterQuality.medium),
      );
    }
    // Tiled texture: positioned in DOCUMENT space at the committed
    // sourceRect mapped into the measured page box. Must stay a direct
    // child of a Stack (enforced by the caller contract above).
    final box = widget.boxSize;
    if (box == null || box.isEmpty) {
      return Texture(textureId: id, filterQuality: FilterQuality.medium);
    }
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 4.0);
    // Atomic swap, no dissolve: box and pixels commit together, so there is
    // never a soft intermediate frame. (A fade here turned every arrival of
    // a settle storm into a visible flicker.)
    return Positioned.fromRect(
      // Device-pixel snap: fractional origins bilinear-shift text by whole
      // physical pixels at high zoom (reads as vertical drift on settle).
      rect: PdfTileMath.snapRectToDevicePixels(_mapClip(committed, box), dpr),
      child: InvertWidget(
        invert: widget.invert,
        child: Texture(textureId: id, filterQuality: FilterQuality.medium),
      ),
    );
  }

  /// Maps a committed clip (displayed page points) into page-box units.
  /// Pure linear fill mapping (same contract as the pdfrx tile overlay).
  Rect _mapClip(PdfClip clip, Size box) {
    final page = clip.pageSize;
    if (page.isEmpty || box.isEmpty) return Rect.zero;
    final sx = box.width / page.width;
    final sy = box.height / page.height;
    if (!sx.isFinite || !sy.isFinite || sx <= 0 || sy <= 0) {
      return Rect.zero;
    }
    return Rect.fromLTWH(
      clip.rect.left * sx,
      clip.rect.top * sy,
      clip.rect.width * sx,
      clip.rect.height * sy,
    );
  }
}
