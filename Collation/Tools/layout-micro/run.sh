#!/bin/zsh
# The two micro tests behind the position rules of loop_check.py (technique log §52 (k)); Apple Silicon only.
#   boundary: a jump target D instructions before a 4 KB boundary (p4k) or a 64-byte boundary (l64), followed by a
#             straight run of 8 (P0) or 20 (P12) instructions that ends in a return. Rule 1: one more cycle when the
#             4 KB boundary makes the run need one more piece of at most 16 instructions.
#   alias:    two pieces that end in a return, the second DELTA bytes after the first. Rule 2: about 4 more cycles
#             per pass when DELTA is a multiple of 2048.
# Prints ns and cycles per pass (cycles at 3.228 GHz, the M1 Max performance core). Builds into .build/layout-micro.
# Usage (repo root): Collation/Tools/layout-micro/run.sh
SCRIPT_DIR=${0:A:h}
REPO=${SCRIPT_DIR:h:h:h}
out=$REPO/.build/layout-micro; mkdir -p $out; cd $out
for t in boundary alias; do
  python3 -I $SCRIPT_DIR/gen_$t.py && xcrun clang -O2 -I . $SCRIPT_DIR/main.c micro*.S -o $t && rm -f micro*.S || exit 1
  echo "== $t"; ./$t 100000000 5
done
