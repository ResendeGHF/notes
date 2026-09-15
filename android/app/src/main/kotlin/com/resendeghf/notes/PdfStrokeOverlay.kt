package com.resendeghf.notes

import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.multipdf.LayerUtility
import com.tom_roush.pdfbox.multipdf.PDFMergerUtility
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.graphics.form.PDFormXObject
import com.tom_roush.pdfbox.pdmodel.graphics.blend.BlendMode
import com.tom_roush.pdfbox.pdmodel.graphics.image.PDImageXObject
import com.tom_roush.pdfbox.pdmodel.graphics.state.PDExtendedGraphicsState
import com.tom_roush.pdfbox.util.Matrix
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/** Upper bound per PDFBox extract job (export batching stays under this). */
private const val MAX_PAGES_PER_EXTRACT_JOB = 2048

/**
 * Pdfrx / Flutter use the crop region's width×height as the logical PDF page size for backgrounds.
 * Overlays are authored in that rectangle but must be placed at the crop box lower-left
 * in page user space (media box origin is often (0,0) while the visible region is inset).
 */
private fun concatCropBoxOrigin(cs: PDPageContentStream, page: PDPage) {
    val crop = page.cropBox
    cs.transform(Matrix(1f, 0f, 0f, 1f, crop.lowerLeftX, crop.lowerLeftY))
}

/**
 * Persist edits to a PDF that was loaded from [scratchFile].
 * [saveIncremental] appends a revision instead of rewriting the entire file — critical for
 * large textbooks — and falls back to a full save if incremental is not possible.
 */
private fun saveDocAfterInPlaceEdits(
    doc: PDDocument,
    scratchFile: File,
    outputFile: File,
    tempParent: File,
) {
    try {
        FileOutputStream(scratchFile, true).use { fos ->
            doc.saveIncremental(fos)
        }
        Files.move(
            scratchFile.toPath(),
            outputFile.toPath(),
            StandardCopyOption.REPLACE_EXISTING,
        )
    } catch (_: Exception) {
        val tmpSaved = File.createTempFile("saber_inplace_full_", ".pdf", tempParent)
        try {
            doc.save(tmpSaved)
            Files.move(
                tmpSaved.toPath(),
                outputFile.toPath(),
                StandardCopyOption.REPLACE_EXISTING,
            )
        } finally {
            if (tmpSaved.exists()) tmpSaved.delete()
        }
    }
}

/**
 * Always rewrites the full PDF. Use when [saveIncremental] produces a structurally valid but
 * visually incomplete file (e.g. many [PDFormXObject] stamps: file grows ~2× but ink missing).
 */
private fun saveDocAfterInPlaceEditsFull(
    doc: PDDocument,
    outputFile: File,
    tempParent: File,
) {
    val tmpSaved = File.createTempFile("saber_inplace_full_", ".pdf", tempParent)
    try {
        doc.save(tmpSaved)
        Files.move(
            tmpSaved.toPath(),
            outputFile.toPath(),
            StandardCopyOption.REPLACE_EXISTING,
        )
    } finally {
        if (tmpSaved.exists()) tmpSaved.delete()
    }
}

internal object PdfStrokeOverlay {

    /** Fast page count for export fast-paths (temp-file-backed load, no full render). */
    @Throws(Exception::class)
    fun getPageCount(sourcePath: String): Int {
        PDDocument.load(File(sourcePath), MemoryUsageSetting.setupTempFileOnly()).use {
            return it.numberOfPages
        }
    }

    /**
     * Replaces the document outline with [outlines] (trees of
     * `{ title: String, pageIndex: Int, children?: List }`), writing to
     * [outputPath]. [sourcePath] may equal [outputPath].
     */
    @Throws(Exception::class)
    fun setBookmarks(
        sourcePath: String,
        outputPath: String,
        outlines: List<Map<String, Any>>,
    ) {
        val src = File(sourcePath)
        val out = File(outputPath)
        val parent = out.parentFile
            ?: throw IllegalArgumentException("setBookmarks: bad outputPath")
        if (!parent.exists()) parent.mkdirs()

        val writeToTemp = src.canonicalPath == out.canonicalPath
        val destFile = if (writeToTemp) {
            File(parent, "saber_bookmarks_${System.nanoTime()}.pdf")
        } else {
            out
        }

        PDDocument.load(src, MemoryUsageSetting.setupTempFileOnly()).use { doc ->
            val root = com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.outline.PDDocumentOutline()
            doc.documentCatalog.documentOutline = root

            fun addItems(
                parentNode: com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.outline.PDOutlineNode,
                items: List<Map<String, Any>>,
            ) {
                for (raw in items) {
                    val title = raw["title"] as? String
                        ?: throw IllegalArgumentException("setBookmarks: missing title")
                    val pageIndexAny = raw["pageIndex"]
                        ?: throw IllegalArgumentException("setBookmarks: missing pageIndex")
                    val pageIndex = (pageIndexAny as Number).toInt()
                    @Suppress("UNCHECKED_CAST")
                    val children = raw["children"] as? List<Map<String, Any>>

                    val item = com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.outline.PDOutlineItem()
                    item.title = title
                    if (pageIndex in 0 until doc.numberOfPages) {
                        val dest = com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.destination.PDPageFitDestination()
                        dest.setPage(doc.getPage(pageIndex))
                        item.destination = dest
                    }
                    parentNode.addLast(item)
                    if (!children.isNullOrEmpty()) {
                        addItems(item, children)
                    }
                }
            }

            if (outlines.isNotEmpty()) {
                addItems(root, outlines)
            }
            doc.save(destFile)
        }

        if (writeToTemp) {
            Files.move(
                destFile.toPath(),
                out.toPath(),
                StandardCopyOption.REPLACE_EXISTING,
            )
        }
    }

    @Throws(Exception::class)
    fun stamp(basePath: String, overlayPath: String, outputPath: String) {
        PDDocument.load(File(basePath), MemoryUsageSetting.setupTempFileOnly()).use { baseDoc ->
            PDDocument.load(File(overlayPath), MemoryUsageSetting.setupTempFileOnly())
                .use { overlayDoc ->
                    if (baseDoc.numberOfPages < 1 || overlayDoc.numberOfPages < 1) {
                        throw IllegalArgumentException("PDF base and overlay need at least one page")
                    }
                    val basePage = baseDoc.getPage(0)
                    val layer = LayerUtility(baseDoc)
                    layer.wrapInSaveRestore(basePage)
                    val form = layer.importPageAsForm(overlayDoc, 0)
                    PDPageContentStream(
                        baseDoc,
                        basePage,
                        PDPageContentStream.AppendMode.APPEND,
                        true,
                        true,
                    ).use { cs ->
                        cs.saveGraphicsState()
                        concatCropBoxOrigin(cs, basePage)
                        cs.drawForm(form)
                        cs.restoreGraphicsState()
                    }
                    baseDoc.save(File(outputPath))
                }
        }
    }

    /**
     * Draws a full-page transparent PNG (stroke layer) above existing vector content.
     * Uses PDF Darken blend by default to approximate highlighter ink; Screen when [darkenBlend] is false.
     * Bitmap rows are top-first (PNG); CTM maps them to the page media box (y-up).
     */
    @Throws(Exception::class)
    fun stampPngOverlay(
        basePath: String,
        pngPath: String,
        outputPath: String,
        pageWidthPt: Float,
        pageHeightPt: Float,
        darkenBlend: Boolean,
    ) {
        PDDocument.load(File(basePath), MemoryUsageSetting.setupTempFileOnly()).use { doc ->
            if (doc.numberOfPages < 1) {
                throw IllegalArgumentException("stampPngOverlay: base PDF has no pages")
            }
            val page = doc.getPage(0)
            val pngFile = File(pngPath)
            if (!pngFile.isFile) {
                throw IllegalArgumentException("stampPngOverlay: PNG missing")
            }
            val pdImage = PDImageXObject.createFromFileByExtension(pngFile, doc)
            PDPageContentStream(
                doc,
                page,
                PDPageContentStream.AppendMode.APPEND,
                true,
                true,
            ).use { cs ->
                cs.saveGraphicsState()
                val ext = PDExtendedGraphicsState()
                ext.setBlendMode(if (darkenBlend) BlendMode.DARKEN else BlendMode.SCREEN)
                cs.setGraphicsStateParameters(ext)
                concatCropBoxOrigin(cs, page)
                // PNG top-left -> PDF page with origin bottom-left
                cs.transform(Matrix(1f, 0f, 0f, -1f, 0f, pageHeightPt))
                cs.drawImage(pdImage, 0f, 0f, pageWidthPt, pageHeightPt)
                cs.restoreGraphicsState()
            }
            doc.save(File(outputPath))
        }
    }

    /**
     * Copies [startPage0]..[endPage0Inclusive] (0-based, inclusive) from [sourcePath]
     * into a new PDF at [outputPath] without re-rendering. Uses temp-only memory.
     */
    @Throws(Exception::class)
    fun extractPageRangeInclusive(
        sourcePath: String,
        startPage0: Int,
        endPage0Inclusive: Int,
        outputPath: String,
    ) {
        if (startPage0 < 0 || endPage0Inclusive < startPage0) {
            throw IllegalArgumentException("Invalid page range")
        }
        PDDocument.load(File(sourcePath), MemoryUsageSetting.setupTempFileOnly()).use { src ->
            val n = src.numberOfPages
            if (endPage0Inclusive >= n) {
                throw IllegalArgumentException("endPage0Inclusive out of bounds")
            }
            PDDocument().use { dest ->
                for (i in startPage0..endPage0Inclusive) {
                    dest.importPage(src.getPage(i))
                }
                dest.save(File(outputPath))
            }
        }
    }

    /**
     * Single PDFBox load of [sourcePath]: builds [outputPath] by applying ordered ops.
     * Op maps (from Flutter): `{ "type": "copy", "startPage0": int, "endPage0Inclusive": int }`,
     * `{ "type": "stamp", "srcPage0": int, "overlayPath": string }`, or
     * `{ "type": "stampPng", "srcPage0": int, "pngPath": string, "pageWidthPt": double, "pageHeightPt": double, "darkenBlend": bool }`.
     * Avoids reloading the source once per fragment between sparse ink pages.
     */
    @Throws(Exception::class)
    fun exportFromRecipe(
        sourcePath: String,
        outputPath: String,
        ops: List<Map<String, Any>>,
    ) {
        if (ops.isEmpty()) {
            throw IllegalArgumentException("exportFromRecipe: empty ops")
        }
        PDDocument.load(File(sourcePath), MemoryUsageSetting.setupTempFileOnly()).use { src ->
            val pageCount = src.numberOfPages
            PDDocument().use { dest ->
                var overlayCache: PDDocument? = null
                var overlayCachePath: String? = null
                val overlayFormCache = mutableMapOf<Int, PDFormXObject>()
                val destLayer = LayerUtility(dest)
                try {
                    for (raw in ops) {
                        val type = raw["type"] as? String
                            ?: throw IllegalArgumentException("exportFromRecipe: missing type")
                        when (type) {
                            "copy" -> {
                                val start = raw["startPage0"] as? Number
                                    ?: throw IllegalArgumentException("copy: startPage0")
                                val end = raw["endPage0Inclusive"] as? Number
                                    ?: throw IllegalArgumentException("copy: endPage0Inclusive")
                                val a = start.toInt()
                                val b = end.toInt()
                                if (a < 0 || b < a || b >= pageCount) {
                                    throw IllegalArgumentException("copy: bad range $a..$b (pages=$pageCount)")
                                }
                                for (i in a..b) {
                                    dest.importPage(src.getPage(i))
                                }
                            }
                            "stamp" -> {
                                val srcPage = raw["srcPage0"] as? Number
                                    ?: throw IllegalArgumentException("stamp: srcPage0")
                                val overlayPath = raw["overlayPath"] as? String
                                    ?: throw IllegalArgumentException("stamp: overlayPath")
                                val overlayPage0 = (raw["overlayPage0"] as? Number)?.toInt() ?: 0
                                val pi = srcPage.toInt()
                                if (pi < 0 || pi >= pageCount) {
                                    throw IllegalArgumentException("stamp: srcPage out of bounds $pi")
                                }
                                if (!File(overlayPath).isFile) {
                                    throw IllegalArgumentException("stamp: overlay missing $overlayPath")
                                }
                                dest.importPage(src.getPage(pi))
                                val basePage = dest.getPage(dest.numberOfPages - 1)
                                if (overlayCachePath != overlayPath) {
                                    overlayCache?.close()
                                    overlayFormCache.clear()
                                    overlayCache = PDDocument.load(
                                        File(overlayPath),
                                        MemoryUsageSetting.setupTempFileOnly(),
                                    )
                                    overlayCachePath = overlayPath
                                }
                                val overlayDoc = overlayCache
                                    ?: throw IllegalStateException("stamp: overlay cache")
                                if (overlayPage0 < 0 || overlayPage0 >= overlayDoc.numberOfPages) {
                                    throw IllegalArgumentException(
                                        "stamp: overlayPage0 out of bounds $overlayPage0",
                                    )
                                }
                                val form = overlayFormCache.getOrPut(overlayPage0) {
                                    destLayer.importPageAsForm(overlayDoc, overlayPage0)
                                }
                                destLayer.wrapInSaveRestore(basePage)
                                PDPageContentStream(
                                    dest,
                                    basePage,
                                    PDPageContentStream.AppendMode.APPEND,
                                    true,
                                    true,
                                ).use { cs ->
                                    cs.saveGraphicsState()
                                    concatCropBoxOrigin(cs, basePage)
                                    cs.drawForm(form)
                                    cs.restoreGraphicsState()
                                }
                            }
                            "stampPng" -> {
                            val srcPage0 = raw["srcPage0"] as? Number
                                ?: throw IllegalArgumentException("stampPng: srcPage0")
                            val pngPath = raw["pngPath"] as? String
                                ?: throw IllegalArgumentException("stampPng: pngPath")
                            val wPt = raw["pageWidthPt"] as? Number
                                ?: throw IllegalArgumentException("stampPng: pageWidthPt")
                            val hPt = raw["pageHeightPt"] as? Number
                                ?: throw IllegalArgumentException("stampPng: pageHeightPt")
                            val darken = raw["darkenBlend"] as? Boolean ?: true
                            val pi = srcPage0.toInt()
                            val pageWidthPt = wPt.toFloat()
                            val pageHeightPt = hPt.toFloat()
                            if (pi < 0 || pi >= pageCount) {
                                throw IllegalArgumentException("stampPng: srcPage out of bounds $pi")
                            }
                            if (!File(pngPath).isFile) {
                                throw IllegalArgumentException("stampPng: PNG missing $pngPath")
                            }
                            dest.importPage(src.getPage(pi))
                            val basePage = dest.getPage(dest.numberOfPages - 1)
                            val pdImage = PDImageXObject.createFromFileByExtension(File(pngPath), dest)
                            PDPageContentStream(
                                dest,
                                basePage,
                                PDPageContentStream.AppendMode.APPEND,
                                true,
                                true,
                            ).use { cs ->
                                cs.saveGraphicsState()
                                val ext = PDExtendedGraphicsState()
                                ext.setBlendMode(if (darken) BlendMode.DARKEN else BlendMode.SCREEN)
                                cs.setGraphicsStateParameters(ext)
                                concatCropBoxOrigin(cs, basePage)
                                cs.transform(Matrix(1f, 0f, 0f, -1f, 0f, pageHeightPt))
                                cs.drawImage(pdImage, 0f, 0f, pageWidthPt, pageHeightPt)
                                cs.restoreGraphicsState()
                            }
                        }
                        else -> throw IllegalArgumentException("exportFromRecipe: unknown type $type")
                    }
                }
                    dest.save(File(outputPath))
                } finally {
                    overlayCache?.close()
                }
            }
        }
    }

    /**
     * When export order matches the source file (page *k* of output is source page *k*),
     * copies [sourcePath] to [outputPath] then stamps only the given pages. Avoids
     * thousands of [PDDocument.importPage] calls for large textbooks.
     *
     * [stamps] entries match [exportFromRecipe] `stamp` / `stampPng` maps (`srcPage0`, paths, dims).
     */
    @Throws(Exception::class)
    fun exportInPlaceStamps(
        sourcePath: String,
        outputPath: String,
        stamps: List<Map<String, Any>>,
    ) {
        if (stamps.isEmpty()) {
            throw IllegalArgumentException("exportInPlaceStamps: empty stamps")
        }
        val src = File(sourcePath)
        val out = File(outputPath)
        val parent = out.parentFile ?: throw IllegalArgumentException("exportInPlaceStamps: bad outputPath")
        parent.mkdirs()
        val scratch = File.createTempFile("saber_inplace_", ".pdf", parent)
        try {
            Files.copy(src.toPath(), scratch.toPath(), StandardCopyOption.REPLACE_EXISTING)
            PDDocument.load(scratch, MemoryUsageSetting.setupTempFileOnly()).use { doc ->
                var overlayCache: PDDocument? = null
                var overlayCachePath: String? = null
                val overlayFormCache = mutableMapOf<Int, PDFormXObject>()
                val destLayer = LayerUtility(doc)
                try {
                    val n = doc.numberOfPages
                    for (raw in stamps) {
                        val type = raw["type"] as? String
                            ?: throw IllegalArgumentException("exportInPlaceStamps: missing type")
                        when (type) {
                            "stamp" -> {
                                val srcPage0 = raw["srcPage0"] as? Number
                                    ?: throw IllegalArgumentException("stamp: srcPage0")
                                val overlayPath = raw["overlayPath"] as? String
                                    ?: throw IllegalArgumentException("stamp: overlayPath")
                                val overlayPage0 = (raw["overlayPage0"] as? Number)?.toInt() ?: 0
                                val pi = srcPage0.toInt()
                                if (pi < 0 || pi >= n) {
                                    throw IllegalArgumentException("stamp: srcPage out of bounds $pi")
                                }
                                if (!File(overlayPath).isFile) {
                                    throw IllegalArgumentException("stamp: overlay missing")
                                }
                                if (overlayCachePath != overlayPath) {
                                    overlayCache?.close()
                                    overlayFormCache.clear()
                                    overlayCache = PDDocument.load(
                                        File(overlayPath),
                                        MemoryUsageSetting.setupTempFileOnly(),
                                    )
                                    overlayCachePath = overlayPath
                                }
                                val overlayDoc = overlayCache
                                    ?: throw IllegalStateException("stamp: overlay cache")
                                if (overlayPage0 < 0 || overlayPage0 >= overlayDoc.numberOfPages) {
                                    throw IllegalArgumentException(
                                        "stamp: overlayPage0 out of bounds $overlayPage0",
                                    )
                                }
                                val basePage = doc.getPage(pi)
                                val form = overlayFormCache.getOrPut(overlayPage0) {
                                    destLayer.importPageAsForm(overlayDoc, overlayPage0)
                                }
                                destLayer.wrapInSaveRestore(basePage)
                                PDPageContentStream(
                                    doc,
                                    basePage,
                                    PDPageContentStream.AppendMode.APPEND,
                                    true,
                                    true,
                                ).use { cs ->
                                    cs.saveGraphicsState()
                                    concatCropBoxOrigin(cs, basePage)
                                    cs.drawForm(form)
                                    cs.restoreGraphicsState()
                                }
                            }
                            "stampPng" -> {
                            val srcPage0 = raw["srcPage0"] as? Number
                                ?: throw IllegalArgumentException("stampPng: srcPage0")
                            val pngPath = raw["pngPath"] as? String
                                ?: throw IllegalArgumentException("stampPng: pngPath")
                            val wPt = raw["pageWidthPt"] as? Number
                                ?: throw IllegalArgumentException("stampPng: pageWidthPt")
                            val hPt = raw["pageHeightPt"] as? Number
                                ?: throw IllegalArgumentException("stampPng: pageHeightPt")
                            val darken = raw["darkenBlend"] as? Boolean ?: true
                            val pi = srcPage0.toInt()
                            val pageWidthPt = wPt.toFloat()
                            val pageHeightPt = hPt.toFloat()
                            if (pi < 0 || pi >= n) {
                                throw IllegalArgumentException("stampPng: srcPage out of bounds $pi")
                            }
                            if (!File(pngPath).isFile) {
                                throw IllegalArgumentException("stampPng: PNG missing")
                            }
                            val basePage = doc.getPage(pi)
                            val pdImage = PDImageXObject.createFromFileByExtension(File(pngPath), doc)
                            PDPageContentStream(
                                doc,
                                basePage,
                                PDPageContentStream.AppendMode.APPEND,
                                true,
                                true,
                            ).use { cs ->
                                cs.saveGraphicsState()
                                val ext = PDExtendedGraphicsState()
                                ext.setBlendMode(if (darken) BlendMode.DARKEN else BlendMode.SCREEN)
                                cs.setGraphicsStateParameters(ext)
                                concatCropBoxOrigin(cs, basePage)
                                cs.transform(Matrix(1f, 0f, 0f, -1f, 0f, pageHeightPt))
                                cs.drawImage(pdImage, 0f, 0f, pageWidthPt, pageHeightPt)
                                cs.restoreGraphicsState()
                            }
                        }
                        else -> throw IllegalArgumentException("exportInPlaceStamps: unknown type $type")
                    }
                    }
                    saveDocAfterInPlaceEdits(doc, scratch, out, parent)
                } finally {
                    overlayCache?.close()
                }
            }
        } finally {
            scratch.delete()
        }
    }

    /**
     * Like [exportInPlaceStamps] for vector overlays only, but loads
     * [mergedOverlayPath] once (multi-page PDF: page *i* is the ink layer for
     * job *i*) instead of opening one overlay file per stamp. Cuts native work
     * from O(stamps × open) to O(merge + 1 open) for large stamp counts.
     *
     * Each [jobs] entry: `srcPage0` (0-based page in source), `overlayPage0`
     * (0-based page in [mergedOverlayPath]).
     */
    @Throws(Exception::class)
    fun exportInPlaceStampsMergedOverlay(
        sourcePath: String,
        outputPath: String,
        mergedOverlayPath: String,
        jobs: List<Map<String, Any>>,
    ) {
        if (jobs.isEmpty()) {
            throw IllegalArgumentException("exportInPlaceStampsMergedOverlay: empty jobs")
        }
        val overlayFile = File(mergedOverlayPath)
        if (!overlayFile.isFile) {
            throw IllegalArgumentException("exportInPlaceStampsMergedOverlay: merged overlay missing")
        }
        val src = File(sourcePath)
        val out = File(outputPath)
        val parent = out.parentFile ?: throw IllegalArgumentException("exportInPlaceStampsMergedOverlay: bad outputPath")
        parent.mkdirs()
        val scratch = File.createTempFile("saber_inplace_m_", ".pdf", parent)
        try {
            Files.copy(src.toPath(), scratch.toPath(), StandardCopyOption.REPLACE_EXISTING)
            PDDocument.load(scratch, MemoryUsageSetting.setupTempFileOnly()).use { doc ->
                val n = doc.numberOfPages
                val destLayer = LayerUtility(doc)
                val overlayFormCache = mutableMapOf<Int, PDFormXObject>()
                PDDocument.load(overlayFile, MemoryUsageSetting.setupTempFileOnly()).use { overlayDoc ->
                    val overlayCount = overlayDoc.numberOfPages
                    for (raw in jobs) {
                        val srcPage0Any = raw["srcPage0"] ?: throw IllegalArgumentException("job: srcPage0")
                        val overlayPage0Any = raw["overlayPage0"] ?: throw IllegalArgumentException("job: overlayPage0")
                        val pi = (srcPage0Any as Number).toInt()
                        val oi = (overlayPage0Any as Number).toInt()
                        if (pi < 0 || pi >= n) {
                            throw IllegalArgumentException("job: srcPage out of bounds $pi")
                        }
                        if (oi < 0 || oi >= overlayCount) {
                            throw IllegalArgumentException("job: overlayPage out of bounds $oi (pages=$overlayCount)")
                        }
                        val basePage = doc.getPage(pi)
                        val form = overlayFormCache.getOrPut(oi) {
                            destLayer.importPageAsForm(overlayDoc, oi)
                        }
                        destLayer.wrapInSaveRestore(basePage)
                        PDPageContentStream(
                            doc,
                            basePage,
                            PDPageContentStream.AppendMode.APPEND,
                            true,
                            true,
                        ).use { cs ->
                            cs.saveGraphicsState()
                            concatCropBoxOrigin(cs, basePage)
                            cs.drawForm(form)
                            cs.restoreGraphicsState()
                        }
                    }
                    // Keep [overlayDoc] open until after save: forms from
                    // [importPageAsForm] may reference the overlay COS until embedded.
                    // Full save: incremental updates here often ~double file size without
                    // visible ink (xref / XObject linkage); full rewrite is slower but correct.
                    saveDocAfterInPlaceEditsFull(doc, out, parent)
                }
            }
        } finally {
            scratch.delete()
        }
    }

    /**
     * Opens [sourcePath] once and writes each contiguous range to its output file
     * (stream copy). Jobs must be non-overlapping and in ascending page order.
     */
    @Throws(Exception::class)
    fun extractPageRangesSingleLoad(
        sourcePath: String,
        jobs: List<Triple<Int, Int, String>>,
    ) {
        if (jobs.isEmpty()) {
            throw IllegalArgumentException("extractPageRangesSingleLoad: empty jobs")
        }
        PDDocument.load(File(sourcePath), MemoryUsageSetting.setupTempFileOnly()).use { src ->
            val pageCount = src.numberOfPages
            for ((startPage0, endPage0Inclusive, outputPath) in jobs) {
                if (startPage0 < 0 || endPage0Inclusive < startPage0) {
                    throw IllegalArgumentException("Invalid page range")
                }
                if (endPage0Inclusive >= pageCount) {
                    throw IllegalArgumentException("endPage0Inclusive out of bounds")
                }
                val span = endPage0Inclusive - startPage0 + 1
                if (span > MAX_PAGES_PER_EXTRACT_JOB) {
                    throw IllegalArgumentException("extract job exceeds max pages ($span > $MAX_PAGES_PER_EXTRACT_JOB)")
                }
                PDDocument().use { dest ->
                    for (i in startPage0..endPage0Inclusive) {
                        dest.importPage(src.getPage(i))
                    }
                    dest.save(File(outputPath))
                }
            }
        }
    }

    private fun mergePdfTwoFiles(a: String, b: String, outputPath: String) {
        val merger = PDFMergerUtility()
        merger.addSource(File(a))
        merger.addSource(File(b))
        merger.setDestinationFileName(outputPath)
        merger.mergeDocuments(MemoryUsageSetting.setupTempFileOnly())
    }

    /**
     * Merges PDFs in page order. Uses pairwise merging when there are more than two inputs
     * so PDFBox never attaches dozens of sources at once (lower peak RAM / less UI impact
     * when invoked from a background thread).
     */
    @Throws(Exception::class)
    fun mergePdfFilesOrdered(inputPaths: List<String>, outputPath: String) {
        if (inputPaths.isEmpty()) {
            throw IllegalArgumentException("mergePdfFilesOrdered: no inputs")
        }
        if (inputPaths.size == 1) {
            Files.copy(
                File(inputPaths[0]).toPath(),
                File(outputPath).toPath(),
                StandardCopyOption.REPLACE_EXISTING,
            )
            return
        }
        if (inputPaths.size == 2) {
            mergePdfTwoFiles(inputPaths[0], inputPaths[1], outputPath)
            return
        }
        var layer = inputPaths.toMutableList()
        val parent = File(outputPath).parentFile
            ?: throw IllegalArgumentException("mergePdfFilesOrdered: invalid outputPath parent")
        while (layer.size > 1) {
            val next = ArrayList<String>((layer.size + 1) / 2)
            var i = 0
            while (i < layer.size) {
                if (i + 1 >= layer.size) {
                    next.add(layer[i])
                    i++
                } else {
                    val dest =
                        if (layer.size == 2) outputPath
                        else File.createTempFile("saber_mrg_", ".pdf", parent).absolutePath
                    mergePdfTwoFiles(layer[i], layer[i + 1], dest)
                    File(layer[i]).delete()
                    File(layer[i + 1]).delete()
                    next.add(dest)
                    i += 2
                }
            }
            layer = next
        }
    }

    private const val FLAG_FILL = 1
    private const val FLAG_HIGHLIGHTER = 1 shl 1
    private const val FLAG_SCREEN_BLEND = 1 shl 3

    /**
     * Builds a multi-page transparent PDF of filled stroke polygons from a
     * packed binary blob (Flutter [PdfStrokeVectorEncoder.packNativeOverlayBlob]).
     * Avoids Dart package:pdf SVG encode for dense handwriting overlays.
     */
    @Throws(Exception::class)
    fun encodeStrokeOverlayFromBlobBytes(bytes: ByteArray): ByteArray {
        if (bytes.size < 12) {
            throw IllegalArgumentException("encodeStrokeOverlayFromBlob: blob too small")
        }
        val magic = byteArrayOf(
            0x53, 0x42, 0x52, 0x4B, 0x4F, 0x56, 0x30, 0x31,
        )
        for (i in magic.indices) {
            if (bytes[i] != magic[i]) {
                throw IllegalArgumentException("encodeStrokeOverlayFromBlob: bad magic")
            }
        }
        val buf = java.nio.ByteBuffer.wrap(bytes).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        buf.position(8)
        val pageCount = buf.int
        if (pageCount < 0 || pageCount > 100_000) {
            throw IllegalArgumentException("encodeStrokeOverlayFromBlob: bad pageCount $pageCount")
        }

        val baos = java.io.ByteArrayOutputStream()
        PDDocument().use { doc ->
            repeat(pageCount) {
                val width = buf.float
                val height = buf.float
                val tx = buf.float
                val ty = buf.float
                val sx = buf.float
                val sy = buf.float
                if (width <= 0f || height <= 0f) {
                    throw IllegalArgumentException("encodeStrokeOverlayFromBlob: bad page size")
                }
                val page = PDPage(
                    com.tom_roush.pdfbox.pdmodel.common.PDRectangle(width, height),
                )
                doc.addPage(page)
                val strokeCount = buf.int
                if (strokeCount < 0 || strokeCount > 1_000_000) {
                    throw IllegalArgumentException("encodeStrokeOverlayFromBlob: bad strokeCount")
                }
                if (strokeCount == 0) return@repeat

                PDPageContentStream(
                    doc,
                    page,
                    PDPageContentStream.AppendMode.OVERWRITE,
                    true,
                    true,
                ).use { cs ->
                    // Match Dart CTM: flipY * scale * translate
                    // x' = sx*(x - tx)
                    // y' = height - sy*(y - ty)
                    cs.transform(
                        Matrix(
                            sx,
                            0f,
                            0f,
                            -sy,
                            -sx * tx,
                            height + sy * ty,
                        ),
                    )

                    var gsOpen = false
                    var lastFlags = 0
                    var lastArgb = 0
                    var lastOpacity = -1f
                    repeat(strokeCount) {
                        val flags = buf.int
                        val argb = buf.int
                        val opacity = buf.float.coerceIn(0f, 1f)
                        val pointCount = buf.int
                        if (pointCount < 0 || pointCount > 5_000_000) {
                            throw IllegalArgumentException(
                                "encodeStrokeOverlayFromBlob: bad pointCount",
                            )
                        }
                        val a = ((argb ushr 24) and 0xff) / 255f
                        val r = ((argb ushr 16) and 0xff) / 255f
                        val g = ((argb ushr 8) and 0xff) / 255f
                        val b = (argb and 0xff) / 255f
                        val effectiveOpacity = if (a > 0f && a < 1f) a * opacity else opacity

                        if (pointCount < 2) {
                            // Skip points still need to be consumed.
                            buf.position(buf.position() + pointCount * 8)
                            return@repeat
                        }

                        val reuseGs =
                            gsOpen &&
                                flags == lastFlags &&
                                argb == lastArgb &&
                                opacity == lastOpacity
                        if (!reuseGs) {
                            if (gsOpen) cs.restoreGraphicsState()
                            cs.saveGraphicsState()
                            val ext = PDExtendedGraphicsState()
                            if (effectiveOpacity < 0.999f) {
                                ext.setNonStrokingAlphaConstant(effectiveOpacity)
                                ext.setStrokingAlphaConstant(effectiveOpacity)
                            }
                            if ((flags and FLAG_HIGHLIGHTER) != 0) {
                                ext.setBlendMode(
                                    if ((flags and FLAG_SCREEN_BLEND) != 0) {
                                        BlendMode.SCREEN
                                    } else {
                                        BlendMode.DARKEN
                                    },
                                )
                            }
                            cs.setGraphicsStateParameters(ext)
                            cs.setNonStrokingColor(r, g, b)
                            gsOpen = true
                            lastFlags = flags
                            lastArgb = argb
                            lastOpacity = opacity
                        }

                        val x0 = buf.float
                        val y0 = buf.float
                        cs.moveTo(x0, y0)
                        for (i in 1 until pointCount) {
                            cs.lineTo(buf.float, buf.float)
                        }
                        cs.closePath()
                        if ((flags and FLAG_FILL) != 0) {
                            cs.fill()
                        } else {
                            cs.stroke()
                        }
                    }
                    if (gsOpen) cs.restoreGraphicsState()
                }
            }
            doc.save(baos)
        }
        return baos.toByteArray()
    }

    @Throws(Exception::class)
    fun encodeStrokeOverlayFromBlob(blobPath: String, outputPath: String) {
        val blobFile = File(blobPath)
        if (!blobFile.isFile) {
            throw IllegalArgumentException("encodeStrokeOverlayFromBlob: blob missing")
        }
        val pdfBytes = encodeStrokeOverlayFromBlobBytes(blobFile.readBytes())
        val out = File(outputPath)
        val parent = out.parentFile
            ?: throw IllegalArgumentException("encodeStrokeOverlayFromBlob: bad outputPath")
        parent.mkdirs()
        out.writeBytes(pdfBytes)
    }
}
