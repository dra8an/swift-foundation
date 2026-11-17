#!/bin/zsh
# The loop check of the benchmark runbook (Docs/27; technique log §52 (k)): records whole passes of EngineBench's
# compare loop under lldb and reports, per corpus,
#   - the instructions per pass INSIDE compare (the engine) and OUTSIDE it (the benchmark loop), and the taken branches;
#   - position rule 1: a 4 KB address boundary that cuts a hot run of code that ends in a return, so that it needs
#     one more piece (a cut run that ends in another instruction is printed as a note);
#   - position rule 2: two hot pieces of code that end in a return and start a multiple of 2 KB apart.
# With a reference file, it also says which counts changed. Run it once for each new EngineBench binary, before the
# numbers of two binaries are compared. It times nothing; the load of the machine does not matter. About 5 minutes (lldb single-steps).
# Usage (repo root): Collation/Tools/insn-count/loop_check.sh <EngineBench> [--write-ref] [corpus ...]
#   corpora default: ascii latin cjk (the rows of a few ns, where 2 instructions of loop are 1%);
#   the reference file is Collation/Tools/insn-count/loop_check.ref (--write-ref replaces the lines of the corpora run).
SCRIPT_DIR=${0:A:h}
REPO=${SCRIPT_DIR:h:h:h}
source "${SCRIPT_DIR:h}/swift_toolchain.sh"   # LLDB: the selected Xcode's lldb (it has the Python framework)
bin=$1; shift
write=""; [[ "$1" == "--write-ref" ]] && { write="--write-ref"; shift; }
if (( $# )); then corpora=($@); else corpora=(ascii latin cjk); fi
out=$REPO/.build/loop-check; mkdir -p $out
sym=$(nm $bin | grep ' T .*12RootCollatorV7compare__7options' | awk '{print $3}' | sed 's/^_//')
[[ -n "$sym" ]] || { echo "loop_check: compare(_:_:options:) not found in $bin" >&2; exit 2; }
for c in $corpora; do
  lines=$(grep -c '' $REPO/Collation/Tools/bench/bench-$c.txt)
  # The recording starts after 3 whole passes, so that it is in the TIMED copy of the loop (main has a second copy
  # for the warm-up pass) and the predictors are warm. A breakpoint with a skip count is slow, so a corpus of more
  # than 2000 lines (thai) is refused: its row is 160 ns, where the loop does not matter.
  if (( lines > 2000 )); then echo "loop_check: $c has $lines lines, too long for a recording after 3 passes; not checked" >&2; continue; fi
  calls=$(( lines - 1 )); (( calls > 400 )) && calls=400      # one whole pass, or the first 400 calls of a pass
  skip=$(( 3 * (lines - 1) ))
  ( $LLDB -b -o "command script import $SCRIPT_DIR/pc_trace.py" -o "breakpoint set -s ${bin:t} -n $sym -K false" \
      -o "breakpoint modify -i $skip 1" -o run -o "pc_trace $out/$c.txt $calls" -o kill \
      -- $bin $REPO/Collation/Tools/bench/bench-$c.txt 1 > $out/$c.log 2>&1 ) &
done
wait
rc=0
for c in $corpora; do
  [[ -f $out/$c.txt ]] || continue
  python3 -I $SCRIPT_DIR/loop_check.py $out/$c.txt $bin $c $SCRIPT_DIR/loop_check.ref $write || rc=1
done
exit $rc
