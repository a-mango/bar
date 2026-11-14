#!/usr/bin/env bash
# The docs/SPEC.md test matrix, run against the nested session (make nested).
#
#   tests/matrix.sh          run every case
#   tests/matrix.sh N5       run one case
#
# Each case is a shell function named case_<ID>. It saves screenshots to
# .test/shots/<ID>/ and returns non-zero on failure. M0 ships the frame
# only: M1 adds the first N cases, M2 the B cases.
set -euo pipefail
REPO=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
T=$REPO/.test

n() { "$REPO/tests/nested.sh" run "$@"; }             # a command inside the session
ipc() { n quickshell ipc -p "$REPO" call "$@"; }      # an IPC call to bar
shot() { mkdir -p "$T/shots/$1"; n grim -o HEADLESS-1 "$T/shots/$1/$2.png"; }

"$REPO/tests/nested.sh" status || { echo "matrix: no nested session, run: make nested" >&2; exit 1; }

cases=$(declare -F | sed -n 's/^declare -f case_//p')
[ $# -gt 0 ] && wanted=$* || wanted=$cases
[ -n "$wanted" ] || { echo "matrix: no case implemented yet" >&2; exit 1; }

failed=0
for id in $wanted; do
    if ! declare -F "case_$id" > /dev/null; then
        echo "FAIL $id (not implemented)"; failed=1; continue
    fi
    if "case_$id"; then echo "PASS $id"; else echo "FAIL $id"; failed=1; fi
done
exit $failed
