/*
 * gen_golden: generates comparison matrices for the differential test corpus
 * across a set of collator configurations, using ICU4C as the oracle.
 *
 * Usage: gen_golden <corpus.txt> <out-dir>
 *
 * Reads corpus strings (UTF-8, one per line, newline stripped, line order
 * significant). For each configuration, opens the root collator with those
 * settings and writes <out-dir>/matrix-<name>.txt: one line per corpus string
 * with one character per corpus string: '<', '=', or '>' for
 * ucol_strcollUTF8(s[i], s[j]).
 *
 * Configuration names must match DifferentialTests.swift.
 *
 * Build (against the locally built ICU; see UCACollation/README.md):
 *   clang gen_golden.c -o gen_golden \
 *     -I $ICU_SRC/icu4c/source/common -I $ICU_SRC/icu4c/source/i18n \
 *     -L $ICU_BUILD/lib -licuuc -licui18n -licudata
 *   DYLD_LIBRARY_PATH=$ICU_BUILD/lib ./gen_golden corpus.txt golden-dir
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "unicode/ucol.h"
#include "unicode/ustring.h"

#define MAX_LINES 4096
#define MAX_LINE 1024

typedef struct {
    const char *name;
    UCollationStrength strength;
    UColAttribute attr;        /* UCOL_ATTRIBUTE_COUNT = none */
    UColAttributeValue value;
} Config;

static const Config configs[] = {
    {"primary",    UCOL_PRIMARY,    UCOL_ATTRIBUTE_COUNT, UCOL_DEFAULT},
    {"secondary",  UCOL_SECONDARY,  UCOL_ATTRIBUTE_COUNT, UCOL_DEFAULT},
    {"tertiary",   UCOL_TERTIARY,   UCOL_ATTRIBUTE_COUNT, UCOL_DEFAULT},
    {"quaternary", UCOL_QUATERNARY, UCOL_ATTRIBUTE_COUNT, UCOL_DEFAULT},
    {"identical",  UCOL_IDENTICAL,  UCOL_ATTRIBUTE_COUNT, UCOL_DEFAULT},
    {"shifted",    UCOL_QUATERNARY, UCOL_ALTERNATE_HANDLING, UCOL_SHIFTED},
    {"shifted3",   UCOL_TERTIARY,   UCOL_ALTERNATE_HANDLING, UCOL_SHIFTED},
    {"case1",      UCOL_PRIMARY,    UCOL_CASE_LEVEL, UCOL_ON},
    {"caselevel",  UCOL_TERTIARY,   UCOL_CASE_LEVEL, UCOL_ON},
    {"upperfirst", UCOL_TERTIARY,   UCOL_CASE_FIRST, UCOL_UPPER_FIRST},
    {"lowerfirst", UCOL_TERTIARY,   UCOL_CASE_FIRST, UCOL_LOWER_FIRST},
    {"french",     UCOL_TERTIARY,   UCOL_FRENCH_COLLATION, UCOL_ON},
    {"numeric",    UCOL_TERTIARY,   UCOL_NUMERIC_COLLATION, UCOL_ON},
};

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <corpus.txt> <out-dir>\n", argv[0]);
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

    int numConfigs = (int)(sizeof(configs) / sizeof(configs[0]));
    for (int k = 0; k < numConfigs; k++) {
        UErrorCode status = U_ZERO_ERROR;
        UCollator *coll = ucol_open("root", &status);
        if (U_FAILURE(status)) {
            fprintf(stderr, "ucol_open: %s\n", u_errorName(status));
            return 1;
        }
        ucol_setStrength(coll, configs[k].strength);
        /* Our implementation follows the ICU4X model: normalization is always
         * on. ICU's root collator defaults to normalization OFF, which gives
         * different (non-canonical) results for input whose combining marks
         * are not in canonical order. Align the oracle. */
        ucol_setAttribute(coll, UCOL_NORMALIZATION_MODE, UCOL_ON, &status);
        if (U_FAILURE(status)) {
            fprintf(stderr, "setAttribute(norm): %s\n", u_errorName(status));
            return 1;
        }
        if (configs[k].attr != UCOL_ATTRIBUTE_COUNT) {
            ucol_setAttribute(coll, configs[k].attr, configs[k].value, &status);
            if (U_FAILURE(status)) {
                fprintf(stderr, "setAttribute(%s): %s\n", configs[k].name, u_errorName(status));
                return 1;
            }
        }

        char path[1024];
        snprintf(path, sizeof(path), "%s/matrix-%s.txt", argv[2], configs[k].name);
        FILE *out = fopen(path, "w");
        if (!out) { perror(path); return 1; }
        for (int i = 0; i < n; i++) {
            for (int j = 0; j < n; j++) {
                status = U_ZERO_ERROR;
                UCollationResult r = ucol_strcollUTF8(coll, lines[i], -1, lines[j], -1, &status);
                if (U_FAILURE(status)) {
                    fprintf(stderr, "strcoll(%s,%d,%d): %s\n",
                            configs[k].name, i, j, u_errorName(status));
                    return 1;
                }
                fputc(r == UCOL_LESS ? '<' : r == UCOL_GREATER ? '>' : '=', out);
            }
            fputc('\n', out);
        }
        fclose(out);
        ucol_close(coll);
        fprintf(stderr, "wrote %s (%dx%d)\n", path, n, n);
    }
    return 0;
}
