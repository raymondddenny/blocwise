// Target: lib/core/ui/show_failure.dart
import 'package:app/core/failures/app_failure.dart';
import 'package:app/core/failures/failure_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Shows [failure] as a SnackBar with user-facing text from [FailureCopy],
/// never `failure.message`. Expects a `RepositoryProvider<FailureCopy>` above
/// the app; swap the SnackBar for your design system's toast.
void showFailure(BuildContext context, AppFailure failure) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final text = context.read<FailureCopy>().of(failure);
  messenger
    // Replace instead of queueing: three failed taps should not mean three
    // snackbars playing one after another.
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
