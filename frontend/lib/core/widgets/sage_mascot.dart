import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// How Sage looks right now — picked by the screen to match the moment.
enum SageMood {
  /// Default: friendly, open eyes, smile.
  happy,

  /// Celebrating (goal met, streak): happy closed "^ ^" eyes, open grin.
  cheer,

  /// Waiting/thinking (AI working, empty states): eyes glance up-left.
  thinking,
}

/// Sage — Study OS's study-buddy mascot (2026-10-19, design v3): a round
/// blue character in a graduation cap. Gives the app the personality the
/// user found missing ("looks generic", "something spontaneous") and turns
/// empty and waiting states into something friendly. Drawn entirely in
/// code (no image assets): scales crisply to any size and costs nothing
/// in APK size.
class SageMascot extends StatelessWidget {
  const SageMascot({super.key, this.size = 96, this.mood = SageMood.happy});

  final double size;
  final SageMood mood;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Sage, the Study OS mascot',
      image: true,
      child: SizedBox.square(dimension: size, child: CustomPaint(painter: _SagePainter(mood))),
    );
  }
}

class _SagePainter extends CustomPainter {
  _SagePainter(this.mood);

  final SageMood mood;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final fill = Paint()..isAntiAlias = true;

    // body — a soft blob, slightly wider than tall, sitting low in the box
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.10, s * 0.26, s * 0.80, s * 0.70), Radius.circular(s * 0.36));
    canvas.drawRRect(body.shift(Offset(0, s * 0.035)), fill..color = StudyOsColors.primaryLedge);
    canvas.drawRRect(body, fill..color = StudyOsColors.primary);
    // belly highlight
    canvas.drawOval(Rect.fromLTWH(s * 0.27, s * 0.62, s * 0.46, s * 0.30), fill..color = const Color(0xFF5B92FF));

    // cheeks
    fill.color = const Color(0xFFFF8FB1).withValues(alpha: 0.75);
    canvas.drawOval(Rect.fromCenter(center: Offset(s * 0.24, s * 0.62), width: s * 0.13, height: s * 0.08), fill);
    canvas.drawOval(Rect.fromCenter(center: Offset(s * 0.76, s * 0.62), width: s * 0.13, height: s * 0.08), fill);

    _eyes(canvas, s);
    _mouth(canvas, s);
    _cap(canvas, s);
  }

  void _eyes(Canvas canvas, double s) {
    final left = Offset(s * 0.35, s * 0.50);
    final right = Offset(s * 0.65, s * 0.50);
    final white = Paint()..color = Colors.white;
    final dark = Paint()..color = const Color(0xFF111A33);

    if (mood == SageMood.cheer) {
      // closed happy arcs: ^ ^
      final arc = Paint()
        ..color = const Color(0xFF111A33)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.045
        ..strokeCap = StrokeCap.round;
      for (final c in [left, right]) {
        canvas.drawArc(Rect.fromCenter(center: c.translate(0, s * 0.02), width: s * 0.15, height: s * 0.13), math.pi * 1.1, math.pi * 0.8, false, arc);
      }
      return;
    }

    final look = mood == SageMood.thinking ? Offset(-s * 0.03, -s * 0.035) : Offset(0, s * 0.01);
    for (final c in [left, right]) {
      canvas.drawCircle(c, s * 0.105, white);
      canvas.drawCircle(c + look, s * 0.058, dark);
      canvas.drawCircle(c + look + Offset(s * 0.02, -s * 0.022), s * 0.019, white);
    }
  }

  void _mouth(Canvas canvas, double s) {
    final center = Offset(s * 0.50, s * 0.665);
    if (mood == SageMood.cheer) {
      final path = Path()
        ..moveTo(center.dx - s * 0.09, center.dy - s * 0.01)
        ..quadraticBezierTo(center.dx, center.dy + s * 0.13, center.dx + s * 0.09, center.dy - s * 0.01)
        ..close();
      canvas.drawPath(path, Paint()..color = const Color(0xFF7A1D35));
      canvas.drawOval(Rect.fromCenter(center: center.translate(0, s * 0.05), width: s * 0.08, height: s * 0.04), Paint()..color = const Color(0xFFFF6F91));
      return;
    }
    final smile = Paint()
      ..color = const Color(0xFF111A33)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.035
      ..strokeCap = StrokeCap.round;
    final width = mood == SageMood.thinking ? s * 0.08 : s * 0.14;
    canvas.drawArc(Rect.fromCenter(center: center, width: width, height: s * 0.09), math.pi * 0.15, math.pi * 0.7, false, smile);
  }

  void _cap(Canvas canvas, double s) {
    final ink = Paint()..color = const Color(0xFF1B2440);
    // A light rim so the dark cap still reads on dark backgrounds (dark
    // mode, the navy avatar circle) as well as light ones.
    final rim = Paint()
      ..color = const Color(0xFF7E95D6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.018
      ..strokeJoin = StrokeJoin.round;
    // band hugging the top of the head
    final band = RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.33, s * 0.20, s * 0.34, s * 0.11), Radius.circular(s * 0.03));
    canvas.drawRRect(band, rim);
    canvas.drawRRect(band, ink);
    // the board, a flat diamond
    final board = Path()
      ..moveTo(s * 0.50, s * 0.04)
      ..lineTo(s * 0.86, s * 0.17)
      ..lineTo(s * 0.50, s * 0.30)
      ..lineTo(s * 0.14, s * 0.17)
      ..close();
    canvas.drawPath(board, ink);
    canvas.drawPath(board, rim);
    // tassel
    final tassel = Paint()
      ..color = StudyOsColors.streak
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.022
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(s * 0.50, s * 0.17), Offset(s * 0.80, s * 0.21), tassel);
    canvas.drawLine(Offset(s * 0.80, s * 0.21), Offset(s * 0.80, s * 0.34), tassel);
    canvas.drawCircle(Offset(s * 0.80, s * 0.36), s * 0.03, Paint()..color = StudyOsColors.streak);
  }

  @override
  bool shouldRepaint(_SagePainter oldDelegate) => oldDelegate.mood != mood;
}
