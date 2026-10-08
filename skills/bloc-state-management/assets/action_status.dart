// Target: lib/core/bloc/action_status.dart
import 'package:app/core/bloc/safe_emit.dart';
import 'package:app/core/failures/app_failure.dart';
import 'package:app/core/result/result.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Lifecycle of one user action (submit, pay, delete).
sealed class ActionStatus extends Equatable {
  const ActionStatus();

  @override
  List<Object?> get props => const [];
}

final class ActionIdle extends ActionStatus {
  const ActionIdle();
}

final class ActionRunning extends ActionStatus {
  const ActionRunning();
}

final class ActionSucceeded<T> extends ActionStatus {
  const ActionSucceeded(this.value);

  final T value;

  @override
  List<Object?> get props => [value];
}

final class ActionFailed extends ActionStatus {
  const ActionFailed(this.failure);

  final AppFailure failure;

  @override
  List<Object?> get props => [failure];
}

/// Runs one action at a time and publishes its outcome as [ActionStatus].
///
/// Subclass once per action (`class PlaceOrderCubit extends ActionCubit<String>`)
/// so two actions on one page never share a provider type.
class ActionCubit<T> extends Cubit<ActionStatus> with SafeEmit<ActionStatus> {
  ActionCubit() : super(const ActionIdle());

  /// Returns null without calling [action] when a run is already in flight.
  /// The guard lives here, not only in the button: a second tap in the same
  /// frame, a keyboard submit or a test can all reach this method.
  Future<Result<T>?> run(FutureResult<T> Function() action) async {
    if (state is ActionRunning) return null;
    safeEmit(const ActionRunning());
    final Result<T> result;
    try {
      result = await action();
    } catch (_) {
      // A Result-returning action should not throw; if it does, do not leave
      // the button disabled forever.
      safeEmit(const ActionIdle());
      rethrow;
    }
    safeEmit(switch (result) {
      Ok(:final value) => ActionSucceeded<T>(value),
      Err(:final failure) => ActionFailed(failure),
    });
    return result;
  }

  void reset() => safeEmit(const ActionIdle());
}
