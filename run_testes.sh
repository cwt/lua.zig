#!/bin/bash
# Run the Lua 5.5.1 test suite against luazig
# Reports pass/fail per test file with summary.
#
# Usage: ./run_testes.sh [--verbose] [--timeout N]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

VERBOSE=false
TIMEOUT=30

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose) VERBOSE=true; shift ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        *) break ;;
    esac
done

echo "=== Lua test suite runner for luazig ==="
echo "Building luazig..."
zig build 2>&1 | tail -3
echo ""

LUAZIG="$SCRIPT_DIR/zig-out/bin/luazig"
TEST_DIR="lua/testes"

# Tests that are the harness / a standalone-interpreter driver. They are not
# regular per-file tests:
#   all.lua    - harness (runs the suite via dofile+string.dump roundtrip)
#   main.lua   - standalone interpreter CLI tests (spawns `lua` subprocesses)
#
# Tests that UNCONDITIONALLY require the internal C test library `T`:
#   api.lua code.lua coroutine.lua gc.lua strings.lua memerr.lua tracegc.lua

# Extra-slow/heavy tests
HEAVY_TESTS="heavy.lua verybig.lua big.lua"

# Tests that unconditionally require the internal C test lib `T`.
T_TESTS="api.lua code.lua coroutine.lua gc.lua strings.lua memerr.lua tracegc.lua"

# Run from within lua/testes so that require("bwcoercion") / require("tracegc")
# resolve via package.path's "./?.lua", and so dofile('main.lua') etc. work.
cd "$TEST_DIR"

# Make `lua` resolve to luazig so tests that spawn subprocesses exercise luazig
# rather than the reference interpreter.
LUA_BIN_DIR="$(mktemp -d)"
ln -sf "$LUAZIG" "$LUA_BIN_DIR/lua"
cleanup() { rm -rf "$LUA_BIN_DIR"; }
trap cleanup EXIT
PATH="$LUA_BIN_DIR:$PATH"
export PATH

declare -A results
declare -A details

for test_file in ./*.lua; do
    base=$(basename "$test_file" .lua)

    # Skip harness / standalone-interpreter driver
    [[ "$base" == "all" || "$base" == "main" ]] && { results["$base"]="SKIP (harness)"; continue; }

    # Skip tests that unconditionally need the internal C test lib `T`
    skip_t=false
    for tt in $T_TESTS; do
        [[ "$base.lua" == "$tt" ]] && skip_t=true
    done
    if $skip_t; then
        results["$base"]="SKIP (needs T)"; continue
    fi

    # Use longer timeout for heavy tests
    t=$TIMEOUT
    for heavy in $HEAVY_TESTS; do
        [[ "$base.lua" == "$heavy" ]] && t=120
    done

    $VERBOSE && echo -n "  $base ... "

    # Run the test, capture stdout and stderr
    tmp_out=$(mktemp)
    tmp_err=$(mktemp)
    set +e
    timeout "$t" "$LUAZIG" "$base.lua" > "$tmp_out" 2> "$tmp_err"
    rc=$?
    set -e

    stdout=$(cat "$tmp_out" 2>/dev/null)
    stderr=$(cat "$tmp_err" 2>/dev/null)
    rm -f "$tmp_out" "$tmp_err"

    if [[ $rc -eq 124 ]]; then
        results["$base"]="TIMEOUT"
        details["$base"]="timed out after ${t}s"
    elif [[ $rc -ne 0 ]]; then
        if echo "$stderr" | grep -q 'panic'; then
            results["$base"]="CRASH"
            details["$base"]=$(echo "$stderr" | grep 'panic' | head -1)
        else
            results["$base"]="FAIL (exit=$rc)"
            details["$base"]=$(echo "$stderr" | head -3)
        fi
    elif echo "$stdout" | grep -q 'OK$'; then
        results["$base"]="PASS"
        details["$base"]=""
    elif echo "$stdout" | grep -q '^\s*OK'; then
        results["$base"]="PASS"
        details["$base"]=""
    elif [[ -z "$stdout" ]] && [[ -z "$stderr" ]]; then
        results["$base"]="PASS (no output)"
        details["$base"]=""
    elif [[ -z "$stdout" ]]; then
        results["$base"]="PASS (stderr only)"
        details["$base"]=""
    else
        results["$base"]="CHECK"
        details["$base"]=$(echo "$stdout" | head -3 | tr '\n' ' ')
    fi

    $VERBOSE && echo "${results[$base]}"
done

# Summary
echo ""
echo "=== Results ==="
passed=0
failed=0
skipped=0
timedout=0
crashed=0
checked=0

for test in $(echo "${!results[@]}" | tr ' ' '\n' | sort); do
    result="${results[$test]}"
    case "$result" in
        PASS*) passed=$((passed+1)) ;;
        FAIL*) failed=$((failed+1)) ;;
        CRASH*) crashed=$((crashed+1)) ;;
        TIMEOUT*) timedout=$((timedout+1)) ;;
        SKIP*) skipped=$((skipped+1)) ;;
        CHECK*) checked=$((checked+1)) ;;
    esac

    if [[ "$result" != PASS* ]] && [[ "$result" != SKIP* ]]; then
        echo "  $test: $result"
        if [[ -n "${details[$test]:-}" ]]; then
            echo "       ${details[$test]}"
        fi
    fi
done

echo ""
echo "  PASS:   $passed"
echo "  FAIL:   $failed"
echo "  CRASH:  $crashed"
echo "  TIMEOUT:$timedout"
echo "  SKIP:   $skipped"
echo "  CHECK:  $checked"
echo "  -----"
echo "  TOTAL:  $((passed + failed + crashed + timedout + skipped + checked))"
