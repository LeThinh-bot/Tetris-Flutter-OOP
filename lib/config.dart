import 'dart:ui';
import 'dart:math';

// ---------- Config ----------
const int cols = 10;
const int rows = 20;
const int initialTickMs = 800;
const int minTickMs = 60;
const int speedStepPerLevel = 70;   // giảm tick theo mỗi level
const int linesPerLevel = 10;       // số dòng cần để lên level
const double cellPadding = 1.5;

// scoring
const Map<int,int> baseScore = {
  1: 100,
  2: 300,
  3: 700,
  4: 2000, // Tetris
};
const int rowUniformBonus = 250; // per uniform row
const int fourRowsSameColorExtra = 1000; // extra if clearing 4 rows all same color

// shape templates
final Map<String, List<List<int>>> shapeTemplates = {
  'I': [[1,1,1,1]],
  'O': [[1,1],[1,1]],
  'T': [[0,1,0],[1,1,1]],
  'S': [[0,1,1],[1,1,0]],
  'Z': [[1,1,0],[0,1,1]],
  'J': [[1,0,0],[1,1,1]],
  'L': [[0,0,1],[1,1,1]],
};

Color randomColor(Random r) {
  int rC = 70 + r.nextInt(180);
  int gC = 70 + r.nextInt(180);
  int bC = 70 + r.nextInt(180);
  return Color.fromARGB(255, rC, gC, bC);
}