/* ICU side of the instruction count (technique log §50 (g)): the same pairs as the
 * Swift ladder's count mode, one ucol_strcollUTF8 each through count_icu,
 * which lldb stops at and single-steps until it returns. Same collator setup
 * as bench_icu.c (root, normalization on). Warms every pair up first.
 * Build: clang -O2 -g icu_count.c -o icu_count -I $ICU_SRC/icu4c/source/common \
 *          -I $ICU_SRC/icu4c/source/i18n -L $ICU_BUILD/lib -licuuc -licui18n -licudata
 * Run under lldb with `settings set target.env-vars DYLD_LIBRARY_PATH=$ICU_BUILD/lib`,
 * break on count_icu, then count_insns as for the Swift side. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "unicode/ucol.h"

__attribute__((noinline)) int count_icu(UCollator *c, const char *a, const char *b) {
    UErrorCode st = U_ZERO_ERROR;
    return ucol_strcollUTF8(c, a, -1, b, -1, &st);
}

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "usage: %s <corpus> <first pair> <pairs>\n", argv[0]); return 2; }
    int first = atoi(argv[2]), n = atoi(argv[3]);
    FILE *in = fopen(argv[1], "r");
    if (!in) { perror("corpus"); return 1; }
    static char *lines[400000];
    char *buf = NULL; size_t cap = 0; ssize_t len; int count = 0;
    while ((len = getline(&buf, &cap, in)) >= 0) {
        if (len > 0 && buf[len - 1] == '\n') buf[--len] = '\0';
        if (len == 0) continue;
        lines[count++] = strdup(buf);
    }
    fclose(in);
    UErrorCode st = U_ZERO_ERROR;
    UCollator *coll = ucol_open("root", &st);
    ucol_setAttribute(coll, UCOL_NORMALIZATION_MODE, UCOL_ON, &st);
    if (U_FAILURE(st)) { fprintf(stderr, "ucol: %s\n", u_errorName(st)); return 1; }
    volatile long sink = 0;
    for (int w = 0; w < 1000; w++)
        for (int i = first; i < first + n && i < count; i++) sink += ucol_strcollUTF8(coll, lines[i - 1], -1, lines[i], -1, &st);
    for (int i = first; i < first + n && i < count; i++) sink += count_icu(coll, lines[i - 1], lines[i]);
    printf("count mode: %d pairs from %d (%ld)\n", n, first, (long)sink);
    return 0;
}
