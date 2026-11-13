// Times each case: N loop passes, minimum of R repetitions, in ns and in cycles (3.228 GHz, M1 Max performance core).
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mach/mach_time.h>
#include <pthread/qos.h>
#include "table.h"
int main(int argc, char **argv) {
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
    long n = argc > 1 ? atol(argv[1]) : 100000000; int reps = argc > 2 ? atoi(argv[2]) : 5;
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    int count = sizeof cases / sizeof cases[0];
    double *best = malloc(count * sizeof(double));
    for (int i = 0; i < count; i++) best[i] = 1e30;
    for (int r = 0; r < reps; r++)
        for (int k = 0; k < count; k++) {
            int i = (r % 2) ? count - 1 - k : k;
            cases[i].fn(n / 20);
            uint64_t t0 = mach_absolute_time(); cases[i].fn(n); uint64_t t1 = mach_absolute_time();
            double ns = (double)(t1 - t0) * tb.numer / tb.denom / n;
            if (ns < best[i]) best[i] = ns;
        }
    for (int i = 0; i < count; i++) printf("%-14s %6.3f ns  %5.2f cycles\n", cases[i].name, best[i], best[i] * 3.228);
    return 0;
}
