#!/usr/bin/env bash
# Structural checks for the skill pack. No network, no Dart toolchain needed.
set -uo pipefail
cd "$(dirname "$0")/.."
errors=0
err() { echo "x $*"; errors=$((errors + 1)); }

python3 -c 'import json,sys; [json.load(open(f)) for f in sys.argv[1:]]' \
  .claude-plugin/plugin.json .claude-plugin/marketplace.json || err "invalid plugin JSON"

for dir in skills/*/; do
  name=$(basename "$dir")
  file="$dir/SKILL.md"
  [ -f "$file" ] || { err "$name: missing SKILL.md"; continue; }
  [ "$(head -1 "$file")" = "---" ] || err "$name: SKILL.md must start with frontmatter"
  fm_name=$(awk '/^---$/{n++; next} n==1 && /^name:/{sub(/^name:[ ]*/, ""); print; exit}' "$file")
  [ "$fm_name" = "$name" ] || err "$name: frontmatter name '$fm_name' does not match folder"
  desc=$(awk '/^---$/{n++; next} n==1 && /^description:/{sub(/^description:[ ]*/, ""); print; exit}' "$file")
  [ -n "$desc" ] || err "$name: missing description"
  [ "${#desc}" -le 1024 ] || err "$name: description longer than 1024 chars"
  for s in "$dir"scripts/*.sh; do
    [ -e "$s" ] || continue
    bash -n "$s" || err "$s: syntax error"
    [ -x "$s" ] || err "$s: not executable"
  done
done

# Built from bytes so this file does not match itself.
emdash=$(printf '\342\200\224')
if grep -rn --exclude-dir=.git "$emdash" . >/dev/null 2>&1; then
  grep -rn --exclude-dir=.git "$emdash" . | head
  err "em dash found (use '-')"
fi

if grep -rnE --exclude-dir=.git 'AIza[0-9A-Za-z_-]{20,}|sk_(live|test)_[0-9A-Za-z]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY|ghp_[0-9A-Za-z]{20,}' . ; then
  err "possible secret committed"
fi

[ "$errors" -eq 0 ] && echo "OK: $(ls -d skills/*/ | wc -l | tr -d ' ') skills valid" || { echo "$errors problem(s)"; exit 1; }
