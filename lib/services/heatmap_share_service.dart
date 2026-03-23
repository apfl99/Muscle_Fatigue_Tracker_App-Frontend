import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import '../theme/app_theme.dart';

class HeatmapShareService {
  const HeatmapShareService._();

  static Future<File> buildShareableImage({
    required Uint8List modelPngBytes,
    required int performanceScore,
    required int workoutVolume,
    required String performanceLabel,
    required String volumeLabel,
    required String headline,
    required String subline,
    String watermark = 'Analyzed by MuscleCare',
  }) async {
    final modelImage = await _decodeImage(modelPngBytes);
    const canvasWidth = 1080.0;
    const canvasHeight = 1350.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
    );

    final backgroundPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(canvasWidth, canvasHeight),
        const [
          Color(0xFF09131B),
          Color(0xFF101A27),
          Color(0xFF050A10),
        ],
        const [0.0, 0.54, 1.0],
      );
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
      backgroundPaint,
    );

    final glowPaint = Paint()
      ..color = AppTheme.primaryGreen.withValues(alpha: 0.13)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 66);
    canvas.drawCircle(const Offset(870, 298), 220, glowPaint);

    final modelRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(64, 250, 952, 700),
      const Radius.circular(42),
    );
    canvas.drawRRect(
      modelRect,
      Paint()..color = const Color(0xFF0A111C).withValues(alpha: 0.88),
    );
    canvas.drawRRect(
      modelRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = AppTheme.primaryGreen.withValues(alpha: 0.42),
    );

    canvas.save();
    canvas.clipRRect(modelRect);
    paintImage(
      canvas: canvas,
      rect: modelRect.outerRect,
      image: modelImage,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
    );
    canvas.drawRect(
      modelRect.outerRect,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 250),
          const Offset(0, 980),
          [
            const Color(0xFF000000).withValues(alpha: 0.05),
            const Color(0xFF000000).withValues(alpha: 0.00),
            const Color(0xFF000000).withValues(alpha: 0.26),
          ],
          const [0.0, 0.48, 1.0],
        ),
    );
    canvas.restore();

    await _paintText(
      canvas,
      headline,
      const Offset(66, 72),
      const TextStyle(
        color: Color(0xFFEAF4FF),
        fontSize: 52,
        height: 1.02,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      maxWidth: 760,
      maxLines: 2,
    );
    await _paintText(
      canvas,
      subline,
      const Offset(68, 174),
      const TextStyle(
        color: Color(0xFF9EB0C6),
        fontSize: 25,
        height: 1.30,
        fontWeight: FontWeight.w500,
      ),
      maxWidth: 820,
      maxLines: 2,
    );

    await _paintMetricChip(
      canvas: canvas,
      title: performanceLabel,
      value: performanceScore.toString(),
      rect: const Rect.fromLTWH(74, 996, 450, 182),
    );
    await _paintMetricChip(
      canvas: canvas,
      title: volumeLabel,
      value: workoutVolume.toString(),
      rect: const Rect.fromLTWH(554, 996, 450, 182),
    );

    await _paintText(
      canvas,
      watermark,
      const Offset(640, 1240),
      const TextStyle(
        color: Color(0xFF95A3B9),
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      maxWidth: 360,
      textAlign: TextAlign.right,
    );

    final finalImage = await recorder.endRecording().toImage(
          canvasWidth.toInt(),
          canvasHeight.toInt(),
        );
    final byteData =
        await finalImage.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Failed to encode share image');
    }
    final output = byteData.buffer.asUint8List();
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/musclecare_share_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(output, flush: true);
    return file;
  }

  static Future<void> _paintMetricChip({
    required Canvas canvas,
    required String title,
    required String value,
    required Rect rect,
  }) async {
    final chipRRect = RRect.fromRectAndRadius(rect, const Radius.circular(26));
    canvas.drawRRect(
      chipRRect,
      Paint()..color = const Color(0xFF0E1826).withValues(alpha: 0.84),
    );
    canvas.drawRRect(
      chipRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFF223247),
    );

    await _paintText(
      canvas,
      title,
      Offset(rect.left + 26, rect.top + 24),
      const TextStyle(
        color: Color(0xFF96A7BD),
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
      maxWidth: rect.width - 52,
    );
    await _paintText(
      canvas,
      value,
      Offset(rect.left + 24, rect.top + 76),
      const TextStyle(
        color: Color(0xFF00F58A),
        fontSize: 60,
        height: 0.95,
        fontWeight: FontWeight.w800,
      ),
      maxWidth: rect.width - 52,
    );
  }

  static Future<void> _paintText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style, {
    double maxWidth = double.infinity,
    int? maxLines,
    TextAlign textAlign = TextAlign.left,
  }) async {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
      textAlign: textAlign,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  static Future<ui.Image> _decodeImage(Uint8List bytes) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (image) {
      if (!completer.isCompleted) {
        completer.complete(image);
      }
    });
    return completer.future;
  }
}
