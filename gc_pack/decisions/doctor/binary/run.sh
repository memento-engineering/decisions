#!/bin/sh
# Gas City pack doctor shim. Protocol: exit 0 ok, 1 warning, 2 error; the first
# stdout line is the message. Every judgement lives in `decisions doctor`.
hint='install: brew install memento-engineering/tap/decisions, or a pinned release download (see this pack README)'
bin=$(command -v decisions) || { printf 'decisions not found on PATH\n%s\n' "$hint"; exit 2; }
skills="${GC_PACK_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}/skills"
out=$("$bin" doctor --no-register --skills "$skills" 2>/dev/null)
code=$?
case $code in
  0|1|2) printf '%s\n' "$out"; exit "$code" ;;
esac
printf 'decisions at %s cannot run doctor (exit %s); it predates this pack\n%s\n' "$bin" "$code" "$hint"
exit 2
