// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

package com.resendeghf.notes

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.SecureRandom
import java.util.zip.Deflater
import java.util.zip.Inflater
import javax.crypto.Cipher
import javax.crypto.CipherInputStream
import javax.crypto.CipherOutputStream
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Streaming AES helpers for vault blobs.
 *
 * CBC matches legacy Dart [VaultAdapter] / PointyCastle output.
 * GCM is vault blob format v2 (AEAD, hardware-accelerated on aarch64).
 */
object VaultAesFileEncrypt {
    private const val BUFFER = 4 * 1024 * 1024
    private const val GCM_TAG_BITS = 128
    private const val GCM_NONCE_BYTES = 12
    const val GCM_CHUNK_BYTES = 1 * 1024 * 1024

    @JvmStatic
    fun encryptFileCbc(sourcePath: String, destPath: String, key: ByteArray, iv: ByteArray) {
        require(iv.size == 16) { "IV must be 16 bytes" }
        require(key.size == 16 || key.size == 24 || key.size == 32) { "Invalid AES key length" }

        val destFile = File(destPath)
        destFile.parentFile?.mkdirs()

        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        val secretKey = SecretKeySpec(key, "AES")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey, IvParameterSpec(iv))

        try {
            FileInputStream(File(sourcePath)).use { fis ->
                FileOutputStream(destFile).use { fos ->
                    CipherOutputStream(fos, cipher).use { cos ->
                        fis.copyTo(cos, BUFFER)
                    }
                }
            }
        } catch (e: Exception) {
            if (destFile.exists()) {
                destFile.delete()
            }
            throw e
        }
    }

    @JvmStatic
    fun decryptFileCbc(cipherPath: String, destPath: String, key: ByteArray, iv: ByteArray) {
        require(iv.size == 16) { "IV must be 16 bytes" }
        require(key.size == 16 || key.size == 24 || key.size == 32) { "Invalid AES key length" }

        val destFile = File(destPath)
        destFile.parentFile?.mkdirs()

        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        val secretKey = SecretKeySpec(key, "AES")
        cipher.init(Cipher.DECRYPT_MODE, secretKey, IvParameterSpec(iv))

        try {
            FileInputStream(File(cipherPath)).use { fis ->
                CipherInputStream(fis, cipher).use { cis ->
                    FileOutputStream(destFile).use { fos ->
                        cis.copyTo(fos, BUFFER)
                    }
                }
            }
        } catch (e: Exception) {
            if (destFile.exists()) {
                destFile.delete()
            }
            throw e
        }
    }

    @JvmStatic
    fun encryptBytesToFileCbc(destPath: String, plaintext: ByteArray, key: ByteArray, iv: ByteArray) {
        require(iv.size == 16) { "IV must be 16 bytes" }
        require(key.size == 16 || key.size == 24 || key.size == 32) { "Invalid AES key length" }

        val destFile = File(destPath)
        destFile.parentFile?.mkdirs()

        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
        try {
            FileOutputStream(destFile).use { fos ->
                fos.write(cipher.doFinal(plaintext))
            }
        } catch (e: Exception) {
            if (destFile.exists()) destFile.delete()
            throw e
        }
    }

    @JvmStatic
    fun decryptFileToBytesCbc(cipherPath: String, key: ByteArray, iv: ByteArray): ByteArray {
        require(iv.size == 16) { "IV must be 16 bytes" }
        require(key.size == 16 || key.size == 24 || key.size == 32) { "Invalid AES key length" }

        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
        return FileInputStream(File(cipherPath)).use { fis ->
            cipher.doFinal(fis.readBytes())
        }
    }

    /**
     * Single-shot GCM: file layout = ciphertext || tag (nonce stored out-of-band).
     * Returns the 12-byte nonce used.
     */
    @JvmStatic
    fun encryptBytesToFileGcm(destPath: String, plaintext: ByteArray, key: ByteArray): ByteArray {
        require(key.size == 32) { "GCM requires 32-byte key" }
        val nonce = ByteArray(GCM_NONCE_BYTES)
        SecureRandom().nextBytes(nonce)

        val destFile = File(destPath)
        destFile.parentFile?.mkdirs()

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.ENCRYPT_MODE,
            SecretKeySpec(key, "AES"),
            GCMParameterSpec(GCM_TAG_BITS, nonce),
        )
        try {
            FileOutputStream(destFile).use { fos ->
                fos.write(cipher.doFinal(plaintext))
            }
        } catch (e: Exception) {
            if (destFile.exists()) destFile.delete()
            throw e
        }
        return nonce
    }

    /**
     * One-shot arm64 note save: optional zlib then AES-GCM to [destPath].
     * Returns 12-byte nonce. [plainSize] is the AES plaintext length (after zlib).
     */
    @JvmStatic
    fun encryptBytesToFileGcmZlib(
        destPath: String,
        plaintext: ByteArray,
        key: ByteArray,
        compressZlib: Boolean,
    ): Pair<ByteArray, Int> {
        val toEncrypt = if (compressZlib && !looksLikeZlib(plaintext)) {
            zlibCompress(plaintext)
        } else {
            plaintext
        }
        val nonce = encryptBytesToFileGcm(destPath, toEncrypt, key)
        return Pair(nonce, toEncrypt.size)
    }

    /**
     * Path-based arm64 note/PDF save: read source → optional zlib → GCM (or chunked).
     * Returns Triple(nonceOrEmpty, plainSize, cipherVer) where cipherVer is 1 or 2.
     */
    @JvmStatic
    fun encryptFileToGcmZlib(
        sourcePath: String,
        destPath: String,
        key: ByteArray,
        compressZlib: Boolean,
        aadPrefix: ByteArray,
        chunkThreshold: Int = 4 * 1024 * 1024,
    ): Triple<ByteArray, Int, Int> {
        var plain = File(sourcePath).readBytes()
        if (compressZlib && !looksLikeZlib(plain)) {
            plain = zlibCompress(plain)
        }
        if (plain.size >= chunkThreshold) {
            // Write compressed plain to a temp then chunk-encrypt.
            val tmp = File.createTempFile("vault_gcm_plain_", ".bin")
            try {
                tmp.writeBytes(plain)
                encryptFileGcmChunked(tmp.absolutePath, destPath, key, aadPrefix)
            } finally {
                tmp.delete()
            }
            return Triple(ByteArray(0), plain.size, 2)
        }
        val nonce = encryptBytesToFileGcm(destPath, plain, key)
        return Triple(nonce, plain.size, 1)
    }

    @JvmStatic
    fun decryptFileToBytesGcm(cipherPath: String, key: ByteArray, nonce: ByteArray): ByteArray {
        require(key.size == 32) { "GCM requires 32-byte key" }
        require(nonce.size == GCM_NONCE_BYTES) { "GCM nonce must be 12 bytes" }

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            SecretKeySpec(key, "AES"),
            GCMParameterSpec(GCM_TAG_BITS, nonce),
        )
        return FileInputStream(File(cipherPath)).use { fis ->
            cipher.doFinal(fis.readBytes())
        }
    }

    /** Decrypt GCM (single or chunked) and optionally zlib-inflate in one native call. */
    @JvmStatic
    fun decryptFileToBytesGcmZlib(
        cipherPath: String,
        key: ByteArray,
        nonce: ByteArray?,
        cipherVer: Int,
        aadPrefix: ByteArray,
        inflateZlib: Boolean,
    ): ByteArray {
        val aesPlain = when (cipherVer) {
            2 -> {
                val tmp = File.createTempFile("vault_gcm_dec_", ".bin")
                try {
                    decryptFileGcmChunked(cipherPath, tmp.absolutePath, key, aadPrefix)
                    tmp.readBytes()
                } finally {
                    tmp.delete()
                }
            }
            else -> {
                require(nonce != null && nonce.size == GCM_NONCE_BYTES) {
                    "GCM nonce must be 12 bytes"
                }
                decryptFileToBytesGcm(cipherPath, key, nonce)
            }
        }
        return if (inflateZlib) zlibDecompressBestEffort(aesPlain) else aesPlain
    }

    @JvmStatic
    fun looksLikeZlib(data: ByteArray): Boolean {
        if (data.size < 2) return false
        val cmf = data[0].toInt() and 0xff
        val flg = data[1].toInt() and 0xff
        return cmf == 0x78 && ((cmf shl 8) + flg) % 31 == 0
    }

    @JvmStatic
    fun zlibCompress(input: ByteArray): ByteArray {
        val deflater = Deflater(Deflater.DEFAULT_COMPRESSION, false)
        deflater.setInput(input)
        deflater.finish()
        val buf = ByteArray(8192)
        val out = ByteArrayOutputStream(input.size / 2 + 64)
        while (!deflater.finished()) {
            val n = deflater.deflate(buf)
            if (n > 0) out.write(buf, 0, n)
        }
        deflater.end()
        return out.toByteArray()
    }

    @JvmStatic
    fun zlibDecompressBestEffort(input: ByteArray): ByteArray {
        if (!looksLikeZlib(input)) return input
        return try {
            val inflater = Inflater(false)
            inflater.setInput(input)
            val buf = ByteArray(8192)
            val out = ByteArrayOutputStream(input.size * 2)
            while (!inflater.finished()) {
                val n = inflater.inflate(buf)
                if (n == 0 && inflater.needsInput()) break
                if (n > 0) out.write(buf, 0, n)
            }
            inflater.end()
            out.toByteArray()
        } catch (_: Exception) {
            input
        }
    }

    /** Peek vault blob magic: 2 = chunked GCM (SBV2), else 0. */
    @JvmStatic
    fun peekCipherVer(cipherPath: String): Int {
        val f = File(cipherPath)
        if (!f.exists() || f.length() < 5) return 0
        FileInputStream(f).use { fis ->
            val magic = ByteArray(4)
            if (fis.read(magic) != 4) return 0
            if (magic[0] == 0x53.toByte() &&
                magic[1] == 0x42.toByte() &&
                magic[2] == 0x56.toByte() &&
                magic[3] == 0x32.toByte()
            ) {
                val ver = fis.read()
                return if (ver == 2) 2 else 0
            }
        }
        return 0
    }

    /**
     * Chunked GCM for large files.
     * Layout: magic "SBV2" | ver=2 | chunkCount(u32 LE) | repeated:
     *   chunkPlainLen(u32 LE) | nonce(12) | cipherLen(u32 LE) | ciphertext||tag
     * Returns empty nonce placeholder (nonces are in-file); caller stores cipher_ver=2.
     */
    @JvmStatic
    fun encryptFileGcmChunked(sourcePath: String, destPath: String, key: ByteArray, aadPrefix: ByteArray) {
        require(key.size == 32) { "GCM requires 32-byte key" }
        val source = File(sourcePath)
        val destFile = File(destPath)
        destFile.parentFile?.mkdirs()

        val random = SecureRandom()
        val secretKey = SecretKeySpec(key, "AES")
        val plainLen = source.length()
        val chunkCount = ((plainLen + GCM_CHUNK_BYTES - 1) / GCM_CHUNK_BYTES).toInt().coerceAtLeast(1)

        try {
            FileInputStream(source).use { fis ->
                FileOutputStream(destFile).use { fos ->
                    fos.write(byteArrayOf(0x53, 0x42, 0x56, 0x32)) // SBV2
                    fos.write(2) // chunked GCM
                    fos.write(
                        ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(chunkCount).array(),
                    )

                    val buf = ByteArray(GCM_CHUNK_BYTES)
                    var chunkIndex = 0
                    var remaining = plainLen
                    while (remaining > 0 || chunkIndex == 0 && plainLen == 0L) {
                        val toRead = minOf(GCM_CHUNK_BYTES.toLong(), remaining).toInt()
                        var n = 0
                        while (n < toRead) {
                            val got = fis.read(buf, n, toRead - n)
                            if (got < 0) break
                            n += got
                        }
                        val plainChunk = if (n == buf.size) buf else buf.copyOf(n)

                        val nonce = ByteArray(GCM_NONCE_BYTES)
                        random.nextBytes(nonce)
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(
                            Cipher.ENCRYPT_MODE,
                            secretKey,
                            GCMParameterSpec(GCM_TAG_BITS, nonce),
                        )
                        val aad = aadPrefix +
                            ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(chunkIndex).array()
                        cipher.updateAAD(aad)
                        val sealed = cipher.doFinal(plainChunk)

                        fos.write(
                            ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(plainChunk.size).array(),
                        )
                        fos.write(nonce)
                        fos.write(
                            ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(sealed.size).array(),
                        )
                        fos.write(sealed)

                        remaining -= n
                        chunkIndex++
                        if (plainLen == 0L) break
                    }
                }
            }
        } catch (e: Exception) {
            if (destFile.exists()) destFile.delete()
            throw e
        }
    }

    @JvmStatic
    fun decryptFileGcmChunked(cipherPath: String, destPath: String, key: ByteArray, aadPrefix: ByteArray) {
        require(key.size == 32) { "GCM requires 32-byte key" }
        val destFile = File(destPath)
        destFile.parentFile?.mkdirs()
        val secretKey = SecretKeySpec(key, "AES")

        try {
            FileInputStream(File(cipherPath)).use { fis ->
                FileOutputStream(destFile).use { fos ->
                    val magic = ByteArray(4)
                    if (fis.read(magic) != 4 ||
                        magic[0] != 0x53.toByte() ||
                        magic[1] != 0x42.toByte() ||
                        magic[2] != 0x56.toByte() ||
                        magic[3] != 0x32.toByte()
                    ) {
                        throw IllegalArgumentException("Not a chunked GCM vault blob")
                    }
                    val ver = fis.read()
                    if (ver != 2) throw IllegalArgumentException("Unsupported GCM chunk version: $ver")
                    val countBuf = ByteArray(4)
                    if (fis.read(countBuf) != 4) throw IllegalArgumentException("Truncated chunk count")
                    val chunkCount = ByteBuffer.wrap(countBuf).order(ByteOrder.LITTLE_ENDIAN).int

                    for (chunkIndex in 0 until chunkCount) {
                        if (fis.read(countBuf) != 4) throw IllegalArgumentException("Truncated plainLen")
                        val plainLen = ByteBuffer.wrap(countBuf).order(ByteOrder.LITTLE_ENDIAN).int
                        val nonce = ByteArray(GCM_NONCE_BYTES)
                        if (fis.read(nonce) != GCM_NONCE_BYTES) {
                            throw IllegalArgumentException("Truncated nonce")
                        }
                        if (fis.read(countBuf) != 4) throw IllegalArgumentException("Truncated cipherLen")
                        val cipherLen = ByteBuffer.wrap(countBuf).order(ByteOrder.LITTLE_ENDIAN).int
                        val sealed = ByteArray(cipherLen)
                        var off = 0
                        while (off < cipherLen) {
                            val got = fis.read(sealed, off, cipherLen - off)
                            if (got < 0) throw IllegalArgumentException("Truncated ciphertext")
                            off += got
                        }

                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(
                            Cipher.DECRYPT_MODE,
                            secretKey,
                            GCMParameterSpec(GCM_TAG_BITS, nonce),
                        )
                        val aad = aadPrefix +
                            ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(chunkIndex).array()
                        cipher.updateAAD(aad)
                        val plain = cipher.doFinal(sealed)
                        if (plain.size != plainLen) {
                            throw IllegalArgumentException("Plain length mismatch")
                        }
                        fos.write(plain)
                    }
                }
            }
        } catch (e: Exception) {
            if (destFile.exists()) destFile.delete()
            throw e
        }
    }

    @JvmStatic
    fun encryptFileGcm(sourcePath: String, destPath: String, key: ByteArray): ByteArray {
        val plain = File(sourcePath).readBytes()
        return encryptBytesToFileGcm(destPath, plain, key)
    }

    @JvmStatic
    fun decryptFileGcm(cipherPath: String, destPath: String, key: ByteArray, nonce: ByteArray) {
        val plain = decryptFileToBytesGcm(cipherPath, key, nonce)
        val destFile = File(destPath)
        destFile.parentFile?.mkdirs()
        try {
            destFile.writeBytes(plain)
        } catch (e: Exception) {
            if (destFile.exists()) destFile.delete()
            throw e
        }
    }
}
