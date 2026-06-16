/*
 * ICU counterpart of Sources/Bench: measures ucol_strcollUTF8 and
 * ucol_getSortKey throughput over a corpus file. Normalization is set ON to
 * match the Swift implementation's always-normalizing design.
 *
 * Build:
 *   clang bench_icu.c -o bench_icu \
 *     -I $ICU_SRC/icu4c/source/common -I $ICU_SRC/icu4c/source/i18n \
 *     -L $ICU_BUILD/lib -licuuc -licui18n -licudata
 * Usage: DYLD_LIBRARY_PATH=$ICU_BUILD/lib ./bench_icu <corpus.txt> [reps] [locale]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "unicode/ucol.h"
#include "unicode/ustring.h"

#define MAX_LINES 320000
#define MAX_LINE 1024

static UCollator *g_sortcoll;
static int sort_cmp(const void *a, const void *b) {
    UErrorCode s = U_ZERO_ERROR;
    return ucol_strcollUTF8(g_sortcoll, *(const char *const *)a, -1,
                            *(const char *const *)b, -1, &s);
}

static uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000u + (uint64_t)ts.tv_nsec;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <corpus.txt> [reps] [locale]\n", argv[0]);
        return 2;
    }
    int reps = argc > 2 ? atoi(argv[2]) : 200;
    const char *locale = argc > 3 ? argv[3] : "root";

    FILE *in = fopen(argv[1], "r");
    if (!in) { perror("corpus"); return 1; }
    static char *lines[MAX_LINES];
    static UChar ulines[MAX_LINES][64];
    static int32_t ulens[MAX_LINES];
    static char buf[MAX_LINE];
    int n = 0;
    UErrorCode status = U_ZERO_ERROR;
    while (fgets(buf, sizeof(buf), in) && n < MAX_LINES) {
        size_t len = strlen(buf);
        if (len > 0 && buf[len - 1] == '\n') buf[--len] = '\0';
        if (len == 0) continue;
        lines[n] = strdup(buf);
        u_strFromUTF8(ulines[n], 64, &ulens[n], buf, -1, &status);
        if (U_FAILURE(status)) { fprintf(stderr, "utf8 conv: %s\n", u_errorName(status)); return 1; }
        n++;
    }
    fclose(in);

    UCollator *coll = ucol_open(locale, &status);
    ucol_setAttribute(coll, UCOL_NORMALIZATION_MODE, UCOL_ON, &status);
    if (U_FAILURE(status)) { fprintf(stderr, "ucol: %s\n", u_errorName(status)); return 1; }

    /* `bench_icu <corpus> sort [locale]` prints lines sorted by ICU, for
     * cross-checking sort order against ours (`Bench <corpus> sort`). */
    if (argc > 2 && strcmp(argv[2], "sort") == 0) {
        g_sortcoll = coll;
        qsort(lines, n, sizeof(lines[0]), sort_cmp);
        for (int i = 0; i < n; i++) printf("%s\n", lines[i]);
        return 0;
    }

    volatile long sink = 0;

    /* warmup + measure compare */
    for (int r = 0; r < 2; r++) {
        uint64_t start = now_ns();
        for (int rep = 0; rep < reps; rep++) {
            for (int i = 1; i < n; i++) {
                status = U_ZERO_ERROR;
                sink += ucol_strcollUTF8(coll, lines[i - 1], -1, lines[i], -1, &status);
            }
        }
        uint64_t ns = now_ns() - start;
        if (r == 1) printf("compare : %llu ns/op (%d ops)\n",
                           (unsigned long long)(ns / ((uint64_t)(n - 1) * reps)), (n - 1) * reps);
    }

    /* warmup + measure sort keys (UTF-16 input, like the public API) */
    for (int r = 0; r < 2; r++) {
        uint64_t start = now_ns();
        for (int rep = 0; rep < reps; rep++) {
            for (int i = 0; i < n; i++) {
                uint8_t skey[1024];
                sink += ucol_getSortKey(coll, ulines[i], ulens[i], skey, sizeof(skey));
            }
        }
        uint64_t ns = now_ns() - start;
        if (r == 1) printf("sortKey : %llu ns/op (%d ops)\n",
                           (unsigned long long)(ns / ((uint64_t)n * reps)), n * reps);
    }

    ucol_close(coll);
    return sink == -1 ? 1 : 0;
}
