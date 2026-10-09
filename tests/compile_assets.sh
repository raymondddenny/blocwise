#!/usr/bin/env bash
# Compiles every Dart asset together in a throwaway Flutter app and runs the
# example tests. Needs flutter on PATH and network for `pub add`.
# Usage: bash tests/compile_assets.sh   (KEEP_TMP=1 keeps the temp app)
set -euo pipefail
cd "$(dirname "$0")/.."
repo="$PWD"

# asset (under skills/) | path in the app. Each asset's first line must be
# "// Target: <path>", and every file under skills/*/assets must be listed.
mapping='
bloc-failures-and-results/assets/api_client.dart|lib/core/network/api_client.dart
bloc-failures-and-results/assets/app_failure.dart|lib/core/failures/app_failure.dart
bloc-failures-and-results/assets/dio_api_client.dart|lib/core/network/dio_api_client.dart
bloc-failures-and-results/assets/failure_copy.dart|lib/core/failures/failure_copy.dart
bloc-failures-and-results/assets/request_guard.dart|lib/core/network/request_guard.dart
bloc-failures-and-results/assets/result.dart|lib/core/result/result.dart
bloc-failures-and-results/assets/transaction_status.dart|lib/core/money/transaction_status.dart
bloc-feature-architecture/assets/injector.dart|lib/core/di/injector.dart
bloc-feature-architecture/assets/example_orders/domain/order.dart|lib/features/orders/domain/order.dart
bloc-feature-architecture/assets/example_orders/domain/orders_repository.dart|lib/features/orders/domain/orders_repository.dart
bloc-feature-architecture/assets/example_orders/data/order_model.dart|lib/features/orders/data/order_model.dart
bloc-feature-architecture/assets/example_orders/data/orders_api.dart|lib/features/orders/data/orders_api.dart
bloc-feature-architecture/assets/example_orders/data/orders_repository_impl.dart|lib/features/orders/data/orders_repository_impl.dart
bloc-feature-architecture/assets/example_orders/di/orders_module.dart|lib/features/orders/di/orders_module.dart
bloc-feature-architecture/assets/example_orders/presentation/cubit/orders_cubit.dart|lib/features/orders/presentation/cubit/orders_cubit.dart
bloc-feature-architecture/assets/example_orders/presentation/cubit/orders_state.dart|lib/features/orders/presentation/cubit/orders_state.dart
bloc-feature-architecture/assets/example_orders/presentation/cubit/place_order_cubit.dart|lib/features/orders/presentation/cubit/place_order_cubit.dart
bloc-feature-architecture/assets/example_orders/presentation/view/orders_page.dart|lib/features/orders/presentation/view/orders_page.dart
bloc-feature-architecture/assets/example_orders/presentation/view/orders_view.dart|lib/features/orders/presentation/view/orders_view.dart
bloc-feature-flags/assets/feature_flags.dart|lib/core/flags/feature_flags.dart
bloc-feature-flags/assets/flag_defaults.dart|lib/core/flags/flag_defaults.dart
bloc-feature-flags/assets/flag_keys.dart|lib/core/flags/flag_keys.dart
bloc-feature-flags/assets/flag_defaults_test.dart|test/core/flags/flag_defaults_test.dart
bloc-sdk-ports/assets/analytics_port.dart|lib/core/analytics/analytics_port.dart
bloc-sdk-ports/assets/noop_analytics.dart|lib/core/analytics/noop_analytics.dart
bloc-sdk-ports/assets/recording_analytics.dart|lib/core/analytics/recording_analytics.dart
bloc-sdk-ports/assets/fan_out_analytics.dart|lib/core/analytics/fan_out_analytics.dart
bloc-sdk-ports/assets/crash_reporter_port.dart|lib/core/crash/crash_reporter_port.dart
bloc-sdk-ports/assets/url_launcher_port.dart|lib/core/platform/url_launcher_port.dart
bloc-sdk-ports/assets/share_port.dart|lib/core/platform/share_port.dart
bloc-sdk-ports/assets/redact.dart|lib/core/logging/redact.dart
bloc-sdk-ports/assets/redact_test.dart|test/core/logging/redact_test.dart
bloc-sdk-ports/assets/di_registration_example.dart|lib/core/di/core_ports_module.dart
bloc-state-management/assets/safe_emit.dart|lib/core/bloc/safe_emit.dart
bloc-state-management/assets/action_status.dart|lib/core/bloc/action_status.dart
bloc-state-management/assets/debounce_transformer.dart|lib/core/bloc/debounce_transformer.dart
bloc-ui-effects/assets/show_failure.dart|lib/core/ui/show_failure.dart
bloc-ui-effects/assets/checkout_button.dart|lib/features/orders/presentation/widgets/checkout_button.dart
bloc-ui-effects/assets/orders_effects_listener.dart|lib/features/orders/presentation/widgets/orders_effects_listener.dart
bloc-testing/assets/fake_api_client.dart|test/helpers/fake_api_client.dart
bloc-testing/assets/pump_app.dart|test/helpers/pump_app.dart
bloc-testing/assets/get_it_test_setup.dart|test/helpers/get_it_test_setup.dart
bloc-testing/assets/request_guard_test.dart|test/core/network/request_guard_test.dart
bloc-testing/assets/orders_cubit_test.dart|test/features/orders/presentation/cubit/orders_cubit_test.dart
bloc-testing/assets/orders_repository_impl_test.dart|test/features/orders/data/orders_repository_impl_test.dart
bloc-testing/assets/orders_effects_listener_test.dart|test/features/orders/presentation/widgets/orders_effects_listener_test.dart
bloc-testing/assets/golden_test_template.dart|test/goldens/order_tile_golden_test.dart
'

errors=0
fail() { echo "x $*" >&2; errors=$((errors + 1)); }

mapped=()
while IFS='|' read -r src dest; do
  [ -n "$src" ] || continue
  mapped+=("skills/$src")
  if [ ! -f "skills/$src" ]; then
    fail "mapped asset missing: skills/$src"
  elif [ "$(head -1 "skills/$src")" != "// Target: $dest" ]; then
    fail "skills/$src: first line must be '// Target: $dest'"
  fi
done <<<"$mapping"

while IFS= read -r file; do
  printf '%s\n' "${mapped[@]}" | grep -qxF "$file" || fail "asset not in tests/compile_assets.sh mapping: $file"
done < <(find skills/*/assets -type f ! -name .DS_Store | sort)

[ "$errors" -eq 0 ] || { echo "$errors mapping problem(s)" >&2; exit 1; }

tmp="$(mktemp -d)"
if [ "${KEEP_TMP:-0}" = 1 ]; then
  echo "keeping $tmp"
else
  trap 'rm -rf "$tmp"' EXIT
fi
app="$tmp/app"

echo "== flutter create"
flutter create --project-name app --platforms=android -e "$app" >/dev/null
cd "$app"
flutter pub add flutter_bloc bloc equatable dio get_it go_router url_launcher share_plus \
  dev:bloc_test dev:mocktail dev:fake_async >/dev/null

copied=()
while IFS='|' read -r src dest; do
  [ -n "$src" ] || continue
  mkdir -p "$(dirname "$dest")"
  cp "$repo/skills/$src" "$dest"
  copied+=("$dest")
done <<<"$mapping"

cat >dart_test.yaml <<'EOF'
tags:
  golden:
EOF

echo "== dart format"
dart format --output=none --set-exit-if-changed "${copied[@]}"

echo "== skill scripts"
bash "$repo/skills/bloc-feature-architecture/scripts/new_feature.sh" wallet_transfer --entity Transfer
bash "$repo/skills/bloc-feature-architecture/scripts/check_layers.sh"
bash "$repo/skills/bloc-leak-guard/scripts/leak_audit.sh" --strict lib

echo "== flutter analyze"
flutter analyze --fatal-infos

echo "== flutter test"
flutter test --exclude-tags golden
# Goldens skip off the pinned host (Linux). There, render them into the temp
# app to prove they build and pump; the committed images live in the app.
if [ "$(uname -s)" = Linux ]; then
  flutter test --tags golden --update-goldens
else
  flutter test --tags golden
fi

echo "OK: ${#copied[@]} assets compile and their tests pass"
