// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

package com.resendeghf.notes

import android.app.Application
import android.content.Context

/**
 * Runs before activities and Dart isolate startup so native code (SQLCipher
 * [mlock]) sees an updated memlock limit when possible.
 */
class NotesApplication : Application() {
    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        MemlockLimiter.raiseBestEffort()
    }

    override fun onCreate() {
        super.onCreate()
        MemlockLimiter.raiseBestEffort()
    }
}
