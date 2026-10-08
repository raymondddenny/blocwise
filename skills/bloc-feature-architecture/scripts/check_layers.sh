#!/usr/bin/env bash
# Grep-only layer checker for feature-first bloc apps. Exit 1 lists violations, exit 0 prints OK.
# Usage: check_layers.sh [root]   (default lib/features, run from the app root)
# Override the vendor list with BLOCWISE_VENDOR_SDKS="dio firebase_* ..." (package-name globs).
set -euo pipefail

root="${1:-lib/features}"
root="${root%/}"
root="${root#./}"
vendors="${BLOCWISE_VENDOR_SDKS:-dio firebase_* sentry* posthog* url_launcher share_plus shared_preferences flutter_secure_storage}"
domain_banned="flutter flutter_bloc bloc dio get_it injectable"
data_banned="flutter flutter_bloc bloc"

[[ -d "$root" ]] || { echo "no such directory: $root" >&2; exit 2; }

# package:<any>/<import_root><feature>/... maps back onto "$root/<feature>/...".
case "$root" in
  lib) import_root="" ;;
  lib/* | */lib/*) import_root="${root##*lib/}/" ;;
  *) import_root="-" ;;
esac

normalize() {
  local IFS=/ part out=()
  for part in $1; do
    case "$part" in
      "" | .) ;;
      ..) [[ ${#out[@]} -gt 0 ]] && unset "out[${#out[@]}-1]" && out=("${out[@]+"${out[@]}"}") ;;
      *) out+=("$part") ;;
    esac
  done
  printf '%s' "${out[*]+"${out[*]}"}"
}

matches_any() {
  local name="$1" pattern
  for pattern in $2; do
    # shellcheck disable=SC2053 # glob match is the point
    [[ "$name" == $pattern ]] && return 0
  done
  return 1
}

violations=()
report() { violations+=("$1:$2: $3 ($4)"); }

while IFS= read -r file; do
  rel="${file#"$root"/}"
  feature="${rel%%/*}"
  rest="${rel#*/}"
  layer="${rest%%/*}"
  [[ "$rest" == "$rel" || "$layer" == "$rest" ]] && layer="other"

  while IFS= read -r hit; do
    line="${hit%%:*}"
    uri="$(sed -E "s/^[^'\"]*['\"]([^'\"]+)['\"].*/\1/" <<<"${hit#*:}")"
    target=""
    pkg=""

    case "$uri" in
      dart:*) pkg="$uri" ;;
      package:*)
        pkg="${uri#package:}"
        pkg="${pkg%%/*}"
        path="${uri#package:"$pkg"/}"
        if [[ "$import_root" != "-" && "$path" == "$import_root"* ]]; then
          target="$root/${path#"$import_root"}"
        fi
        ;;
      *) target="$(normalize "$(dirname "$file")/$uri")" ;;
    esac

    if [[ -n "$pkg" && "$pkg" != dart:* ]] && matches_any "$pkg" "$vendors"; then
      report "$file" "$line" "feature code imports vendor SDK '$pkg' directly; go through a port" "$uri"
      continue
    fi

    case "$layer" in
      domain)
        if [[ "$pkg" == "dart:ui" ]] || { [[ -n "$pkg" && "$pkg" != dart:* ]] && matches_any "$pkg" "$domain_banned"; }; then
          report "$file" "$line" "domain imports framework package '$pkg'" "$uri"
          continue
        fi
        if [[ "/$uri/" == */di/* || "/$target/" == */di/* ]]; then
          report "$file" "$line" "domain imports di" "$uri"
          continue
        fi
        ;;
      data)
        if [[ -n "$pkg" && "$pkg" != dart:* ]] && matches_any "$pkg" "$data_banned"; then
          report "$file" "$line" "data imports UI/state package '$pkg'" "$uri"
          continue
        fi
        ;;
    esac

    [[ "$target" == "$root"/* ]] || continue
    trel="${target#"$root"/}"
    tfeature="${trel%%/*}"
    trest="${trel#*/}"
    tlayer="${trest%%/*}"

    if [[ "$tfeature" != "$feature" && ("$tlayer" == data || "$tlayer" == presentation) ]]; then
      report "$file" "$line" "imports another feature's $tlayer ($tfeature); depend on its domain or promote to core" "$uri"
    elif [[ "$layer" == presentation && "$tlayer" == data ]]; then
      report "$file" "$line" "presentation imports data" "$uri"
    elif [[ "$layer" == domain && ("$tlayer" == data || "$tlayer" == presentation || "$tlayer" == di) ]]; then
      report "$file" "$line" "domain imports $tlayer" "$uri"
    elif [[ "$layer" == data && "$tlayer" == presentation ]]; then
      report "$file" "$line" "data imports presentation" "$uri"
    fi
  done < <(grep -nE "^[[:space:]]*(import|export)[[:space:]]+['\"]" "$file" || true)
done < <(find "$root" -type f -name '*.dart' | sort)

if [[ ${#violations[@]} -gt 0 ]]; then
  echo "Layer violations (${#violations[@]}):"
  printf '  %s\n' "${violations[@]}"
  exit 1
fi
echo "OK: no layer violations under $root"
