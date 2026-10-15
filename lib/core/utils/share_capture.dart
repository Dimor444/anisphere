import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Captures the [RepaintBoundary] that [boundaryKey] is attached to as a PNG
/// and opens the system share sheet with it and [text] — how the True Fan
/// card and the AniCard leave the app.
///
/// Waits for the current frame first, so the image is what the screen shows.
/// Does nothing when there is no boundary or no image to share; a failed
/// capture or share throws, and the caller tells the user. [origin] anchors
/// the share popover on iPad.
Future<void> shareBoundaryAsImage({
  required GlobalKey boundaryKey,
  required String fileName,
  required String text,
  Rect? origin,
}) async {
  await WidgetsBinding.instance.endOfFrame;
  final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return;

  final image = await boundary.toImage(pixelRatio: 3.0);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) return;

  final dir = await Directory.systemTemp.createTemp('anisphere_share');
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(data.buffer.asUint8List());
  await Share.shareXFiles([XFile(file.path)], text: text, sharePositionOrigin: origin);
}
