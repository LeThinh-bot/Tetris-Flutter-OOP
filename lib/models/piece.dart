import 'dart:ui';
import 'dart:math';

class Piece {
  List<List<int>> shape;
  Color color;
  int x;
  int y;
  final String name;

  Piece(this.name, this.shape, this.color, {this.x = 3, this.y = -1});

  Piece.copy(Piece p)
      : shape = p.shape.map((r) => [...r]).toList(),
        color = p.color,
        x = p.x,
        y = p.y,
        name = p.name;

  void rotate() {
    final n = shape.length;
    final m = shape[0].length;
    List<List<int>> newShape = List.generate(m, (_) => List.filled(n, 0));
    for (int i=0;i<n;i++) for (int j=0;j<m;j++) newShape[j][n-1-i] = shape[i][j];
    shape = newShape;
  }

  List<Point<int>> cells() {
    List<Point<int>> out = [];
    for (int r=0;r<shape.length;r++) for (int c=0;c<shape[r].length;c++) if (shape[r][c]!=0) out.add(Point<int>(x+c, y+r));
    return out;
  }
}