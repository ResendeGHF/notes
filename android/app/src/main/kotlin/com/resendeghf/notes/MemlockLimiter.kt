// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

package com.resendeghf.notes

import android.util.Log

/**
 * Best-effort raise of `RLIMIT_MEMLOCK` via JNI (`getrlimit`/`setrlimit` in libc).
 *
 * Those calls are not reliably on [android.system.Os] for `RLIMIT_MEMLOCK` at
 * this compile SDK, so there is no Java/Kotlin fallback.
 */
object MemlockLimiter {
    private const val TAG = "MemlockLimiter"

    /** Locked-byte budget after the last raise, or -1 if unlimited. */
    @Volatile
    var lastBudgetBytes: Long = 0
        private set

    fun raiseBestEffort(): Long {
        return try {
            val budget = MemlockLimiterNative.raiseBestEffort()
            lastBudgetBytes = budget
            Log.i(TAG, "memlock budget bytes=$budget (-1=unlimited)")
            budget
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "saber_memlock native library not loaded", e)
            lastBudgetBytes
        } catch (e: Throwable) {
            Log.w(TAG, "RLIMIT_MEMLOCK raise failed", e)
            lastBudgetBytes
        }
    }
}
