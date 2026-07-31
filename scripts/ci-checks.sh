#!/usr/bin/env bash
# The full CI check chain: the framework's self-test, the tour, then the
# tour coverage gate. release.yml's `test-command` points here so the list
# lives in one place.
set -euo pipefail
cd "$(dirname "$0")/.."

cajeta test

./samples/tour/run.sh

CAJETA="$(command -v cajeta)" ./scripts/check-library-tour-coverage.sh \
    src/main/cajeta samples/tour scripts/tour-coverage-ignore.txt
