package com.resendeghf.notes

import android.content.Intent.FLAG_ACTIVITY_NEW_TASK
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity: FlutterActivity() {
    // Parallel crypto/IO for vault blobs (reads can overlap; writes are still
    // ordered by Dart-side awaiting). Sized for aarch64 phone cores.
    private val vaultCryptoExecutor = Executors.newFixedThreadPool(
        (Runtime.getRuntime().availableProcessors().coerceAtLeast(2)).coerceAtMost(4),
    )
    private val pdfBoxExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.resendeghf.notes/vault_crypto",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "raiseMemlock" -> {
                    result.success(MemlockLimiter.raiseBestEffort())
                    return@setMethodCallHandler
                }
                "encryptFileCbc" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val destPath = call.argument<String>("destPath")
                    val key = call.argument<ByteArray>("key")
                    val iv = call.argument<ByteArray>("iv")
                    if (sourcePath.isNullOrEmpty() || destPath.isNullOrEmpty() || key == null || iv == null) {
                        result.error("bad_args", "encryptFileCbc: missing argument", null)
                        return@setMethodCallHandler
                    }
                    vaultCryptoExecutor.execute {
                        try {
                            VaultAesFileEncrypt.encryptFileCbc(sourcePath, destPath, key, iv)
                            runOnUiThread { result.success(null) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("encrypt_failed", e.message, null)
                            }
                        }
                    }
                }
                "decryptFileCbc" -> {
                    val cipherPath = call.argument<String>("cipherPath")
                    val destPath = call.argument<String>("destPath")
                    val key = call.argument<ByteArray>("key")
                    val iv = call.argument<ByteArray>("iv")
                    if (cipherPath.isNullOrEmpty() || destPath.isNullOrEmpty() || key == null || iv == null) {
                        result.error("bad_args", "decryptFileCbc: missing argument", null)
                        return@setMethodCallHandler
                    }
                    vaultCryptoExecutor.execute {
                        try {
                            VaultAesFileEncrypt.decryptFileCbc(cipherPath, destPath, key, iv)
                            runOnUiThread { result.success(null) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("decrypt_failed", e.message, null)
                            }
                        }
                    }
                }
                "encryptBytesToFileCbc" -> {
                    val destPath = call.argument<String>("destPath")
                    val plaintext = call.argument<ByteArray>("plaintext")
                    val key = call.argument<ByteArray>("key")
                    val iv = call.argument<ByteArray>("iv")
                    if (destPath.isNullOrEmpty() || plaintext == null || key == null || iv == null) {
                        result.error("bad_args", "encryptBytesToFileCbc: missing argument", null)
                        return@setMethodCallHandler
                    }
                    vaultCryptoExecutor.execute {
                        try {
                            VaultAesFileEncrypt.encryptBytesToFileCbc(destPath, plaintext, key, iv)
                            runOnUiThread { result.success(null) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("encrypt_failed", e.message, null)
                            }
                        }
                    }
                }
                "decryptFileToBytesCbc" -> {
                    val cipherPath = call.argument<String>("cipherPath")
                    val key = call.argument<ByteArray>("key")
                    val iv = call.argument<ByteArray>("iv")
                    if (cipherPath.isNullOrEmpty() || key == null || iv == null) {
                        result.error("bad_args", "decryptFileToBytesCbc: missing argument", null)
                        return@setMethodCallHandler
                    }
                    vaultCryptoExecutor.execute {
                        try {
                            val plain = VaultAesFileEncrypt.decryptFileToBytesCbc(cipherPath, key, iv)
                            runOnUiThread { result.success(plain) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("decrypt_failed", e.message, null)
                            }
                        }
                    }
                }
                "encryptBytesToFileGcm" -> {
                    val destPath = call.argument<String>("destPath")
                    val plaintext = call.argument<ByteArray>("plaintext")
                    val key = call.argument<ByteArray>("key")
                    if (destPath.isNullOrEmpty() || plaintext == null || key == null) {
                        result.error("bad_args", "encryptBytesToFileGcm: missing argument", null)
                        return@setMethodCallHandler
                    }
                    vaultCryptoExecutor.execute {
                        try {
                            val nonce = VaultAesFileEncrypt.encryptBytesToFileGcm(destPath, plaintext, key)
                            runOnUiThread { result.success(nonce) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("encrypt_failed", e.message, null)
                            }
                        }
                    }
                }
                "encryptBytesToFileGcmZlib" -> {
                    val destPath = call.argument<String>("destPath")
                    val plaintext = call.argument<ByteArray>("plaintext")
                    val key = call.argument<ByteArray>("key")
                    val compressZlib = call.argument<Boolean>("compressZlib") ?: false
                    if (destPath.isNullOrEmpty() || plaintext == null || key == null) {
                        result.error("bad_args", "encryptBytesToFileGcmZlib: missing argument", null)
                        return@setMethodCallHandler
                    }
                    vaultCryptoExecutor.execute {
                        try {
                            val (nonce, plainSize) = VaultAesFileEncrypt.encryptBytesToFileGcmZlib(
                                destPath, plaintext, key, compressZlib,
                            )
                            runOnUiThread {
                                result.success(
                                    hashMapOf(
                                        "nonce" to nonce,
                                        "plainSize" to plainSize,
                                        "cipherVer" to 1,
                                    ),
                                )
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("encrypt_failed", e.message, null)
                            }
                        }
                    }
                }
                "encryptFileToGcmZlib" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val destPath = call.argument<String>("destPath")
                    val key = call.argument<ByteArray>("key")
                    val compressZlib = call.argument<Boolean>("compressZlib") ?: false
                    val aadPrefix = call.argument<ByteArray>("aadPrefix") ?: ByteArray(0)
                    if (sourcePath.isNullOrEmpty() || destPath.isNullOrEmpty() || key == null) {
                        result.error("bad_args", "encryptFileToGcmZlib: missing argument", null)
                        return@setMethodCallHandler
                    }
                    vaultCryptoExecutor.execute {
                        try {
                            val (nonce, plainSize, cipherVer) = VaultAesFileEncrypt.encryptFileToGcmZlib(
                                sourcePath, destPath, key, compressZlib, aadPrefix,
                            )
                            runOnUiThread {
                                result.success(
                                    hashMapOf(
                                        "nonce" to nonce,
                                        "plainSize" to plainSize,
                                        "cipherVer" to cipherVer,
                                    ),
                                )
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("encrypt_failed", e.message, null)
                            }
                        }
                    }
                }
                "decryptFileToBytesGcmZlib" -> {
                    val cipherPath = call.argument<String>("cipherPath")
                    val key = call.argument<ByteArray>("key")
                    val nonce = call.argument<ByteArray>("nonce")
                    val cipherVer = call.argument<Int>("cipherVer") ?: 1
                    val aadPrefix = call.argument<ByteArray>("aadPrefix") ?: ByteArray(0)
                    val inflateZlib = call.argument<Boolean>("inflateZlib") ?: false
                    if (cipherPath.isNullOrEmpty() || key == null) {
                        result.error("bad_args", "decryptFileToBytesGcmZlib: missing argument", null)
                        return@setMethodCallHandler
                    }
                    vaultCryptoExecutor.execute {
                        try {
                            val plain = VaultAesFileEncrypt.decryptFileToBytesGcmZlib(
                                cipherPath, key, nonce, cipherVer, aadPrefix, inflateZlib,
                            )
                            runOnUiThread { result.success(plain) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("decrypt_failed", e.message, null)
                            }
                        }
                    }
                }
                "peekCipherVer" -> {
                    val cipherPath = call.argument<String>("cipherPath")
                    if (cipherPath.isNullOrEmpty()) {
                        result.error("bad_args", "peekCipherVer: missing argument", null)
                        return@setMethodCallHandler
                    }
                    vaultCryptoExecutor.execute {
                        try {
                            val ver = VaultAesFileEncrypt.peekCipherVer(cipherPath)
                            runOnUiThread { result.success(ver) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("peek_failed", e.message, null)
                            }
                        }
                    }
                }
                "decryptFileToBytesGcm" -> {
                    val cipherPath = call.argument<String>("cipherPath")
                    val key = call.argument<ByteArray>("key")
                    val nonce = call.argument<ByteArray>("nonce")
                    if (cipherPath.isNullOrEmpty() || key == null || nonce == null) {
                        result.error("bad_args", "decryptFileToBytesGcm: missing argument", null)
                        return@setMethodCallHandler
                    }
                    vaultCryptoExecutor.execute {
                        try {
                            val plain = VaultAesFileEncrypt.decryptFileToBytesGcm(cipherPath, key, nonce)
                            runOnUiThread { result.success(plain) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("decrypt_failed", e.message, null)
                            }
                        }
                    }
                }
                "encryptFileGcm" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val destPath = call.argument<String>("destPath")
                    val key = call.argument<ByteArray>("key")
                    if (sourcePath.isNullOrEmpty() || destPath.isNullOrEmpty() || key == null) {
                        result.error("bad_args", "encryptFileGcm: missing argument", null)
                        return@setMethodCallHandler
                    }
                    vaultCryptoExecutor.execute {
                        try {
                            val nonce = VaultAesFileEncrypt.encryptFileGcm(sourcePath, destPath, key)
                            runOnUiThread { result.success(nonce) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("encrypt_failed", e.message, null)
                            }
                        }
                    }
                }
                "decryptFileGcm" -> {
                    val cipherPath = call.argument<String>("cipherPath")
                    val destPath = call.argument<String>("destPath")
                    val key = call.argument<ByteArray>("key")
                    val nonce = call.argument<ByteArray>("nonce")
                    if (cipherPath.isNullOrEmpty() || destPath.isNullOrEmpty() || key == null || nonce == null) {
                        result.error("bad_args", "decryptFileGcm: missing argument", null)
                        return@setMethodCallHandler
                    }
                    vaultCryptoExecutor.execute {
                        try {
                            VaultAesFileEncrypt.decryptFileGcm(cipherPath, destPath, key, nonce)
                            runOnUiThread { result.success(null) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("decrypt_failed", e.message, null)
                            }
                        }
                    }
                }
                "encryptFileGcmChunked" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val destPath = call.argument<String>("destPath")
                    val key = call.argument<ByteArray>("key")
                    val aadPrefix = call.argument<ByteArray>("aadPrefix") ?: ByteArray(0)
                    if (sourcePath.isNullOrEmpty() || destPath.isNullOrEmpty() || key == null) {
                        result.error("bad_args", "encryptFileGcmChunked: missing argument", null)
                        return@setMethodCallHandler
                    }
                    vaultCryptoExecutor.execute {
                        try {
                            VaultAesFileEncrypt.encryptFileGcmChunked(sourcePath, destPath, key, aadPrefix)
                            runOnUiThread { result.success(null) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("encrypt_failed", e.message, null)
                            }
                        }
                    }
                }
                "decryptFileGcmChunked" -> {
                    val cipherPath = call.argument<String>("cipherPath")
                    val destPath = call.argument<String>("destPath")
                    val key = call.argument<ByteArray>("key")
                    val aadPrefix = call.argument<ByteArray>("aadPrefix") ?: ByteArray(0)
                    if (cipherPath.isNullOrEmpty() || destPath.isNullOrEmpty() || key == null) {
                        result.error("bad_args", "decryptFileGcmChunked: missing argument", null)
                        return@setMethodCallHandler
                    }
                    vaultCryptoExecutor.execute {
                        try {
                            VaultAesFileEncrypt.decryptFileGcmChunked(cipherPath, destPath, key, aadPrefix)
                            runOnUiThread { result.success(null) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("decrypt_failed", e.message, null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.resendeghf.notes/pdf_stroke_overlay",
        ).setMethodCallHandler { call, result ->
            if (call.method == "getPageCount") {
                val path = call.argument<String>("path")
                if (path.isNullOrEmpty()) {
                    result.error("bad_args", "Missing path", null)
                    return@setMethodCallHandler
                }
                pdfBoxExecutor.execute {
                    try {
                        val count = PdfStrokeOverlay.getPageCount(path)
                        runOnUiThread { result.success(count) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("getPageCount_failed", e.message, null)
                        }
                    }
                }
                return@setMethodCallHandler
            }
            if (call.method == "setBookmarks") {
                val sourcePath = call.argument<String>("sourcePath")
                val outputPath = call.argument<String>("outputPath")
                @Suppress("UNCHECKED_CAST")
                val outlinesRaw = call.argument<List<Map<String, Any>>>("outlines")
                if (sourcePath.isNullOrEmpty() || outputPath.isNullOrEmpty() || outlinesRaw == null) {
                    result.error(
                        "bad_args",
                        "setBookmarks: missing sourcePath, outputPath, or outlines",
                        null,
                    )
                    return@setMethodCallHandler
                }
                pdfBoxExecutor.execute {
                    try {
                        PdfStrokeOverlay.setBookmarks(sourcePath, outputPath, outlinesRaw)
                        runOnUiThread { result.success(outputPath) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("setBookmarks_failed", e.message, null)
                        }
                    }
                }
                return@setMethodCallHandler
            }
            if (call.method == "stamp") {
                val basePath = call.argument<String>("basePath")
                val overlayPath = call.argument<String>("overlayPath")
                val outputPath = call.argument<String>("outputPath")
                if (basePath.isNullOrEmpty() || overlayPath.isNullOrEmpty() || outputPath.isNullOrEmpty()) {
                    result.error("bad_args", "Missing basePath, overlayPath, or outputPath", null)
                    return@setMethodCallHandler
                }
                pdfBoxExecutor.execute {
                    try {
                        PdfStrokeOverlay.stamp(basePath, overlayPath, outputPath)
                        runOnUiThread { result.success(outputPath) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("stamp_failed", e.message, null)
                        }
                    }
                }
                return@setMethodCallHandler
            }
            if (call.method == "stampPngOverlay") {
                val basePath = call.argument<String>("basePath")
                val pngPath = call.argument<String>("pngPath")
                val outputPath = call.argument<String>("outputPath")
                val widthPt = call.argument<Number>("pageWidthPt")
                val heightPt = call.argument<Number>("pageHeightPt")
                val darken = call.argument<Boolean>("darkenBlend") ?: true
                if (basePath.isNullOrEmpty() || pngPath.isNullOrEmpty() ||
                    outputPath.isNullOrEmpty() || widthPt == null || heightPt == null
                ) {
                    result.error("bad_args", "stampPngOverlay: missing arguments", null)
                    return@setMethodCallHandler
                }
                pdfBoxExecutor.execute {
                    try {
                        PdfStrokeOverlay.stampPngOverlay(
                            basePath,
                            pngPath,
                            outputPath,
                            widthPt.toFloat(),
                            heightPt.toFloat(),
                            darken,
                        )
                        runOnUiThread { result.success(outputPath) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("stamp_png_failed", e.message, null)
                        }
                    }
                }
                return@setMethodCallHandler
            }
            if (call.method == "extractPageRange") {
                val sourcePath = call.argument<String>("sourcePath")
                val start = call.argument<Int>("startPage0")
                val end = call.argument<Int>("endPage0Inclusive")
                val outputPath = call.argument<String>("outputPath")
                if (sourcePath.isNullOrEmpty() || outputPath.isNullOrEmpty() || start == null || end == null) {
                    result.error("bad_args", "Missing extractPageRange arguments", null)
                    return@setMethodCallHandler
                }
                pdfBoxExecutor.execute {
                    try {
                        PdfStrokeOverlay.extractPageRangeInclusive(sourcePath, start, end, outputPath)
                        runOnUiThread { result.success(outputPath) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("extract_failed", e.message, null)
                        }
                    }
                }
                return@setMethodCallHandler
            }
            if (call.method == "exportInPlaceStamps") {
                val sourcePath = call.argument<String>("sourcePath")
                val outputPath = call.argument<String>("outputPath")
                @Suppress("UNCHECKED_CAST")
                val stampsRaw = call.argument<List<Map<String, Any>>>("stamps")
                if (sourcePath.isNullOrEmpty() || outputPath.isNullOrEmpty() ||
                    stampsRaw.isNullOrEmpty()
                ) {
                    result.error(
                        "bad_args",
                        "exportInPlaceStamps: missing sourcePath, outputPath, or stamps",
                        null,
                    )
                    return@setMethodCallHandler
                }
                pdfBoxExecutor.execute {
                    try {
                        PdfStrokeOverlay.exportInPlaceStamps(sourcePath, outputPath, stampsRaw)
                        runOnUiThread { result.success(outputPath) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("export_inplace_failed", e.message, null)
                        }
                    }
                }
                return@setMethodCallHandler
            }
            if (call.method == "exportInPlaceStampsMerged") {
                val sourcePath = call.argument<String>("sourcePath")
                val outputPath = call.argument<String>("outputPath")
                val mergedPath = call.argument<String>("mergedOverlayPath")
                @Suppress("UNCHECKED_CAST")
                val jobsRaw = call.argument<List<Map<String, Any>>>("jobs")
                if (sourcePath.isNullOrEmpty() || outputPath.isNullOrEmpty() ||
                    mergedPath.isNullOrEmpty() || jobsRaw.isNullOrEmpty()
                ) {
                    result.error(
                        "bad_args",
                        "exportInPlaceStampsMerged: missing path arguments or jobs",
                        null,
                    )
                    return@setMethodCallHandler
                }
                pdfBoxExecutor.execute {
                    try {
                        PdfStrokeOverlay.exportInPlaceStampsMergedOverlay(
                            sourcePath,
                            outputPath,
                            mergedPath,
                            jobsRaw,
                        )
                        runOnUiThread { result.success(outputPath) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("export_inplace_merged_failed", e.message, null)
                        }
                    }
                }
                return@setMethodCallHandler
            }
            if (call.method == "exportFromRecipe") {
                val sourcePath = call.argument<String>("sourcePath")
                val outputPath = call.argument<String>("outputPath")
                @Suppress("UNCHECKED_CAST")
                val opsRaw = call.argument<List<Map<String, Any>>>("ops")
                if (sourcePath.isNullOrEmpty() || outputPath.isNullOrEmpty() || opsRaw.isNullOrEmpty()) {
                    result.error("bad_args", "exportFromRecipe: missing sourcePath, outputPath, or ops", null)
                    return@setMethodCallHandler
                }
                pdfBoxExecutor.execute {
                    try {
                        PdfStrokeOverlay.exportFromRecipe(sourcePath, outputPath, opsRaw)
                        runOnUiThread { result.success(outputPath) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("export_recipe_failed", e.message, null)
                        }
                    }
                }
                return@setMethodCallHandler
            }
            if (call.method == "extractPageRangesBatch") {
                val sourcePath = call.argument<String>("sourcePath")
                @Suppress("UNCHECKED_CAST")
                val jobsRaw = call.argument<List<Map<String, Any>>>("jobs")
                if (sourcePath.isNullOrEmpty() || jobsRaw.isNullOrEmpty()) {
                    result.error("bad_args", "extractPageRangesBatch: missing sourcePath or jobs", null)
                    return@setMethodCallHandler
                }
                val jobs = ArrayList<Triple<Int, Int, String>>(jobsRaw.size)
                for (m in jobsRaw) {
                    val startAny = m["startPage0"]
                    val endAny = m["endPage0Inclusive"]
                    val out = m["outputPath"] as? String
                    if (startAny == null || endAny == null || out.isNullOrEmpty()) {
                        result.error("bad_args", "extractPageRangesBatch: bad job entry", null)
                        return@setMethodCallHandler
                    }
                    val start = (startAny as Number).toInt()
                    val end = (endAny as Number).toInt()
                    jobs.add(Triple(start, end, out))
                }
                pdfBoxExecutor.execute {
                    try {
                        PdfStrokeOverlay.extractPageRangesSingleLoad(sourcePath, jobs)
                        runOnUiThread { result.success(true) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("extract_batch_failed", e.message, null)
                        }
                    }
                }
                return@setMethodCallHandler
            }
            if (call.method == "mergePdfs") {
                val paths = call.argument<List<String>>("paths")
                val outputPath = call.argument<String>("outputPath")
                if (paths.isNullOrEmpty() || outputPath.isNullOrEmpty()) {
                    result.error("bad_args", "mergePdfs: missing paths or outputPath", null)
                    return@setMethodCallHandler
                }
                pdfBoxExecutor.execute {
                    try {
                        PdfStrokeOverlay.mergePdfFilesOrdered(paths, outputPath)
                        runOnUiThread { result.success(outputPath) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("merge_failed", e.message, null)
                        }
                    }
                }
                return@setMethodCallHandler
            }
            if (call.method == "encodeStrokeOverlay") {
                val blobPath = call.argument<String>("blobPath")
                val outputPath = call.argument<String>("outputPath")
                if (blobPath.isNullOrEmpty() || outputPath.isNullOrEmpty()) {
                    result.error(
                        "bad_args",
                        "encodeStrokeOverlay: missing blobPath or outputPath",
                        null,
                    )
                    return@setMethodCallHandler
                }
                pdfBoxExecutor.execute {
                    try {
                        PdfStrokeOverlay.encodeStrokeOverlayFromBlob(blobPath, outputPath)
                        runOnUiThread { result.success(outputPath) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("encode_stroke_overlay_failed", e.message, null)
                        }
                    }
                }
                return@setMethodCallHandler
            }
            if (call.method == "encodeStrokeOverlayBytes") {
                val blob = call.argument<ByteArray>("blob")
                if (blob == null || blob.isEmpty()) {
                    result.error(
                        "bad_args",
                        "encodeStrokeOverlayBytes: missing blob",
                        null,
                    )
                    return@setMethodCallHandler
                }
                pdfBoxExecutor.execute {
                    try {
                        val pdf = PdfStrokeOverlay.encodeStrokeOverlayFromBlobBytes(blob)
                        runOnUiThread { result.success(pdf) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("encode_stroke_overlay_failed", e.message, null)
                        }
                    }
                }
                return@setMethodCallHandler
            }
            result.notImplemented()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        if (intent.getIntExtra("org.chromium.chrome.extra.TASK_ID", -1) == this.taskId) {
            this.finish()
            intent.addFlags(FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
        }
        super.onCreate(savedInstanceState)
        MemlockLimiter.raiseBestEffort()

        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }

        // Prefer a shorter input→photon path for ink. When battery saver caps
        // the panel at 60 Hz this still drops compositor post-processing delay;
        // Dart-side DisplayInkFeel then boosts stroke prediction for the rest.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setPreferMinimalPostProcessing(true)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Do not ask the system to further throttle frames for power while
            // the editor is interactive — battery saver already sets the cap.
            @Suppress("NewApi")
            try {
                val method = window.javaClass.getMethod(
                    "setFrameRatePowerSavingsBalanced",
                    Boolean::class.javaPrimitiveType,
                )
                method.invoke(window, false)
            } catch (_: Throwable) {
                // Optional API — ignore on OEM builds that strip it.
            }
        }

        val windowInsetsController = WindowCompat.getInsetsController(window, window.decorView)
        windowInsetsController.isAppearanceLightNavigationBars = true
    }
}
