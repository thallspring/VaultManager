#!/bin/sh
# Headless simulation of Vault Manager with a mocked WoW API (Lua 5.1).
# Usage: sh tests/run_all.sh   (from the repository root)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for f in "$ROOT"/*.lua; do luac5.1 -p "$f" || exit 1; done
for s in "$ROOT"/tests/scenario_*.lua; do
    echo "=== $(basename "$s")"
    lua5.1 "$s" "$ROOT" || exit 1
done
