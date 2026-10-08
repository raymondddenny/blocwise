// Target: lib/core/bloc/debounce_transformer.dart
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

/// Waits until [duration] passes with no new event, then handles only the
/// last one. Handling is sequential, so a slow response cannot overwrite a
/// newer one, but a new query waits for the previous request to finish.
///
/// With `bloc_concurrency` you can cancel the in-flight request instead:
///
///     on<QueryChanged>(
///       _onQueryChanged,
///       transformer: (events, mapper) =>
///           restartable<QueryChanged>()(events.debounced(duration), mapper),
///     );
EventTransformer<E> debounce<E>(Duration duration) =>
    (events, mapper) => events.debounced(duration).asyncExpand(mapper);

extension DebouncedStream<T> on Stream<T> {
  /// Emits an event only after [duration] of silence. A pending event is
  /// dropped when the source closes, because the bloc is closing too.
  Stream<T> debounced(Duration duration) {
    Timer? timer;
    StreamSubscription<T>? subscription;
    late final StreamController<T> controller;
    controller = StreamController<T>(
      onListen: () {
        subscription = listen(
          (event) {
            timer?.cancel();
            timer = Timer(duration, () => controller.add(event));
          },
          onError: controller.addError,
          onDone: () {
            timer?.cancel();
            controller.close();
          },
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        timer?.cancel();
        return subscription?.cancel();
      },
    );
    return controller.stream;
  }
}
