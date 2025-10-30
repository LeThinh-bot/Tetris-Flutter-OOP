import 'dart:ui';
import 'dart:math';
import '../config.dart';
import 'piece.dart';

class Board {
  final List<List<Color?>> grid;

  Board() : grid = List.generate(rows, (_) => List.filled(cols, null));

  bool inside(int x,int y) => x>=0 && x<cols && y<rows;

  bool collides(Piece p, {int dx=0,int dy=0, int level = 1, List<Point<int>> blockers = const []}) {
    for (final c in p.cells()) {
      final nx = c.x + dx;
      final ny = c.y + dy;
      if (nx < 0 || nx >= cols || ny < 0 || ny >= rows) return true;
      if (ny>=0 && grid[ny][nx]!=null) return true;
      if (level >= 3 && blockers.any((b) => b.x == nx && b.y == ny)) return true;
    }
    return false;
  }

  void lockPiece(Piece p) {
    for (final c in p.cells()) {
      if (c.y>=0 && c.y<rows && c.x>=0 && c.x<cols) grid[c.y][c.x] = p.color;
    }
  }

  // Return list of map {row: idx, uniform: bool, color: Color?}
  List<Map<String,dynamic>> clearFullRowsWithInfo() {
    List<Map<String,dynamic>> cleared = [];
    for (int r=rows-1;r>=0;r--) {
      bool full=true;
      Set<Color> colors = {};
      for (int c=0;c<cols;c++){
        if (grid[r][c]==null) { full=false; break; }
        else colors.add(grid[r][c]!);
      }
      if (full) {
        cleared.add({'row': r, 'uniform': colors.length==1, 'color': colors.length==1 ? colors.first : null});
      }
    }
    if (cleared.isNotEmpty) {
      final toRemove = cleared.map<int>((m)=>m['row'] as int).toList()..sort();
      for (final rr in toRemove.reversed) grid.removeAt(rr);
      while (grid.length<rows) grid.insert(0, List.filled(cols, null));
    }
    return cleared;
  }

  void reset() {
    for (int r=0;r<rows;r++) for (int c=0;c<cols;c++) grid[r][c]=null;
  }
}