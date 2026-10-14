package com.resendeghf.notes

import android.graphics.Bitmap
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.SurfaceTexture
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.view.Surface
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Hardware texture rendering (zero-copy path).
 *
 * Standard Flutter PDF packages decode each page to a full RGBA bitmap and
 * copy it across the FFI boundary into Dart (`ui.Image`) on every frame.
 * Native note apps never do that: the OS PDF stack memory-maps the file and
 * composites straight into a GPU surface. This plugin does the same with
 * `android.graphics.pdf.PdfRenderer`:
 * - The file is opened read-only via a file descriptor (the OS mmaps it;
 *   nothing is loaded into Dart RAM).
 * - Pages render on a background thread into a Bitmap that is blitted once
 *   onto the [Surface] backing a Flutter [TextureRegistry] SurfaceTexture
 *   entry. From then on the frame lives on the GPU.
 * - Dart shows the GPU handle with a <Texture> widget: zero pixel copies
 *   through Dart, no FFI bitmap, no `ui.Image` allocation per page.
 *
 * Threading contract (hard Flutter requirement): TextureRegistry entry
 * create/release (FlutterJNI register/unregisterTexture) and every
 * MethodChannel.Result reply are @UiThread. Pixel work (Surface
 * lock/unlock, PdfRenderer, Bitmap) stays on the single executor.
 * Entries are therefore created on the calling (platform) thread and
 * released via [mainHandler]; violating this throws
 * "Methods marked with @UiThread must be executed on the main thread" AND
 * drops the Dart reply, hanging the caller until its timeout.
 *
 * Lifecycle (no thrashing, no crashes, no leaks):
 * - ONE [PdfRenderer] per document path, refcounted, kept open while any
 *   texture uses it. Renderer init happens once per document, not per page;
 *   `openPageTexture` takes the file path directly (single channel call).
 * - [PdfRenderer] allows a single open [PdfRenderer.Page] at a time. Every
 *   open/render/close sequence runs inside `synchronized(holder.lock)` on a
 *   SINGLE-thread executor, so concurrent page requests serialize safely and
 *   `IllegalStateException` from double-open is impossible. Pages are never
 *   held open between requests.
 * - Per-texture generation fencing: stale queued updates abort before
 *   touching the renderer, so flings never backlog decodes.
 * - [closeTexture] destroys both ping-pong slots and drops the doc ref
 *   immediately. Native memory never waits on Dart garbage collection.
 *
 * Atomic tile swaps (no flicker/displacement): each session holds TWO
 * SurfaceTexture slots (ping-pong). Updates render into the inactive
 * back-buffer and return its textureId; Dart swaps the id AND the
 * [Positioned] box in the same setState frame, so position and pixels can
 * never desync across VSync frames.
 *
 * Deep zoom (viewport tiling): updates accept an optional clip rect in PDF
 * page points plus an output bitmap size. Only the visible rect renders, at
 * native vector resolution for the current zoom — a small texture that stays
 * razor sharp at 400-800% zoom instead of a GPU-stretched full page. The
 * clip is mapped with independent per-axis scales so it lands 1:1 on the
 * bitmap with zero edge bleed.
 *
 * Encrypted PDFs throw SecurityException inside PdfRenderer; those calls
 * return the `encrypted` error so Dart falls back to pdfrx (which handles
 * passwords). Any other failure returns a plain error and Dart falls back
 * to pdfrx as well — a missing texture must never blank a page.
 *
 * Channel: `com.resendeghf.notes/pdf_texture`
 * - openPageTexture {path, pageIndex, width, height, clipL?, clipT?,
 *   clipR?, clipB?, pageW?, pageH?} -> textureId (Long)
 * - updatePageTexture {textureId, pageIndex, width, height, gen?,
 *   clipL?, ...} -> newTextureId (Long), null when superseded
 * - closeTexture {textureId} -> null
 */
internal object PdfTexturePlugin {
    private const val CHANNEL = "com.resendeghf.notes/pdf_texture"
    private const val MAX_EDGE = 3072

    /**
     * Opaque white backdrop. PdfRenderer honors page transparency literally:
     * erasing with TRANSPARENT leaves alpha holes that composite as black
     * rects (or break dark-mode inversion) on PDFs with transparent
     * backgrounds such as exported slides. Always opaque white.
     */
    private const val PAGE_BACKGROUND = -0x1 // 0xFFFFFFFF white.

    // Single thread: renders serialize in call order, so a stale frame can
    // never overwrite a newer one. Combined with per-texture generation IDs
    // (stale queued tasks abort before touching the renderer), rapid
    // pan/fling gestures cannot backlog the executor.
    private val executor = Executors.newSingleThreadExecutor()

    // All TextureRegistry traffic (create/release) and every MethodChannel
    // reply runs here (see threading contract above).
    private val mainHandler = Handler(Looper.getMainLooper())

    // Reusable scratch bitmap (thread-confined to [executor]): every render
    // blits through this single buffer instead of allocating a 25-35 MB
    // ARGB_8888 array per tile, which would trigger violent ART GC pauses
    // during pinch-zoom. Grow-only: reallocated only when the request
    // exceeds current capacity (base/tile size switches never churn); the
    // blit always covers exactly the requested w x h sub-rect.
    private var scratch: Bitmap? = null

    private fun obtainScratch(w: Int, h: Int): Bitmap {
        val s = scratch
        if (s != null && !s.isRecycled && s.width >= w && s.height >= h) {
            s.eraseColor(PAGE_BACKGROUND)
            return s
        }
        val allocW = maxOf(w, s?.width ?: 0)
        val allocH = maxOf(h, s?.height ?: 0)
        try {
            s?.recycle()
        } catch (_: Throwable) {
        }
        val fresh = Bitmap.createBitmap(allocW, allocH, Bitmap.Config.ARGB_8888)
        fresh.eraseColor(PAGE_BACKGROUND)
        scratch = fresh
        return fresh
    }

    private class DocHolder(
        val renderer: PdfRenderer,
        val pfd: ParcelFileDescriptor,
        val lock: Any = Any(),
        var refcount: Int = 0,
    )

    private class Slot(
        val entry: TextureRegistry.SurfaceTextureEntry,
        val surface: Surface,
    ) {
        val id: Long get() = entry.id()
        fun surfaceTexture(): SurfaceTexture = entry.surfaceTexture()
    }

    private class Session(
        val docKey: String,
        val slots: Array<Slot>,
        @Volatile var activeSlot: Int = 0,
        @Volatile var pageIndex: Int,
        // Generation fencing: every update bumps this; a queued task whose
        // generation is older than the session's current one aborts before
        // opening the page, so flings never backlog stale decodes.
        @Volatile var activeGen: Int = 0,
    )

    private val docs = HashMap<String, DocHolder>()
    private val sessions = ConcurrentHashMap<Long, Session>()
    private var registered = false

    fun register(flutterEngine: FlutterEngine) {
        if (registered) return
        registered = true
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openPageTexture" -> openPageTexture(flutterEngine, call, result)
                "updatePageTexture" -> updatePageTexture(call, result)
                "closeTexture" -> closeTexture(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun clampEdge(v: Int): Int = v.coerceIn(1, MAX_EDGE)

    private data class Clip(
        val l: Float,
        val t: Float,
        val r: Float,
        val b: Float,
        // Displayed page size (points) the clip was measured against: maps
        // Dart display-space clips into renderer page space, so crop-box
        // documents tile exactly instead of needing a size roundtrip.
        val pageW: Float,
        val pageH: Float,
    ) {
        val isValid: Boolean get() = r > l && b > t
    }

    private fun readClip(call: MethodCall): Clip? {
        val l = (call.argument<Number>("clipL"))?.toFloat() ?: return null
        val t = (call.argument<Number>("clipT"))?.toFloat() ?: return null
        val r = (call.argument<Number>("clipR"))?.toFloat() ?: return null
        val b = (call.argument<Number>("clipB"))?.toFloat() ?: return null
        val pw = (call.argument<Number>("pageW"))?.toFloat() ?: 0f
        val ph = (call.argument<Number>("pageH"))?.toFloat() ?: 0f
        val clip = Clip(l, t, r, b, pw, ph)
        return if (clip.isValid) clip else null
    }

    /** Open (or reuse) the shared renderer for [canonical], taking one ref. */
    private fun getOrOpenDocLocked(canonical: String): DocHolder {
        synchronized(docs) {
            val existing = docs[canonical]
            if (existing != null) {
                existing.refcount++
                return existing
            }
        }
        val pfd = ParcelFileDescriptor.open(
            File(canonical),
            ParcelFileDescriptor.MODE_READ_ONLY,
        )
        val renderer = try {
            PdfRenderer(pfd)
        } catch (e: Throwable) {
            try { pfd.close() } catch (_: Throwable) {}
            throw e
        }
        synchronized(docs) {
            // A concurrent open may have won the race while we were
            // constructing ours; keep exactly one holder per path.
            val raced = docs[canonical]
            if (raced != null) {
                try { renderer.close() } catch (_: Throwable) {}
                try { pfd.close() } catch (_: Throwable) {}
                raced.refcount++
                return raced
            }
            val holder = DocHolder(renderer, pfd, refcount = 1)
            docs[canonical] = holder
            return holder
        }
    }

    /** Decrement [docKey]'s refcount, closing the renderer at zero. */
    private fun releaseDocument(docKey: String) {
        var holder: DocHolder? = null
        synchronized(docs) {
            val h = docs[docKey] ?: return
            h.refcount--
            if (h.refcount <= 0) {
                docs.remove(docKey)
                holder = h
            }
        }
        holder?.let {
            try { it.renderer.close() } catch (_: Throwable) {}
            try { it.pfd.close() } catch (_: Throwable) {}
        }
    }

    private fun withDoc(docKey: String?, block: (DocHolder) -> Unit, onMissing: () -> Unit) {
        if (docKey.isNullOrEmpty()) {
            onMissing()
            return
        }
        val holder: DocHolder?
        synchronized(docs) {
            holder = docs[docKey]
            if (holder != null) holder.refcount++ // pin across the render
        }
        if (holder == null) {
            onMissing()
            return
        }
        try {
            block(holder)
        } finally {
            releaseDocument(docKey)
        }
    }

    private fun releaseSlots(s0: Slot, s1: Slot) {
        try { s0.surface.release() } catch (_: Throwable) {}
        try { s1.surface.release() } catch (_: Throwable) {}
        mainHandler.post {
            try { s0.entry.release() } catch (_: Throwable) {}
            try { s1.entry.release() } catch (_: Throwable) {}
        }
    }

    private fun openPageTexture(
        flutterEngine: FlutterEngine,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        // Single-call open: the file path comes straight from Dart (no
        // preliminary openDocument roundtrip). docKey accepted for compat.
        val rawPath = call.argument<String>("path") ?: call.argument<String>("docKey")
        val pageIndex = call.argument<Int>("pageIndex")
        val width = call.argument<Int>("width")
        val height = call.argument<Int>("height")
        if (rawPath.isNullOrEmpty() || pageIndex == null || width == null || height == null) {
            result.error("bad_args", "openPageTexture: missing arguments", null)
            return
        }
        val canonical = try {
            val c = File(rawPath).canonicalPath
            if (!File(c).isFile) {
                result.error("not_found", "openPageTexture: file missing", null)
                return
            }
            c
        } catch (e: Throwable) {
            result.error("not_found", e.message, null)
            return
        }
        val clip = readClip(call)
        val w = clampEdge(width)
        val h = clampEdge(height)

        // Create the 2-slot ping-pong pair on the platform UI thread
        // (threading contract above): updates render into the inactive
        // back-buffer and Dart swaps id+box atomically, so position and
        // pixels can never desync across VSync frames.
        val slot0: Slot
        val slot1: Slot
        try {
            val e0 = flutterEngine.renderer.createSurfaceTexture()
            val e1 = flutterEngine.renderer.createSurfaceTexture()
            slot0 = Slot(e0, Surface(e0.surfaceTexture()))
            slot1 = Slot(e1, Surface(e1.surfaceTexture()))
        } catch (e: Throwable) {
            result.error("texture_create_failed", e.message, null)
            return
        }

        val tOpenStart = android.os.SystemClock.elapsedRealtime()
        android.util.Log.d("PDFTIMING", "native.open queued page=$pageIndex ${w}x$h")
        executor.execute {
            val holder = try {
                getOrOpenDocLocked(canonical)
            } catch (e: SecurityException) {
                releaseSlots(slot0, slot1)
                postResult(result) { result.error("encrypted", "PDF is encrypted", null) }
                return@execute
            } catch (e: Throwable) {
                releaseSlots(slot0, slot1)
                postResult(result) { result.error("open_failed", e.message, null) }
                return@execute
            }
            val rendered = renderLocked(
                holder,
                pageIndex,
                slot0.surfaceTexture(),
                slot0.surface,
                w,
                h,
                clip,
            )
            if (!rendered) {
                releaseDocument(canonical)
                releaseSlots(slot0, slot1)
                postResult(result) {
                    result.error("render_failed", "initial render failed", null)
                }
                return@execute
            }
            // The opener ref from getOrOpenDocLocked is now owned by the
            // session; closeTexture releases it.
            android.util.Log.d("PDFTIMING", "native.open done page=$pageIndex elapsed=${android.os.SystemClock.elapsedRealtime() - tOpenStart}ms")
            val session = Session(canonical, arrayOf(slot0, slot1), activeSlot = 0, pageIndex = pageIndex)
            sessions[slot0.id] = session
            sessions[slot1.id] = session
            val primaryId = slot0.id
            postResult(result) { result.success(primaryId) }
        }
    }

    private fun updatePageTexture(call: MethodCall, result: MethodChannel.Result) {
        val textureId = (call.argument<Number>("textureId"))?.toLong()
        val pageIndex = call.argument<Int>("pageIndex")
        val width = call.argument<Int>("width")
        val height = call.argument<Int>("height")
        val gen = (call.argument<Number>("gen"))?.toInt() ?: 0
        if (textureId == null || pageIndex == null || width == null || height == null) {
            result.error("bad_args", "updatePageTexture: missing arguments", null)
            return
        }
        val session = sessions[textureId]
        if (session == null) {
            result.error("not_found", "updatePageTexture: unknown textureId", null)
            return
        }
        val clip = readClip(call)
        val w = clampEdge(width)
        val h = clampEdge(height)
        session.pageIndex = pageIndex
        // Fence: newer requests supersede this one even before it runs.
        if (gen > session.activeGen) session.activeGen = gen
        val myGen = gen
        executor.execute {
            // Stale queued task, or texture destroyed while queued (close
            // runs on this same thread): skip instead of burning the
            // renderer or touching a released Surface.
            if (myGen < session.activeGen || sessions[textureId] !== session) {
                postResult(result) { result.success(null) }
                return@execute
            }
            // Render into the INACTIVE back-buffer slot so the currently
            // displayed front slot never mutates or stretches mid-frame.
            val nextSlotIdx = 1 - session.activeSlot
            val targetSlot = session.slots[nextSlotIdx]
            withDoc(session.docKey,
                block = { holder ->
                    val ok = renderLocked(
                        holder,
                        pageIndex,
                        targetSlot.surfaceTexture(),
                        targetSlot.surface,
                        w,
                        h,
                        clip,
                    )
                    if (ok) {
                        session.activeSlot = nextSlotIdx
                        val newTexId = targetSlot.id
                        postResult(result) { result.success(newTexId) }
                    } else {
                        postResult(result) {
                            result.error("render_failed", "re-render failed", null)
                        }
                    }
                },
                onMissing = {
                    postResult(result) {
                        result.error("not_found", "updatePageTexture: document closed", null)
                    }
                })
        }
    }

    private fun closeTexture(call: MethodCall, result: MethodChannel.Result) {
        val textureId = (call.argument<Number>("textureId"))?.toLong()
        if (textureId == null) {
            result.error("bad_args", "closeTexture: missing textureId", null)
            return
        }
        executor.execute {
            destroySession(textureId)
            postResult(result) { result.success(null) }
        }
    }

    /**
     * Render [pageIndex] into [surface] at [w]x[h], optionally clipped to
     * [clip] (PDF points, pre-mapped toward renderer space — see below).
     * Must be called with the doc pin held; the open/render/close page
     * sequence additionally serializes on [holder.lock] so concurrent pages
     * can never double-open the renderer.
     *
     * All pixel work goes through the pooled [scratch] bitmap: no per-render
     * multi-MB allocations, no ART GC pauses during zoom. Thread-confined to
     * the single executor thread.
     */
    private fun renderLocked(
        holder: DocHolder,
        pageIndex: Int,
        surfaceTexture: SurfaceTexture,
        surface: Surface,
        w: Int,
        h: Int,
        clip: Clip?,
    ): Boolean {
        synchronized(holder.lock) {
            return try {
                if (pageIndex < 0 || pageIndex >= holder.renderer.pageCount) {
                    return false
                }
                // Buffer-size sync: the compositor's GraphicBuffer must match
                // the bitmap we are about to post, or frames letterbox /
                // stretch / sample blurry on resize. Set BEFORE locking.
                try {
                    surfaceTexture.setDefaultBufferSize(w, h)
                } catch (_: Throwable) {
                    return false
                }
                holder.renderer.openPage(pageIndex).use { page ->
                    val tRenderStart = android.os.SystemClock.elapsedRealtime()
                    val bmp = obtainScratch(w, h)
                    val pageW = page.width.toFloat()
                    val pageH = page.height.toFloat()
                    if (clip != null && pageW > 0f && pageH > 0f) {
                        // Display-space clip -> renderer-space clip (exact
                        // for unrotated pages; proportional for crop-box
                        // documents, no size roundtrip needed).
                        val scaleX = if (clip.pageW > 0f) pageW / clip.pageW else 1f
                        val scaleY = if (clip.pageH > 0f) pageH / clip.pageH else 1f
                        val cl = (clip.l * scaleX).coerceIn(0f, pageW)
                        val ct = (clip.t * scaleY).coerceIn(0f, pageH)
                        val cr = (clip.r * scaleX).coerceIn(0f, pageW)
                        val cb = (clip.b * scaleY).coerceIn(0f, pageH)
                        if (cr > cl && cb > ct) {
                            // Exact per-axis scale so (cl,ct)..(cr,cb) maps
                            // 1:1 onto (0,0)..(w,h) with zero edge bleed.
                            val sx = w.toFloat() / (cr - cl)
                            val sy = h.toFloat() / (cb - ct)
                            val matrix = Matrix()
                            matrix.setScale(sx, sy)
                            matrix.postTranslate(-cl * sx, -ct * sy)
                            page.render(
                                bmp,
                                Rect(0, 0, w, h),
                                matrix,
                                PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY,
                            )
                        }
                    } else {
                        page.render(
                            bmp,
                            Rect(0, 0, w, h),
                            null,
                            PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY,
                        )
                    }
                    blitToSurface(surfaceTexture, surface, bmp, w, h)
                    android.util.Log.d("PDFTIMING", "native.render page=$pageIndex ${w}x$h elapsed=${android.os.SystemClock.elapsedRealtime() - tRenderStart}ms")
                }
                true
            } catch (_: Throwable) {
                false
            }
        }
    }

    private fun blitToSurface(
        surfaceTexture: SurfaceTexture,
        surface: Surface,
        bitmap: Bitmap,
        w: Int,
        h: Int,
    ) {
        surfaceTexture.setDefaultBufferSize(w, h)
        val canvas = surface.lockCanvas(null)
        try {
            canvas.drawColor(PAGE_BACKGROUND)
            val src = Rect(0, 0, w, h)
            canvas.drawBitmap(bitmap, src, src, null)
        } finally {
            surface.unlockCanvasAndPost(canvas)
        }
    }

    /**
     * Destroy a session NOW: both slots leave the session map and their
     * Surfaces release on the worker (never interleaved mid-render); the
     * @UiThread entry releases and the doc refcount drop follow. Native
     * VRAM never waits on Dart GC.
     */
    private fun destroySession(textureId: Long) {
        val session = sessions.remove(textureId) ?: return
        for (slot in session.slots) {
            sessions.remove(slot.id)
        }
        releaseDocument(session.docKey)
        releaseSlots(session.slots[0], session.slots[1])
    }

    private fun postResult(result: MethodChannel.Result, block: () -> Unit) {
        // All channel replies go through the main thread (@UiThread
        // contract); the worker only computes. Swallowing here is deliberate:
        // teardown races (engine gone) must never crash the executor.
        mainHandler.post {
            try {
                block()
            } catch (_: Throwable) {
            }
        }
    }
}
