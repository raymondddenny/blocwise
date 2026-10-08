#!/usr/bin/env bash
# Creates compilable layer stubs for one feature module.
# Usage: new_feature.sh <feature_snake> [--entity Name] [--package name] [--root lib/features]
# Run from the app root (the folder holding pubspec.yaml). Existing files are never overwritten.
set -euo pipefail

usage() {
  echo "usage: $0 <feature_snake> [--entity Name] [--package name] [--root lib/features]" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage
feature="$1"
shift
entity=""
package=""
root="lib/features"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --entity) [[ $# -ge 2 ]] || usage; entity="$2"; shift 2 ;;
    --package) [[ $# -ge 2 ]] || usage; package="$2"; shift 2 ;;
    --root) [[ $# -ge 2 ]] || usage; root="$2"; shift 2 ;;
    -h | --help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

if [[ ! "$feature" =~ ^[a-z][a-z0-9_]*$ ]]; then
  echo "feature must be snake_case (got '$feature')" >&2
  exit 2
fi

if [[ -z "$package" ]]; then
  [[ -f pubspec.yaml ]] || { echo "no pubspec.yaml here; pass --package" >&2; exit 2; }
  package="$(awk '/^name:/ { print $2; exit }' pubspec.yaml | tr -d "\"'")"
  [[ -n "$package" ]] || { echo "could not read name: from pubspec.yaml" >&2; exit 2; }
fi

root="${root%/}"
root="${root#./}"
case "$root" in
  lib) import_root="" ;;
  lib/* | */lib/*) import_root="${root##*lib/}/" ;;
  *) echo "--root must live under a lib/ folder (got '$root')" >&2; exit 2 ;;
esac

pascal() {
  local out="" part
  IFS='_' read -ra parts <<<"$1"
  for part in "${parts[@]}"; do
    [[ -n "$part" ]] && out+="$(tr '[:lower:]' '[:upper:]' <<<"${part:0:1}")${part:1}"
  done
  printf '%s' "$out"
}

snake() {
  sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' <<<"$1" | tr '[:upper:]' '[:lower:]'
}

F="$(pascal "$feature")"
if [[ -z "$entity" ]]; then
  # orders -> Order; anything not ending in a single "s" keeps its name.
  if [[ "$F" == *s && "$F" != *ss ]]; then entity="${F%s}"; else entity="$F"; fi
fi
if [[ ! "$entity" =~ ^[A-Z][A-Za-z0-9]*$ ]]; then
  echo "--entity must be PascalCase (got '$entity')" >&2
  exit 2
fi
E="$entity"
e="$(snake "$E")"
endpoint="/${feature//_/-}"

dir="$root/$feature"
pkg="package:$package/${import_root}$feature"
core="package:$package/core"

emit() {
  local file="$1"
  if [[ -e "$file" ]]; then
    echo "skip   $file"
    cat >/dev/null
    return
  fi
  mkdir -p "$(dirname "$file")"
  cat >"$file"
  echo "create $file"
}

emit "$dir/domain/$e.dart" <<EOF
import 'package:equatable/equatable.dart';

class $E extends Equatable {
  const $E({required this.id});

  final String id;

  @override
  List<Object?> get props => [id];
}
EOF

emit "$dir/domain/${feature}_repository.dart" <<EOF
import '$core/result/result.dart';
import '$pkg/domain/$e.dart';

abstract interface class ${F}Repository {
  FutureResult<List<$E>> fetchAll();
}
EOF

emit "$dir/data/${e}_model.dart" <<EOF
import '$pkg/domain/$e.dart';

class ${E}Model {
  const ${E}Model({required this.id});

  factory ${E}Model.fromJson(Map<String, dynamic> json) =>
      ${E}Model(id: json['id'] as String);

  final String id;

  $E toDomain() => $E(id: id);
}
EOF

emit "$dir/data/${feature}_api.dart" <<EOF
import '$core/network/api_client.dart';
import '$pkg/data/${e}_model.dart';

class ${F}Api {
  const ${F}Api(this._client);

  final ApiClient _client;

  static const _list = '$endpoint';

  Future<List<${E}Model>> fetchAll() async {
    final response = await _client.get(_list);
    return response.jsonList
        .map((item) => ${E}Model.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
EOF

emit "$dir/data/${feature}_repository_impl.dart" <<EOF
import '$core/network/request_guard.dart';
import '$core/result/result.dart';
import '$pkg/data/${feature}_api.dart';
import '$pkg/domain/$e.dart';
import '$pkg/domain/${feature}_repository.dart';

class ${F}RepositoryImpl with RequestGuard implements ${F}Repository {
  ${F}RepositoryImpl(this._api);

  final ${F}Api _api;

  @override
  FutureResult<List<$E>> fetchAll() => guardRead(() async {
    final models = await _api.fetchAll();
    return models.map((model) => model.toDomain()).toList();
  });
}
EOF

emit "$dir/di/${feature}_module.dart" <<EOF
import 'package:get_it/get_it.dart';

import '$core/network/api_client.dart';
import '$pkg/data/${feature}_api.dart';
import '$pkg/data/${feature}_repository_impl.dart';
import '$pkg/domain/${feature}_repository.dart';
import '$pkg/presentation/cubit/${feature}_cubit.dart';

void register${F}Module(GetIt sl) {
  sl
    ..registerLazySingleton<${F}Api>(() => ${F}Api(sl<ApiClient>()))
    ..registerLazySingleton<${F}Repository>(
      () => ${F}RepositoryImpl(sl<${F}Api>()),
    )
    ..registerFactory<${F}Cubit>(() => ${F}Cubit(sl<${F}Repository>()));
}
EOF

emit "$dir/presentation/cubit/${feature}_state.dart" <<EOF
import 'package:equatable/equatable.dart';

import '$core/failures/app_failure.dart';
import '$pkg/domain/$e.dart';

sealed class ${F}State extends Equatable {
  const ${F}State();

  @override
  List<Object?> get props => [];
}

final class ${F}Loading extends ${F}State {
  const ${F}Loading();
}

final class ${F}Loaded extends ${F}State {
  const ${F}Loaded(this.items);

  final List<$E> items;

  @override
  List<Object?> get props => [items];
}

final class ${F}Failed extends ${F}State {
  const ${F}Failed(this.failure);

  final AppFailure failure;

  @override
  List<Object?> get props => [failure];
}
EOF

emit "$dir/presentation/cubit/${feature}_cubit.dart" <<EOF
import 'package:flutter_bloc/flutter_bloc.dart';

import '$core/bloc/safe_emit.dart';
import '$core/result/result.dart';
import '$pkg/domain/${feature}_repository.dart';
import '$pkg/presentation/cubit/${feature}_state.dart';

class ${F}Cubit extends Cubit<${F}State> with SafeEmit<${F}State> {
  ${F}Cubit(this._repository) : super(const ${F}Loading());

  final ${F}Repository _repository;

  Future<void> load() async {
    safeEmit(const ${F}Loading());
    final result = await _repository.fetchAll();
    safeEmit(switch (result) {
      Ok(:final value) => ${F}Loaded(value),
      Err(:final failure) => ${F}Failed(failure),
    });
  }
}
EOF

emit "$dir/presentation/view/${feature}_page.dart" <<EOF
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '$core/di/injector.dart';
import '$pkg/presentation/cubit/${feature}_cubit.dart';
import '$pkg/presentation/view/${feature}_view.dart';

class ${F}Page extends StatelessWidget {
  const ${F}Page({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<${F}Cubit>()..load(),
      child: const ${F}View(),
    );
  }
}
EOF

emit "$dir/presentation/view/${feature}_view.dart" <<EOF
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '$pkg/presentation/cubit/${feature}_cubit.dart';
import '$pkg/presentation/cubit/${feature}_state.dart';

class ${F}View extends StatelessWidget {
  const ${F}View({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<${F}Cubit, ${F}State>(
        builder: (context, state) => switch (state) {
          ${F}Loading() => const Center(child: CircularProgressIndicator()),
          ${F}Loaded(:final items) => ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, index) => ListTile(title: Text(items[index].id)),
          ),
          ${F}Failed() => Center(
            child: TextButton(
              onPressed: () => context.read<${F}Cubit>().load(),
              child: const Text('Retry'),
            ),
          ),
        },
      ),
    );
  }
}
EOF

echo "next: call register${F}Module(sl) from lib/core/di/injector.dart and add a route to ${F}Page."
