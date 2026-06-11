/*
 * gen_golden: generates the primary-strength comparison matrix for the
 * differential test corpus, using ICU4C as the oracle.
 *
 * Usage: gen_golden <corpus.txt> <matrix-out.txt>
 *
 * Reads corpus strings (UTF-8, one per line, newline stripped, line order
 * significant). Opens the root collator at UCOL_PRIMARY strength and writes
 * one line per corpus string with one character per corpus string:
 * '<', '=', or '>' for ucol_strcollUTF8(s[i], s[j]).
 *
 * Build (against the locally built ICU; see Docs/03-swift-strategy.md):
 *   clang gen_golden.c -o gen_golden \
 *     -I $ICU_SRC/icu4c/source/common -I $ICU_SRC/icu4c/source/i18n \
 *     -L $ICU_BUILD/lib -licuuc -licui18n -licudata
 *   DYLD_LIBRARY_PATH=$ICU_BUILD/lib ./gen_golden corpus.txt matrix.txt
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "unicode/ucol.h"
#include "unicode/ustring.h"

#define MAX_LINES 4096
#define MAX_LINE 1024

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <corpus.txt> <matrix-out.txt>\n", argv[0]);
        return 2;
    }
    FILE *in = fopen(argv[1], "r");
    if (!in) { perror("corpus"); return 1; }

    static char *lines[MAX_LINES];
    static char buf[MAX_LINE];
    int n = 0;
    while (fgets(buf, sizeof(buf), in) && n < MAX_LINES) {
        size_t len = strlen(buf);
        if (len > 0 && buf[len - 1] == '\n') buf[--len] = '\0';
        if (len == 0) continue;
        lines[n++] = strdup(buf);
    }
    fclose(in);
    fprintf(stderr, "corpus: %d strings\n", n);

    UErrorCode status = U_ZERO_ERROR;
    UCollator *coll = ucol_open("root", &status);
    if (U_FAILURE(status)) {
        fprintf(stderr, "ucol_open: %s\n", u_errorName(status));
        return 1;
    }
    ucol_setStrength(coll, UCOL_PRIMARY);

    UVersionInfo uca;
    ucol_getUCAVersion(coll, uca);
    fprintf(stderr, "UCA version: %d.%d.%d\n", uca[0], uca[1], uca[2]);

    FILE *out = fopen(argv[2], "w");
    if (!out) { perror("matrix"); return 1; }
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            status = U_ZERO_ERROR;
            UCollationResult r = ucol_strcollUTF8(coll, lines[i], -1, lines[j], -1, &status);
            if (U_FAILURE(status)) {
                fprintf(stderr, "strcoll(%d,%d): %s\n", i, j, u_errorName(status));
                return 1;
            }
            fputc(r == UCOL_LESS ? '<' : r == UCOL_GREATER ? '>' : '=', out);
        }
        fputc('\n', out);
    }
    fclose(out);
    ucol_close(coll);
    fprintf(stderr, "wrote %dx%d matrix\n", n, n);
    return 0;
}
