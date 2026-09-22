// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

package com.resendeghf.notes

import android.util.Log
import com.google_mlkit_digital_ink_recognition.DigitalInkRecognizer
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * compat shim for google_mlkit_digital_ink_recognition 0.16.x.
 *
 * That version builds its GMS RemoteModelManager eagerly inside the method
 * call handler constructor. If that throws during engine plugin
 * auto-registration (observed NullPointerException inside Play Services init
 * on some devices), the generated registrant swallows the failure and the
 * channel is left with no handler, so every Dart call fails forever with
 * MissingPluginException.
 *
 * This installs a delegating handler that constructs the real handler lazily
 * on first use, when ML Kit init has had a chance to settle. Construction
 * failures are reported back as structured channel errors instead of leaving
 * the channel dead, and only the first failure is logged.
 */
object MlKitInkCompat {
    private const val TAG = "MlKitInkCompat"
    private const val CHANNEL = "google_mlkit_digital_ink_recognizer"

    @Volatile
    private var delegate: MethodChannel.MethodCallHandler? = null

    @Volatile
    private var loggedFailure = false

    fun registerLazy(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            try {
                val handler = delegate ?: buildDelegate()
                if (handler == null) {
                    result.error(
                        "mlkit_unavailable",
                        "Digital Ink recognizer unavailable on this device",
                        null,
                    )
                    return@setMethodCallHandler
                }
                handler.onMethodCall(call, result)
            } catch (e: Throwable) {
                Log.w(TAG, "delegated ink call failed: ${call.method}", e)
                try {
                    result.error("mlkit_error", e.toString(), null)
                } catch (_: Throwable) {
                }
            }
        }
        Log.i(TAG, "lazy delegating handler installed")
    }

    @Synchronized
    private fun buildDelegate(): MethodChannel.MethodCallHandler? {
        delegate?.let { return it }
        return try {
            DigitalInkRecognizer().also {
                delegate = it
                Log.i(TAG, "real DigitalInkRecognizer constructed")
            }
        } catch (e: Throwable) {
            if (!loggedFailure) {
                loggedFailure = true
                Log.w(TAG, "DigitalInkRecognizer construction failed", e)
            }
            null
        }
    }
}
