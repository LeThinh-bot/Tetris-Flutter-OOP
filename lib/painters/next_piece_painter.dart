// lib/painters/next_piece_painter.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/piece.dart';
import '../config.dart'; 

class NextPiecePainter extends CustomPainter {
  final Piece piece;
  final double cellSize;
  final double padding;
  
  NextPiecePainter(this.piece, this.cellSize, this.padding);
  
  @override
  void paint(Canvas canvas, Size size) {
    Paint p = Paint()..color = piece.color;
    for (int r=0;r<piece.shape.length;r++){
      for (int c=0;c<piece.shape[r].length;c++){
        if (piece.shape[r][c]!=0){
          final rect = Rect.fromLTWH(c*cellSize+padding, r*cellSize+padding, cellSize-2*padding, cellSize-2*padding);
          // *** SỬA LỖI: Dùng drawRRect để bo góc ***
          canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(cellSize*0.12)), p); 
        }
      }
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate)=>true;
}