package com.resendeghf.notes

import android.content.Context
import android.graphics.Matrix
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import androidx.ink.authoring.InProgressStrokeId
import androidx.ink.authoring.InProgressStrokesFinishedListener
import androidx.ink.authoring.InProgressStrokesView
import androidx.ink.brush.Brush
import androidx.ink.brush.StockBrushes
import androidx.ink.strokes.Stroke
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

// ---------------------------------------------------------------------------
// Google Ink experimental-pen engine (Android).
//
// Architecture (Phase 1 test bench):
// - The transparent [GoogleInkPlatformView] is mounted full-screen above the
//   canvas ONLY while the experimental pen is selected. It consumes STYLUS
//   pointers exclusively: fingers, mouse, rubber and the inverted-stylus
//   eraser end return false untouched, so pan/scroll/zoom, the app eraser and
//   finger-draw keep flowing to Flutter's gesture arena (consuming the first
//   DOWN natively would starve Flutter's ScaleGestureRecognizer and kill
//   pinch-zoom). Two-finger input cancels live native ink the same way.
// - Touch capture is native for the stylus: MotionEvents (pressure / tilt /
//   orientation, 120Hz+ with requestUnbufferedDispatch) feed
//   androidx.ink.authoring.InProgressStrokesView, which models
//   (ink-stroke-modeler input smoothing) + renders the low-latency shader mesh.
//   Samples pushed to Dart are converted px -> dp (Flutter logical px).
// - Brush comes from androidx.ink.brush.StockBrushes + Brush.createWithColorIntArgb,
//   driven by the Dart test modal over the `google_ink` MethodChannel.
// - Persistence stays in Dart: on finish we push the screen-space input batch
//   to Flutter (`onGoogleInkStrokeFinished`); Dart maps screen->world with the
//   live canvas transform, commits a normal Stroke (toolId=experimentalPen),
//   and the standard tiled Picture + PageRasterCache LOD bakes it. The native
//   view never owns committed ink.
//
// Upstream docs:
// - https://github.com/google/ink , https://github.com/google/ink-stroke-modeler
// - developer.android.com/develop/ui/views/touch-and-input/stylus-input/ink-api-*
// ---------------------------------------------------------------------------

internal data class InkSample(
    val x: Float,
    val y: Float,
    val pressure: Float,
    val tiltDeg: Float,
    val timeMs: Long,
)

internal object GoogleInkBrushFactory {
    @Volatile var size: Float = 4f
    @Volatile var colorArgb: Int = -16777216 // opaque black
    @Volatile var epsilon: Float = 0.1f
    @Volatile var familyId: String = "pressurePen"

    @Volatile var currentBrush: Brush? = null

    // Finished screen-space batches waiting for Dart to drain/push.
    // Pushed proactively via `onGoogleInkStrokeFinished`; kept here as well
    // so `drainFinishedInputs` can re-deliver after a missed push.
    val finishedQueue: ArrayDeque<List<InkSample>> = ArrayDeque()

    fun buildBrush(): Brush {
        val family = try {
            when (familyId) {
                "marker" -> StockBrushes.marker()
                "highlighter" -> StockBrushes.highlighter()
                // Stock set has no dedicated brush/calligraphy/dashed families;
                // pressurePen is the closest modeling tip; the Dart fallback
                // (google_ink_geometry.dart) draws the distinctive nib/dash so
                // committed ink still reads differently per family in tests.
                else -> StockBrushes.pressurePen()
            }
        } catch (_: Throwable) {
            // Last resort: never crash the editor for a brush miss.
            StockBrushes.marker()
        }
        val s = size.coerceIn(0.5f, 48f)
        val e = epsilon.coerceIn(0.01f, 1f).coerceAtMost(s)
        return try {
            Brush.createWithColorIntArgb(family, colorArgb, s, e)
        } catch (_: Throwable) {
            Brush(family, s, e)
        }.also { currentBrush = it }
    }

    fun currentBrushOrBuild(): Brush =
        try {
            currentBrush ?: buildBrush()
        } catch (_: Throwable) {
            buildBrush()
        }
}

class GoogleInkViewFactory(
    private val messenger: BinaryMessenger,
    private val pushChannel: MethodChannel,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return GoogleInkPlatformView(context, pushChannel)
    }
}

class GoogleInkPlatformView(
    private val context: Context,
    private val pushChannel: MethodChannel,
) : PlatformView, View.OnTouchListener, InProgressStrokesFinishedListener {

    private val container = FrameLayout(context)
    private var inProgressView: InProgressStrokesView? = null

    // Active native stroke per pointer id (erased size; single ink pointer typical).
    private val nativeStrokeIds = mutableMapOf<Int, Any>()
    // Overlay-local samples per pointer, pushed to Dart on finish.
    // Already converted to dp (Flutter logical px): Dart maps them with the
    // overlay RenderBox + canvas transform, so committed ink lands exactly
    // where it was drawn.
    private val activeSamples = mutableMapOf<Int, MutableList<InkSample>>()

    /// Display density (px per dp). MotionEvent coordinates arrive in physical
    /// view px; Flutter layout (and the Dart commit mapping) works in dp.
    /// Forgetting this factor misplaces committed strokes by ~density.
    private val density: Float
        get() {
            return try {
                val d = context.resources.displayMetrics.density
                if (d > 0) d else 1f
            } catch (_: Throwable) {
                1f
            }
        }

    init {
        container.layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        )
        try {
            val v = InProgressStrokesView(context)
            v.layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
            // Transparent overlay above Flutter tiles.
            v.setBackgroundColor(android.graphics.Color.TRANSPARENT)
            v.addFinishedStrokesListener(this)
            container.addView(v)
            container.setOnTouchListener(this)
            inProgressView = v
            // Pre-build the brush off the first-touch path.
            try {
                GoogleInkBrushFactory.currentBrushOrBuild()
            } catch (_: Throwable) {
            }
        } catch (t: Throwable) {
            android.util.Log.w("GoogleInk", "InProgressStrokesView unavailable, touch capture only", t)
            container.setOnTouchListener(this)
            inProgressView = null
        }
    }

    override fun getView(): View = container

    override fun dispose() {
        try {
            inProgressView?.removeFinishedStrokesListener(this)
        } catch (_: Throwable) {
        }
        nativeStrokeIds.clear()
        activeSamples.clear()
    }

    // -- Brush / config channel (called from MainActivity handler) ----------

    fun applyBrushMap(args: Map<*, *>) {
        (args["family"] as? String)?.let { GoogleInkBrushFactory.familyId = it }
        (args["size"] as? Number)?.let { GoogleInkBrushFactory.size = it.toFloat() }
        (args["colorArgb"] as? Number)?.let { GoogleInkBrushFactory.colorArgb = it.toInt() }
        (args["epsilon"] as? Number)?.let { GoogleInkBrushFactory.epsilon = it.toFloat() }
        try {
            GoogleInkBrushFactory.buildBrush()
        } catch (t: Throwable) {
            android.util.Log.w("GoogleInk", "buildBrush failed", t)
        }
    }

    fun clearLive() {
        try {
            val v = inProgressView ?: return
            // `getFinishedStrokes()` naming drifted across alphas (property vs
            // getter), so resolve via reflection: compilation must never depend
            // on the exact accessor name.
            try {
                val getter = v.javaClass.methods.firstOrNull {
                    it.name == "getFinishedStrokes" && it.parameterTypes.isEmpty()
                }
                @Suppress("UNCHECKED_CAST")
                val finished = getter?.invoke(v) as? Map<Any, Any>
                if (finished != null && finished.isNotEmpty()) {
                    val remover = v.javaClass.methods.firstOrNull {
                        it.name == "removeFinishedStrokes" && it.parameterTypes.size == 1
                    }
                    remover?.invoke(v, finished.keys)
                }
            } catch (_: Throwable) {
            }
        } catch (_: Throwable) {
        }
        nativeStrokeIds.clear()
        activeSamples.clear()
    }

    // -- Native touch capture -------------------------------------------------

    private fun sampleOf(e: MotionEvent, pointerIndex: Int): InkSample {
        val pressure = try {
            e.getPressure(pointerIndex).coerceIn(0f, 1f)
        } catch (_: Throwable) {
            0.5f
        }
        val tilt = try {
            // Axis tilt (radians) -> degrees for the Dart tip model.
            val ax = e.getAxisValue(MotionEvent.AXIS_TILT, pointerIndex)
            Math.toDegrees(ax.toDouble()).toFloat()
        } catch (_: Throwable) {
            0f
        }
        val d = density
        return InkSample(
            x = e.getX(pointerIndex) / d,
            y = e.getY(pointerIndex) / d,
            pressure = pressure,
            tiltDeg = tilt,
            timeMs = e.eventTime,
        )
    }

    private fun toolTypeOf(e: MotionEvent, pointerIndex: Int): Int {
        return try {
            e.getToolType(pointerIndex)
        } catch (_: Throwable) {
            MotionEvent.TOOL_TYPE_UNKNOWN
        }
    }

    override fun onTouch(v: View, event: MotionEvent): Boolean {
        // Two-finger gestures belong to Flutter (pinch-zoom + viewport LOD):
        // cancel any live native ink and let the event fall through.
        if (event.pointerCount >= 2) {
            cancelAllNative("multitouch")
            return false
        }
        val action = event.actionMasked
        val pointerIndex = event.actionIndex
        // Native ink owns STYLUS pointers only. Fingers, mouse, rubber and the
        // inverted-stylus eraser end fall through to Flutter untouched, so
        // pan/scroll/zoom, the app eraser and finger-draw keep working while
        // the experimental pen is selected. Consuming the first DOWN here
        // would starve Flutter's gesture arena (breaking pinch-zoom), so any
        // non-stylus DOWN must return false without recording anything.
        if (toolTypeOf(event, pointerIndex) != MotionEvent.TOOL_TYPE_STYLUS) {
            return false
        }
        val pointerId = try {
            event.getPointerId(pointerIndex)
        } catch (_: Throwable) {
            return false
        }
        return when (action) {
            MotionEvent.ACTION_DOWN -> {
                try {
                    v.requestUnbufferedDispatch(event)
                } catch (_: Throwable) {
                }
                activeSamples[pointerId] = mutableListOf(sampleOf(event, pointerIndex))
                startNativeStroke(event, pointerId)
                true
            }
            MotionEvent.ACTION_MOVE -> {
                val samples = activeSamples[pointerId] ?: return false
                val d = density
                for (i in 0 until event.pointerCount) {
                    val id = try {
                        event.getPointerId(i)
                    } catch (_: Throwable) {
                        continue
                    }
                    if (id != pointerId) continue
                    if (toolTypeOf(event, i) != MotionEvent.TOOL_TYPE_STYLUS) continue
                    // Include historical samples: native-rate fidelity (120Hz+).
                    try {
                        val h = event.historySize
                        for (hi in 0 until h) {
                            samples.add(
                                InkSample(
                                    x = event.getHistoricalX(i, hi) / d,
                                    y = event.getHistoricalY(i, hi) / d,
                                    pressure = event.getHistoricalPressure(i, hi).coerceIn(0f, 1f),
                                    tiltDeg = samples.lastOrNull()?.tiltDeg ?: 0f,
                                    timeMs = event.getHistoricalEventTime(hi),
                                ),
                            )
                        }
                    } catch (_: Throwable) {
                    }
                    samples.add(sampleOf(event, i))
                }
                addNativeStroke(event, pointerId)
                true
            }
            MotionEvent.ACTION_UP -> {
                activeSamples[pointerId]?.add(sampleOf(event, pointerIndex))
                finishNativeStroke(event, pointerId, canceled = false)
                true
            }
            MotionEvent.ACTION_CANCEL -> {
                cancelAllNative("cancel")
                true
            }
            MotionEvent.ACTION_POINTER_DOWN, MotionEvent.ACTION_POINTER_UP -> {
                // Second finger mid-stroke: hand the viewport back to Flutter.
                cancelAllNative("pointer")
                false
            }
            else -> false
        }
    }

    private fun startNativeStroke(event: MotionEvent, pointerId: Int) {
        val v = inProgressView ?: return
        try {
            val brush = GoogleInkBrushFactory.currentBrushOrBuild()
            val identity = Matrix()
            // Documented Views overload:
            // startStroke(event, pointerId, brush, motionEventToWorld, strokeToWorld).
            // Screen-space recording (identity); Dart maps screen->world on commit
            // with the live canvas transform (stable: no pinch mid-ink).
            val id = v.startStroke(event, pointerId, brush, identity, identity)
            nativeStrokeIds[pointerId] = id as Any
        } catch (t: Throwable) {
            android.util.Log.w("GoogleInk", "startStroke failed", t)
        }
    }

    /**
     * Invokes the first [name] overload that actually accepts [args].
     *
     * The androidx.ink alphas renamed/overloaded the authoring calls; matching
     * by arity alone can hit an overload with incompatible parameter types, so
     * a blind invoke throws and (previously swallowed) kills live rendering
     * with zero feedback. Here an [IllegalArgumentException] means "wrong
     * overload, try the next", while any other throwable means the overload
     * matched but its implementation threw — stop and report that instead.
     */
    private fun invokeBest(target: Any, name: String, vararg args: Any?): Boolean {
        val cands = target.javaClass.methods.filter {
            it.name == name && it.parameterTypes.size == args.size
        }
        if (cands.isEmpty()) {
            android.util.Log.w("GoogleInk", "$name: no overload with ${args.size} args")
            return false
        }
        for (m in cands) {
            try {
                m.invoke(target, *args)
                return true
            } catch (e: IllegalArgumentException) {
                continue
            } catch (e: java.lang.reflect.InvocationTargetException) {
                android.util.Log.w("GoogleInk", "$name ${m.parameterTypes.contentToString()} threw", e.cause ?: e)
                return false
            } catch (t: Throwable) {
                android.util.Log.w("GoogleInk", "$name failed", t)
                return false
            }
        }
        android.util.Log.w("GoogleInk", "$name: no compatible overload")
        return false
    }

    private fun addNativeStroke(event: MotionEvent, pointerId: Int) {
        val v = inProgressView ?: return
        val id = nativeStrokeIds[pointerId] ?: return
        // addToStroke(event, pointerId, strokeId, predictedEvent=null).
        invokeBest(v, "addToStroke", event, pointerId, id, null)
    }

    private fun finishNativeStroke(event: MotionEvent, pointerId: Int, canceled: Boolean) {
        val v = inProgressView
        val id = nativeStrokeIds.remove(pointerId)
        val samples = activeSamples.remove(pointerId)
        if (v != null && id != null) {
            if (canceled) {
                invokeBest(v, "cancelStroke", id, event)
            } else {
                // finishStroke(event, pointerId, strokeId); some alphas named
                // it finishStrokes — probe both.
                if (!invokeBest(v, "finishStroke", event, pointerId, id)) {
                    invokeBest(v, "finishStrokes", event, pointerId, id)
                }
            }
        }
        // Persistence payload goes to Dart regardless of the render path, so a
        // renderer miss can never lose ink (Dart fallback still commits).
        if (!canceled && samples != null && samples.size >= 1) {
            pushFinished(samples)
        }
    }

    private fun cancelAllNative(reason: String) {
        val v = inProgressView
        for ((pointerId, id) in nativeStrokeIds) {
            if (v != null) {
                // Last MotionEvent unavailable here; pass null-tolerant cancel.
                // Most alphas accept (strokeId, event); reflection keeps us compiling.
                invokeBest(v, "cancelStroke", id, null)
            }
        }
        nativeStrokeIds.clear()
        activeSamples.clear()
    }

    // -- Finished-stroke handoff ----------------------------------------------

    @androidx.annotation.UiThread
    override fun onStrokesFinished(strokes: Map<InProgressStrokeId, Stroke>) {
        // Keep rendering the finished mesh until Dart commits + clears, avoiding
        // a one-frame gap between native live ink and the baked Dart stroke.
        // Actual persistence payload was already pushed in finishNativeStroke().
        try {
            // Opportunistically drop the oldest queued duplicate.
            while (GoogleInkBrushFactory.finishedQueue.size > 4) {
                GoogleInkBrushFactory.finishedQueue.removeFirst()
            }
        } catch (_: Throwable) {
        }
    }

    private fun pushFinished(samples: List<InkSample>) {
        try {
            GoogleInkBrushFactory.finishedQueue.addLast(samples.toList())
            while (GoogleInkBrushFactory.finishedQueue.size > 8) {
                GoogleInkBrushFactory.finishedQueue.removeFirst()
            }
            val payload = HashMap<String, Any>()
            payload["samples"] = samples.map {
                mapOf(
                    "x" to it.x.toDouble(),
                    "y" to it.y.toDouble(),
                    "pressure" to it.pressure.toDouble(),
                    "tilt" to it.tiltDeg.toDouble(),
                    "time" to it.timeMs.toDouble(),
                )
            }
            payload["brush"] = mapOf(
                "family" to GoogleInkBrushFactory.familyId,
                "size" to GoogleInkBrushFactory.size.toDouble(),
                "colorArgb" to GoogleInkBrushFactory.colorArgb.toDouble(),
                "epsilon" to GoogleInkBrushFactory.epsilon.toDouble(),
            )
            try {
                pushChannel.invokeMethod("onGoogleInkStrokeFinished", payload)
            } catch (_: Throwable) {
            }
        } catch (t: Throwable) {
            android.util.Log.w("GoogleInk", "pushFinished failed", t)
        }
    }
}

// ---------------------------------------------------------------------------
// Registration + MethodChannel, called from MainActivity.configureFlutterEngine.
// ---------------------------------------------------------------------------

object GoogleInkPlugin {
    const val VIEW_TYPE = "com.resendeghf.notes/google_ink_view"
    const val CHANNEL = "com.resendeghf.notes/google_ink"

    // Last live view (single overlay). Channel calls target it.
    @Volatile var liveView: GoogleInkPlatformView? = null

    fun register(engine: io.flutter.embedding.engine.FlutterEngine) {
        val messenger: BinaryMessenger = engine.dartExecutor.binaryMessenger
        val push = MethodChannel(messenger, CHANNEL)
        val factory = object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
            override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
                val v = GoogleInkPlatformView(context, push)
                liveView = v
                return v
            }
        }
        try {
            engine.platformViewsController.registry.registerViewFactory(VIEW_TYPE, factory)
        } catch (t: Throwable) {
            android.util.Log.w("GoogleInk", "registerViewFactory failed", t)
        }
        PendingFactory.holder = factory
        push.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "setBrush" -> {
                    @Suppress("UNCHECKED_CAST")
                    val map = call.arguments as? Map<*, *>
                    if (map != null) {
                        GoogleInkBrushFactory.familyId =
                            (map["family"] as? String) ?: GoogleInkBrushFactory.familyId
                        GoogleInkBrushFactory.size =
                            (map["size"] as? Number)?.toFloat() ?: GoogleInkBrushFactory.size
                        GoogleInkBrushFactory.colorArgb =
                            (map["colorArgb"] as? Number)?.toInt() ?: GoogleInkBrushFactory.colorArgb
                        GoogleInkBrushFactory.epsilon =
                            (map["epsilon"] as? Number)?.toFloat() ?: GoogleInkBrushFactory.epsilon
                        try {
                            GoogleInkBrushFactory.buildBrush()
                        } catch (_: Throwable) {
                        }
                        liveView?.applyBrushMap(map)
                    }
                    result.success(null)
                }
                "setPrediction" -> result.success(null) // MotionEventPredictor internal; kept for API parity.
                "clearLive" -> {
                    liveView?.clearLive()
                    result.success(null)
                }
                "drainFinishedInputs" -> {
                    val q = GoogleInkBrushFactory.finishedQueue
                    val last = q.removeLastOrNull()
                    if (last == null) {
                        result.success(null)
                    } else {
                        result.success(
                            last.map {
                                mapOf(
                                    "x" to it.x.toDouble(),
                                    "y" to it.y.toDouble(),
                                    "pressure" to it.pressure.toDouble(),
                                    "tilt" to it.tiltDeg.toDouble(),
                                    "time" to it.timeMs.toDouble(),
                                )
                            },
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
        PendingFactory.holder = factory
    }

    object PendingFactory {
        @Volatile var holder: PlatformViewFactory? = null
    }
}
