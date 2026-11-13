#!/bin/zsh
# The loop check of the benchmark runbook (Docs/27; technique log §52 (k)): records whole passes of EngineBench's
# compare loop under lldb and reports, per corpus,
#   - the instructions per pass INSIDE compare (the engine) and OUTSIDE it (the benchmark loop), and the taken branches;
#   - position rule 1: a 4 KB address boundary that cuts a hot straight run of code so that it needs one more piece;
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
  calls=$(( lines - 1 )); (( calls > 400 )) && calls=400      # one whole pass, or 400 calls of a long corpus
  skip=$(( 3 * (lines - 1) )); (( calls == 400 )) && skip=400  # after 3 passes (the predictors are warm); long corpus: 400 calls
  ( $LLDB -b -o "command script import $SCRIPT_DIR/pc_trace.py" -o "breakpoint set -s ${bin:t} -n $sym -K false" \
      -o "breakpoint modify -i $skip 1" -o run -o "pc_trace $out/$c.txt $calls" -o kill \
      -- $bin $REPO/Collation/Tools/bench/bench-$c.txt 1 > $out/$c.log 2>&1 ) &
done
wait
rc=0
for c in $corpora; do
  python3 -I $SCRIPT_DIR/loop_check.py $out/$c.txt $bin $c $SCRIPT_DIR/loop_check.ref $write || rc=1
done
exit $rc
