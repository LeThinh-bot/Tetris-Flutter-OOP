import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/board.dart';
import '../models/piece.dart';
import '../models/particle.dart';
import '../config.dart';

class BoardPainterWithEffects extends CustomPainter {
  final Board board;
  final Piece current;
  final double cellSize;
  final double padding;
  final List<Particle> particles;
  final int level;
  final List<Point<int>> blockers;
  final List<Offset> trailPositions; // board coords
  final double wavePhase;
  final double hue;
  final double flashOpacity;

  BoardPainterWithEffects(
    this.board,
    this.current,
    this.cellSize,
    this.padding,
    this.particles,
    this.level,
    this.blockers,
    this.trailPositions,
    this.wavePhase,
    this.hue,
    this.flashOpacity,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint();

    // 1) dynamic gradient background inside board (based on hue)
    final Color bg1 = HSVColor.fromAHSV(1.0, hue % 360, 0.6, 0.18).toColor();
    final Color bg2 = HSVColor.fromAHSV(1.0, (hue + 50) % 360, 0.8, 0.22).toColor();
    final Rect boardRect = Offset.zero & size;
    p.shader = LinearGradient(colors: [bg1, bg2], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(boardRect);
    canvas.drawRect(boardRect, p);
    p.shader = null;

    // 2) energy wave (inside board only)
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, cellSize * 0.06)
      ..color = Colors.white.withOpacity(0.06);
    final Path path = Path();
    final double w = size.width;
    final double h = size.height;
    final double amp = 6 + (level.clamp(1, 8) * 0.8); 
    for (double x = 0; x <= w; x += 6) {
      final double nx = x / w;
      final double y = h*0.5 + sin((nx * 6.0) + wavePhase) * amp * (0.5 + 0.5 * sin(wavePhase*0.3));
      if (x==0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    canvas.drawPath(path, wavePaint);

    // 3) draw grid cells (board)
    for (int r=0;r<rows;r++){
      for (int c=0;c<cols;c++){
        final color = board.grid[r][c];
        if (color!=null){
          final rect = Rect.fromLTWH(c*cellSize+padding, r*cellSize+padding, cellSize-2*padding, cellSize-2*padding);
          p.color = color;
          canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(cellSize*0.12)), p);
        } else {
          // draw faint cell background for subtle grid
          final rect = Rect.fromLTWH(c*cellSize+padding, r*cellSize+padding, cellSize-2*padding, cellSize-2*padding);
          p.color = Colors.white.withOpacity(0.02);
          canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(cellSize*0.08)), p);
        }
      }
    }

    // 4) trail glow (subtle) - draw behind current piece
    for (int i = 0; i < trailPositions.length; i++) {
      final alpha = (1.0 - (i / trailPositions.length)) * 0.35;
      final pos = trailPositions[i];
      final rect = Rect.fromLTWH(pos.dx*cellSize+padding*0.8, pos.dy*cellSize+padding*0.8, cellSize-2*padding*0.8, cellSize-2*padding*0.8);
      p.maskFilter = MaskFilter.blur(BlurStyle.normal, cellSize*0.45);
      p.color = current.color.withOpacity(alpha);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(cellSize*0.12)), p);
      p.maskFilter = null;
    }

    // 5) draw current piece (with slight glow)
    for (final cc in current.cells()) {
      if (cc.y>=0){
        final rect = Rect.fromLTWH(cc.x*cellSize+padding, cc.y*cellSize+padding, cellSize-2*padding, cellSize-2*padding);
        // glow
        p.color = current.color.withOpacity(0.25);
        p.maskFilter = MaskFilter.blur(BlurStyle.normal, cellSize*0.5);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(cellSize*0.12)), p);
        // solid block
        p.maskFilter = null;
        p.color = current.color;
        canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(cellSize*0.12)), p);
      }
    }

    // 6) blockers
    p.color = Colors.grey.shade700.withOpacity(0.9);
    for (final b in blockers) {
      final rect = Rect.fromLTWH(b.x*cellSize+padding, b.y*cellSize+padding, cellSize-2*padding, cellSize-2*padding);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(cellSize*0.12)), p);
    }

    // 7) particles
    for (final part in particles){
      final px = part.pos.dx * cellSize;
      final py = part.pos.dy * cellSize;
      final r = max(1.0, cellSize*0.12);
      p.color = part.color.withOpacity(max(0, part.life/600.0));
      canvas.drawCircle(Offset(px, py), r, p);
    }

    // 8) flash overlay (draw last)
    if (flashOpacity > 0) {
      final Paint fp = Paint()..color = Colors.white.withOpacity(flashOpacity.clamp(0.0, 1.0));
      canvas.drawRect(boardRect, fp);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}