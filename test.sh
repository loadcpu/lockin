#!/bin/bash
set -e

WORKDIR="$(pwd)"
MODULE_CACHE_ROOT="$WORKDIR/.build/module-cache"
CLANG_CACHE="$MODULE_CACHE_ROOT/clang"
SWIFTPM_CACHE="$MODULE_CACHE_ROOT/swiftpm"

mkdir -p "$CLANG_CACHE" "$SWIFTPM_CACHE"

run_swift() {
    CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_CACHE" \
    swift "$@"
}

echo "Running TimerInputRuleChecks…"
run_swift run TimerInputRuleChecks

echo ""
echo "✓ All tests passed"
