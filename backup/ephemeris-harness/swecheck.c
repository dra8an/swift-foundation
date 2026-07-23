/* Reads lines "label jd_ut" from stdin; prints label, jd, sun ecliptic
   longitude, moon-sun elongation (degrees), and the ephemeris flag used. */
#include <stdio.h>
#include <string.h>
#include "swephexp.h"

int main(int argc, char **argv) {
    char serr[256];
    double xsun[6], xmoon[6];
    if (argc > 1) swe_set_ephe_path(argv[1]); else swe_set_ephe_path(NULL);
    int flag = (argc > 1) ? SEFLG_SWIEPH : SEFLG_MOSEPH;
    char label[128]; double jd;
    while (scanf("%127s %lf", label, &jd) == 2) {
        int r1 = swe_calc_ut(jd, SE_SUN, flag, xsun, serr);
        int r2 = swe_calc_ut(jd, SE_MOON, flag, xmoon, serr);
        if (r1 < 0 || r2 < 0) { printf("%s %.6f ERR %s\n", label, jd, serr); continue; }
        double elong = xmoon[0] - xsun[0];
        while (elong < -180) elong += 360;
        while (elong > 180) elong -= 360;
        printf("%s %.6f %.7f %.7f %d\n", label, jd, xsun[0], elong, r1);
    }
    swe_close();
    return 0;
}
