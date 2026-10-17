// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

package com.resendeghf.notes

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.zip.Inflater

/**
 * Holds inflated note bodies in native memory. Dart asks for byte ranges
 * instead of copying the whole file across the platform channel on open.
 */
internal object NoteOpenStore {
    private const val CHANNEL = "com.resendeghf.notes/note_open"
    private val io = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "note-open").apply { isDaemon = true }
    }
    private val sessions = ConcurrentHashMap<Int, ByteArray>()
    private var nextId = 1

    fun register(engine: FlutterEngine) {
        val main = android.os.Handler(android.os.Looper.getMainLooper())
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("bad_args", "open: missing path", null)
                            return@setMethodCallHandler
                        }
                        io.execute {
                            try {
                                val bytes = readInflated(path)
                                val id = synchronized(sessions) { nextId++ }
                                sessions[id] = bytes
                                val hash = sampleHash(bytes)
                                main.post {
                                    result.success(
                                        mapOf(
                                            "id" to id,
                                            "length" to bytes.size,
                                            "sampleHash" to hash,
                                        ),
                                    )
                                }
                            } catch (e: Exception) {
                                main.post { result.error("read_failed", e.message, null) }
                            }
                        }
                    }
                    "slice" -> {
                        val id = call.argument<Int>("id")
                        val start = call.argument<Int>("start")
                        val end = call.argument<Int>("end")
                        if (id == null || start == null || end == null) {
                            result.error("bad_args", "slice: missing range", null)
                            return@setMethodCallHandler
                        }
                        io.execute {
                            try {
                                val body = sessions[id]
                                    ?: throw IllegalStateException("Unknown note session $id")
                                if (start < 0 || end < start || end > body.size) {
                                    throw IndexOutOfBoundsException("$start..$end of ${body.size}")
                                }
                                val slice = body.copyOfRange(start, end)
                                main.post { result.success(slice) }
                            } catch (e: Exception) {
                                main.post { result.error("slice_failed", e.message, null) }
                            }
                        }
                    }
                    "close" -> {
                        val id = call.argument<Int>("id")
                        if (id != null) sessions.remove(id)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun readInflated(path: String): ByteArray {
        val raw = File(path).readBytes()
        if (raw.size < 2 || raw[0] != 0x78.toByte()) return raw
        val inflater = Inflater()
        try {
            inflater.setInput(raw)
            val out = ByteArrayOutputStream(raw.size.coerceAtLeast(4096))
            val buf = ByteArray(16 * 1024)
            while (!inflater.finished()) {
                val n = inflater.inflate(buf)
                if (n == 0) {
                    if (inflater.needsInput() || inflater.needsDictionary()) break
                } else {
                    out.write(buf, 0, n)
                }
            }
            if (out.size() == 0) return raw
            return out.toByteArray()
        } catch (_: Exception) {
            return raw
        } finally {
            inflater.end()
        }
    }

    /** Same mix as [NotePageIndex.sampleHash] in Dart. */
    private fun sampleHash(body: ByteArray): Int {
        var h = (body.size and 0x7fffffff).toLong()
        var i = 0
        while (i < body.size) {
            h = 0x1fffffffL and (h * 131L + (body[i].toInt() and 0xff))
            i += 64
        }
        if (body.isNotEmpty()) {
            h = 0x1fffffffL and (h * 131L + (body.last().toInt() and 0xff))
        }
        return h.toInt()
    }
}
