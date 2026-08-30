// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

package com.resendeghf.notes;

/**
 * Thin JNI bridge: {@code getrlimit}/{@code setrlimit} live in libc and are not exposed on older
 * Android API levels through {@link android.system.Os} / {@link android.system.StructRlimit}.
 */
public final class MemlockLimiterNative {

    static {
        System.loadLibrary("saber_memlock");
    }

    /** @return locked-byte budget after raise, or {@code -1} if unlimited */
    public static long raiseBestEffort() {
        return nativeRaiseBestEffort();
    }

    private static native long nativeRaiseBestEffort();
}
