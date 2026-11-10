/*
 * extract_tailoring: extracts compiled collation tailoring binaries
 * (%%CollationBin, "UCol" v5 format with data header) from ICU resource
 * bundles, for bundling as Swift package resources.
 *
 * Usage: extract_tailoring <out-dir> <locale[/type]>...
 *   e.g. extract_tailoring out de/phonebook sv fr_CA tr da lt ja zh
 * Writes <out-dir>/<locale>[-<type>].bin
 *
 * Build:
 *   clang extract_tailoring.c -o extract_tailoring \
 *     -I $ICU_SRC/icu4c/source/common -I $ICU_SRC/icu4c/source/i18n \
 *     -L $ICU_BUILD/lib -licuuc -licui18n -licudata
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "unicode/ures.h"
#include "unicode/utypes.h"

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <out-dir> <locale[/type]>...\n", argv[0]);
        return 2;
    }
    for (int a = 2; a < argc; a++) {
        char locale[64], type[64] = "standard", name[160];
        const char *slash = strchr(argv[a], '/');
        if (slash) {
            snprintf(locale, sizeof(locale), "%.*s", (int)(slash - argv[a]), argv[a]);
            snprintf(type, sizeof(type), "%s", slash + 1);
            snprintf(name, sizeof(name), "%s-%s", locale, type);
        } else {
            snprintf(locale, sizeof(locale), "%s", argv[a]);
            snprintf(name, sizeof(name), "%s", locale);
        }

        UErrorCode status = U_ZERO_ERROR;
        UResourceBundle *bundle = ures_open(U_ICUDATA_NAME "-coll", locale, &status);
        UResourceBundle *collations = ures_getByKey(bundle, "collations", NULL, &status);
        UResourceBundle *t = ures_getByKey(collations, type, NULL, &status);
        UResourceBundle *bin = ures_getByKey(t, "%%CollationBin", NULL, &status);
        int32_t length = 0;
        const uint8_t *bytes = ures_getBinary(bin, &length, &status);
        if (U_FAILURE(status) || length <= 0) {
            fprintf(stderr, "%s: %s\n", argv[a], u_errorName(status));
            return 1;
        }

        char path[1024];
        snprintf(path, sizeof(path), "%s/%s.bin", argv[1], name);
        FILE *out = fopen(path, "wb");
        if (!out) { perror(path); return 1; }
        fwrite(bytes, 1, (size_t)length, out);
        fclose(out);
        fprintf(stderr, "wrote %s (%d bytes)\n", path, length);

        ures_close(bin);
        ures_close(t);
        ures_close(collations);
        ures_close(bundle);
    }
    return 0;
}
