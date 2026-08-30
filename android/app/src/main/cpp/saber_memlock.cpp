/* SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF> */
/* SPDX-License-Identifier: GPL-3.0-or-later */

#include <android/log.h>
#include <errno.h>
#include <jni.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <unistd.h>

#define LOG_TAG "MemlockLimiter"

#ifndef RLIM_INFINITY
#define RLIM_INFINITY (~(rlim_t)0)
#endif

static int is_infinity(rlim_t v) { return v == RLIM_INFINITY; }

static int try_set(rlim_t cur, rlim_t max) {
  struct rlimit lim;
  memset(&lim, 0, sizeof(lim));
  lim.rlim_cur = cur;
  lim.rlim_max = max;
  return setrlimit(RLIMIT_MEMLOCK, &lim);
}

#ifdef __NR_prlimit64
static int try_prlimit(rlim_t cur, rlim_t max) {
  struct rlimit lim;
  memset(&lim, 0, sizeof(lim));
  lim.rlim_cur = cur;
  lim.rlim_max = max;
  return (int)syscall(__NR_prlimit64, 0, RLIMIT_MEMLOCK, &lim, nullptr);
}
#else
static int try_prlimit(rlim_t cur, rlim_t max) {
  (void)cur;
  (void)max;
  errno = ENOSYS;
  return -1;
}
#endif

static void log_limit(const char *prefix, const struct rlimit *v) {
  if (is_infinity(v->rlim_cur) && is_infinity(v->rlim_max)) {
    __android_log_print(ANDROID_LOG_INFO, LOG_TAG, "%s cur=INFINITY max=INFINITY", prefix);
    return;
  }
  __android_log_print(ANDROID_LOG_INFO, LOG_TAG, "%s cur=%llu max=%llu", prefix,
                      (unsigned long long)v->rlim_cur, (unsigned long long)v->rlim_max);
}

/** Returns locked-byte budget, or -1 if unlimited. */
static jlong budget_from(const struct rlimit *v) {
  if (is_infinity(v->rlim_cur)) return -1;
  if (v->rlim_cur > (rlim_t)INT64_MAX) return -1;
  return (jlong)v->rlim_cur;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_resendeghf_notes_MemlockLimiterNative_nativeRaiseBestEffort(JNIEnv *env, jclass clazz) {
  struct rlimit orig;
  memset(&orig, 0, sizeof(orig));
  if (getrlimit(RLIMIT_MEMLOCK, &orig) != 0) {
    __android_log_print(ANDROID_LOG_WARN, LOG_TAG, "getrlimit(RLIMIT_MEMLOCK) failed: errno=%d",
                        errno);
    return 0;
  }
  log_limit("RLIMIT_MEMLOCK before", &orig);

  /* 1) Unlimited (works when the hard cap is already INFINITY). */
  if (try_set(RLIM_INFINITY, RLIM_INFINITY) != 0) {
    try_prlimit(RLIM_INFINITY, RLIM_INFINITY);
  }

  /* 2) Soft = existing hard cap. */
  if (!is_infinity(orig.rlim_max)) {
    try_set(orig.rlim_max, orig.rlim_max);
  } else {
    try_set(RLIM_INFINITY, orig.rlim_max);
  }

  /* 3) Ask for successively smaller explicit caps; raising the hard limit
   *    needs CAP_IPC_LOCK / CAP_SYS_RESOURCE and usually fails. */
  static const rlim_t kWant[] = {
      (rlim_t)256 * 1024 * 1024, (rlim_t)64 * 1024 * 1024, (rlim_t)16 * 1024 * 1024,
      (rlim_t)8 * 1024 * 1024,   (rlim_t)1 * 1024 * 1024,
  };
  for (size_t i = 0; i < sizeof(kWant) / sizeof(kWant[0]); ++i) {
    const rlim_t want = kWant[i];
    if (try_set(want, want) == 0) break;
    if (try_prlimit(want, want) == 0) break;
    if (!is_infinity(orig.rlim_max) && want <= orig.rlim_max) {
      if (try_set(want, orig.rlim_max) == 0) break;
    }
  }

  /* 4) Guarantee at least soft = min(want, hard). */
  struct rlimit now;
  memset(&now, 0, sizeof(now));
  if (getrlimit(RLIMIT_MEMLOCK, &now) == 0) {
    if (!is_infinity(now.rlim_cur) && !is_infinity(now.rlim_max) && now.rlim_cur < now.rlim_max) {
      try_set(now.rlim_max, now.rlim_max);
      getrlimit(RLIMIT_MEMLOCK, &now);
    }
    log_limit("RLIMIT_MEMLOCK after", &now);
    return budget_from(&now);
  }
  return budget_from(&orig);
}
