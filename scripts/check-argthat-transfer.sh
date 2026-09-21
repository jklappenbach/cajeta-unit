#!/usr/bin/env bash
# `argThat` takes its predicate owned, so a named predicate must be handed over
# with `#`. Asserts the check FIRES on a plain name and does NOT fire on `#name`.
#
# Override the compiler with CAJETA=/path/to/cajeta (defaults to `cajeta` on PATH).
set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"
CAJETA="${CAJETA:-cajeta}"

# Always rebuild. A leftover archive from an earlier source state compiles the
# reject probe happily and turns this check green for the wrong reason.
( cd "$REPO_ROOT" && "$CAJETA" build )
CJA="$( ls "$REPO_ROOT"/build/archive/dev.cajeta.unit-*.cja | head -1 )"

WORK="$REPO_ROOT/tmp/argthat-transfer"
rm -rf "$WORK"

emit() {
    local dir="$1" handoff="$2"
    mkdir -p "$dir/src/probe" "$dir/w"
    cat > "$dir/src/probe/Main.cajeta" <<PROBE
package probe;

import dev.cajeta.unit.ArgMatchers;
import dev.cajeta.unit.Matcher;
import cajeta.lang.Int64;

public class Main {
    public static int32 run() {
        int64 floor = 10;
        (Object) -> boolean p = (Object o) -> {
            Int64 i = (Int64) o;
            return i.value() > floor;
        };
        Matcher m #= ArgMatchers.argThat(${handoff});
        if (m.matches(Int64.of(50))) { return 0; }
        return 1;
    }
}
PROBE
}

build_probe() {
    local dir="$1"
    ( cd "$dir" && "$CAJETA" --emit=exe --classpath="$CJA" \
        -o out probe.Main.run src w ) > "$dir/build.log" 2>&1
}

# FIRES: a plain name must be refused, and named as a transfer problem.
emit "$WORK/reject" "p"
if build_probe "$WORK/reject"; then
    echo "FAIL: argThat(p) compiled. A borrowed predicate outlives its frame." >&2
    exit 1
fi
if ! grep -q "CAJETA_ERROR_TRANSFER_REQUIRED" "$WORK/reject/build.log"; then
    echo "FAIL: argThat(p) was refused, but not for the transfer. Log:" >&2
    tail -5 "$WORK/reject/build.log" >&2
    exit 1
fi

# DOES NOT FIRE: the same predicate handed over with `#` must build and run.
emit "$WORK/accept" "#p"
if ! build_probe "$WORK/accept"; then
    echo "FAIL: argThat(#p) did not compile. Log:" >&2
    tail -20 "$WORK/accept/build.log" >&2
    exit 1
fi
if ! "$WORK/accept/out"; then
    echo "FAIL: argThat(#p) built but did not match through the moved predicate." >&2
    exit 1
fi

echo "check-argthat-transfer: argThat(p) refused, argThat(#p) accepted and matched"
