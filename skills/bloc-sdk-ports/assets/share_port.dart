// Target: lib/core/platform/share_port.dart
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Opens the system share sheet.
abstract interface class SharePort {
  /// [origin] anchors the popover on iPad; without it the share call fails
  /// there. Get it from [shareOriginOf].
  Future<void> shareText(String text, {String? subject, Rect? origin});
}

/// The only file that imports share_plus.
final class SharePlusAdapter implements SharePort {
  const SharePlusAdapter();

  @override
  Future<void> shareText(String text, {String? subject, Rect? origin}) async {
    await SharePlus.instance.share(
      ShareParams(text: text, subject: subject, sharePositionOrigin: origin),
    );
  }
}

/// The global rect of the widget that owns [context], e.g. the share button.
Rect? shareOriginOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
