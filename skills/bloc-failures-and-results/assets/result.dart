// Target: lib/core/result/result.dart
import 'package:app/core/failures/app_failure.dart';

/// What a repository returns instead of throwing.
typedef FutureResult<T> = Future<Result<T>>;

/// The value of an operation that succeeds with nothing to return.
final class Unit {
  const Unit._();

  @override
  String toString() => 'unit';
}

const unit = Unit._();

/// Either an [Ok] value or an [Err] failure. Consume it with a `switch`.
sealed class Result<T> {
  const Result();

  T? get valueOrNull => switch (this) {
    Ok(:final value) => value,
    Err() => null,
  };

  AppFailure? get failureOrNull => switch (this) {
    Ok() => null,
    Err(:final failure) => failure,
  };

  bool get isOk => this is Ok<T>;

  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Ok(:final value) => Ok(transform(value)),
    Err(:final failure) => Err(failure),
  };

  Result<R> flatMap<R>(Result<R> Function(T value) transform) => switch (this) {
    Ok(:final value) => transform(value),
    Err(:final failure) => Err(failure),
  };

  Result<T> mapFailure(AppFailure Function(AppFailure failure) transform) =>
      switch (this) {
        Ok() => this,
        Err(:final failure) => Err(transform(failure)),
      };

  R fold<R>(R Function(AppFailure failure) onErr, R Function(T value) onOk) =>
      switch (this) {
        Ok(:final value) => onOk(value),
        Err(:final failure) => onErr(failure),
      };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

final class Err<T> extends Result<T> {
  const Err(this.failure);

  final AppFailure failure;

  @override
  bool operator ==(Object other) => other is Err<T> && other.failure == failure;

  @override
  int get hashCode => Object.hash(Err, failure);

  @override
  String toString() => 'Err($failure)';
}
