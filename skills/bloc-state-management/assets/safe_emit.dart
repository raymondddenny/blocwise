// Target: lib/core/bloc/safe_emit.dart
import 'package:flutter_bloc/flutter_bloc.dart';

/// Drops emissions after [close], so a cubit that awaits a request and then
/// emits does not throw when its page was popped mid-request.
///
/// For a [Bloc], emit through the handler's `Emitter`, which already stops
/// after close; this mixin is for cubits.
mixin SafeEmit<S> on BlocBase<S> {
  void safeEmit(S state) {
    if (isClosed) return;
    emit(state);
  }
}
