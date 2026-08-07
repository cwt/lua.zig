#!/bin/bash
# Run the Lua test suite against luazig or specified reference interpreter
# Reports pass/fail per test file with summary.
#
# Usage: ./run_testes.sh [--verbose] [--timeout N] [--lua PATH]
#
# Compatible with bash >= 3.2 (macOS default).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

VERBOSE=false
TIMEOUT=30
LUA_BIN="$SCRIPT_DIR/zig-out/bin/luazig"
RUN_ALL=false

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose) VERBOSE=true; shift ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --lua) LUA_BIN="$2"; shift 2 ;;
        --all) RUN_ALL=true; shift ;;
        *) break ;;
    esac
done

if [[ "$LUA_BIN" != /* ]]; then
    LUA_BIN="$SCRIPT_DIR/$LUA_BIN"
fi

echo "=== Lua test suite runner ==="
echo "Interpreter: $LUA_BIN"

# Fallback for macOS where GNU timeout causes SIGSYS in sandbox environments
if [[ "$(uname)" == "Darwin" ]]; then
    run_with_timeout() {
        local t=$1; shift
        perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$t" "$@" &
        local pid=$!
        wait $pid 2>/dev/null || true
        local rc=$?
        if [[ $rc -gt 128 ]]; then return 124; fi
        if [[ $rc -eq 127 ]]; then return 1; fi
        return $rc
    }
elif command -v timeout &>/dev/null; then
    run_with_timeout() { timeout "$@"; }
elif command -v gtimeout &>/dev/null; then
    run_with_timeout() { gtimeout "$@"; }
else
    run_with_timeout() {
        local t=$1; shift
        perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$t" "$@" &
        local pid=$!
        wait $pid 2>/dev/null || true
        local rc=$?
        if [[ $rc -gt 128 ]]; then return 124; fi
        if [[ $rc -eq 127 ]]; then return 1; fi
        return $rc
    }
fi

if [[ "$LUA_BIN" == *"/luazig"* ]]; then
    echo "Building luazig..."
    zig build 2>&1 | tail -3
    echo ""
fi

LUAZIG="$LUA_BIN"
TEST_DIR="lua/testes"

cd "$TEST_DIR"

# Make `lua` resolve to the selected interpreter so tests that spawn subprocesses exercise it.
LUA_BIN_DIR="$(mktemp -d /tmp/luazig_tests_XXXXXX)"
ln -sf "$LUAZIG" "$LUA_BIN_DIR/lua"
cleanup() { rm -rf "$LUA_BIN_DIR"; }
trap cleanup EXIT
PATH="$LUA_BIN_DIR:$PATH"
export PATH

if $RUN_ALL; then
    echo "Running all.lua harness..."
    set +e
    run_with_timeout "$TIMEOUT" "$LUAZIG" all.lua
    rc=$?
    set -e
    exit $rc
fi

# Extra-slow/heavy tests
HEAVY_TESTS="verybig.lua big.lua constructs.lua sort.lua cstack.lua"

# Tests that unconditionally require the internal C test lib `T`.
T_TESTS="api.lua code.lua coroutine.lua gc.lua strings.lua memerr.lua tracegc.lua"

# Tests that require the all.lua harness environment (coroutine wrapper, dynamic lib compilation, _port/_soft setup)
STANDALONE_SKIP="attrib.lua big.lua files.lua literals.lua heavy.lua cstack.lua"

# Store results in a temp file: each line is "test_name<TAB>status<TAB>detail"
RESULTS_TMP=$(mktemp /tmp/luazig_results_XXXXXX)

for test_file in ./*.lua; do
    base=$(basename "$test_file" .lua)

    # Skip harness / standalone-interpreter driver
    if [[ "$base" == "all" || "$base" == "main" ]]; then
        printf "%s\t%s\t%s\n" "$base" "SKIP (harness)" "" >> "$RESULTS_TMP"
        continue
    fi

    # Skip tests that unconditionally need the internal C test lib `T`
    skip_t=false
    for tt in $T_TESTS; do
        [[ "$base.lua" == "$tt" ]] && skip_t=true
    done
    if $skip_t; then
        printf "%s\t%s\t%s\n" "$base" "SKIP (needs T)" "" >> "$RESULTS_TMP"
        continue
    fi

    # Skip tests that require all.lua harness environment
    skip_standalone=false
    for st in $STANDALONE_SKIP; do
        [[ "$base.lua" == "$st" ]] && skip_standalone=true
    done
    if $skip_standalone; then
        printf "%s\t%s\t%s\n" "$base" "SKIP (needs all.lua)" "" >> "$RESULTS_TMP"
        continue
    fi

    # Use longer timeout for heavy tests
    t=$TIMEOUT
    for heavy in $HEAVY_TESTS; do
        [[ "$base.lua" == "$heavy" ]] && t=120
    done

    $VERBOSE && echo -n "  $base ... "

    # Run the test, capture stdout and stderr
    tmp_out=$(mktemp /tmp/luazig_out_XXXXXX)
    tmp_err=$(mktemp /tmp/luazig_err_XXXXXX)
    set +e
    run_with_timeout "$t" "$LUAZIG" "$base.lua" > "$tmp_out" 2> "$tmp_err"
    rc=$?
    set -e

    stdout=$(cat "$tmp_out" 2>/dev/null)
    stderr=$(cat "$tmp_err" 2>/dev/null)
    rm -f "$tmp_out" "$tmp_err"

    if [[ $rc -eq 124 ]]; then
        result="TIMEOUT"
        detail="timed out after ${t}s"
    elif [[ $rc -ne 0 ]]; then
        if echo "$stderr" | grep -q 'panic'; then
            result="CRASH"
            detail=$(echo "$stderr" | grep 'panic' | head -1)
        else
            result="FAIL (exit=$rc)"
            detail=$(echo "$stderr" | head -3 | tr '\n' ' ')
        fi
    elif echo "$stdout" | grep -qi 'ok$'; then
        result="PASS"
        detail=""
    elif echo "$stdout" | grep -qi '^\s*ok'; then
        result="PASS"
        detail=""
    elif [[ -z "$stdout" ]] && [[ -z "$stderr" ]]; then
        result="PASS (no output)"
        detail=""
    elif [[ -z "$stdout" ]]; then
        result="PASS (stderr only)"
        detail=""
    else
        result="CHECK"
        detail=$(echo "$stdout" | head -3 | tr '\n' ' ')
    fi

    printf "%s\t%s\t%s\n" "$base" "$result" "$detail" >> "$RESULTS_TMP"

    $VERBOSE && echo "$result"
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

sort "$RESULTS_TMP" -o "$RESULTS_TMP"

while IFS=$'\t' read -r test result detail; do
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
        if [[ -n "${detail:-}" ]]; then
            echo "       $detail"
        fi
    fi
done < "$RESULTS_TMP"

rm -f "$RESULTS_TMP"

echo ""
echo "  PASS:   $passed"
echo "  FAIL:   $failed"
echo "  CRASH:  $crashed"
echo "  TIMEOUT:$timedout"
echo "  SKIP:   $skipped"
echo "  CHECK:  $checked"
echo "  -----"
echo "  TOTAL:  $((passed + failed + crashed + timedout + skipped + checked))"
