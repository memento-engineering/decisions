#!/bin/sh
# Gas City pack doctor shim. Protocol: exit 0 ok, 1 warning, 2 error; the first
# stdout line is the message. Every judgement lives in `decisions doctor`.
# `decisions` runs by name, so the shell's own PATH lookup picks the binary an
# agent would get; `command -v` only names it in a message.
hint='install: brew install memento-engineering/tap/decisions, or a pinned release download (see this pack README)'
skills="${GC_PACK_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}/skills"
out=$(decisions doctor --no-register --skills "$skills" 2>/dev/null)
code=$?
case $code in
  0|1|2) printf '%s\n' "$out"; exit "$code" ;;
  126) printf 'decisions on PATH is not executable\n%s\n' "$hint"; exit 2 ;;
  127) printf 'decisions not found on PATH\n%s\n' "$hint"; exit 2 ;;
esac
printf 'decisions at %s cannot run doctor (exit %s); it predates this pack\n%s\n' "$(command -v decisions)" "$code" "$hint"
exit 2
