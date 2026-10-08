#!/usr/bin/env bash
# Grep heuristics for resources created in a Dart file with no matching release in
# the same file. A hit is a lead to read, not a proven leak; confirm with DevTools.
#
# Usage: leak_audit.sh [--strict] [dir]   (dir defaults to lib)
#   --strict  exit 1 when there are findings (for CI); otherwise always exit 0.
# Silence one line with a trailing comment: // leak-audit:ignore <reason>
set -euo pipefail

strict=0
dir=lib
for arg in "$@"; do
  case "$arg" in
    --strict) strict=1 ;;
    -h | --help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *) dir="$arg" ;;
  esac
done

if [ ! -d "$dir" ]; then
  echo "leak-audit: directory '$dir' not found (run from the package root)" >&2
  exit 2
fi

# label ~ creation regex ~ release regex (must appear somewhere in the same file)
rules='Timer~\bTimer(\.periodic)?\(~\.cancel\(
StreamSubscription (.listen)~\.listen\(~\.cancel\(
StreamController~\bStreamController(<[^>]*>)?(\.broadcast)?\(~\.close\(
AnimationController~\bAnimationController\(~\.dispose\(
TextEditingController~\bTextEditingController\(~\.dispose\(
FocusNode~\bFocusNode\(~\.dispose\(
ScrollController~\bScrollController\(~\.dispose\(
PageController~\bPageController\(~\.dispose\(
TabController~\bTabController\(~\.dispose\(
addListener~\.addListener\(~\.removeListener\(
Cubit/Bloc built outside a provider~(=|return|=>)[[:space:]]*[A-Z][A-Za-z0-9_]*(Cubit|Bloc)\(~\.close\('

findings=0
files_hit=0
scanned=0

while IFS= read -r file; do
  scanned=$((scanned + 1))
  # Drop comment lines and explicitly ignored lines before counting creations.
  code=$(grep -vE '^[[:space:]]*(//|\*|/\*)|leak-audit:ignore' "$file" || true)
  report=''
  while IFS='~' read -r label create release; do
    count=$(printf '%s\n' "$code" | grep -cE "$create" || true)
    if [ "$label" = 'Cubit/Bloc built outside a provider' ] && [ "$count" -gt 0 ]; then
      # create: lambdas and DI factories hand ownership to the provider / container.
      # The marker may sit on the line before, where dart format wraps the call.
      count=$(printf '%s\n' "$code" | RE="$create" awk '
        BEGIN { owner = "create:|register(Factory|LazySingleton|Singleton)" }
        $0 ~ ENVIRON["RE"] && $0 !~ owner && prev !~ owner { n++ }
        { prev = $0 }
        END { print n + 0 }')
    fi
    if [ "$count" -gt 0 ] && ! grep -qE "$release" "$file"; then
      report="${report}  - ${label}: ${count} created, no ${release//\\/} in file"$'\n'
      findings=$((findings + 1))
    fi
  done <<<"$rules"
  if [ -n "$report" ]; then
    files_hit=$((files_hit + 1))
    printf '%s\n%s' "$file" "$report"
  fi
done < <(find "$dir" -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' \
  ! -name '*.mocks.dart' -type f | sort)

echo
echo "leak-audit: scanned $scanned file(s), $findings finding(s) in $files_hit file(s)."
if [ "$findings" -gt 0 ]; then
  echo "Heuristic only: read each hit, then confirm with a DevTools heap diff (see SKILL.md)."
fi

if [ "$strict" -eq 1 ] && [ "$findings" -gt 0 ]; then
  exit 1
fi
exit 0
