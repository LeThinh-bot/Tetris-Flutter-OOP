import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // LogicalKeyboardKey
import 'package:flutter/scheduler.dart'; // Ticker (cho AnimationController)
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';

// Score Model
class GameScore {
  final int score;
  final String playerName;
  final DateTime date;

  GameScore({required this.score, required this.playerName, required this.date});

  Map<String, dynamic> toJson() => {
        'score': score,
        'playerName': playerName,
        'date': date.toIso8601String(),
      };

  factory GameScore.fromJson(Map<String, dynamic> json) {
    return GameScore(
      score: json['score'] as int,
      playerName: json['playerName'] as String,
      date: DateTime.parse(json['date'] as String),
    );
  }
}

void main() {
  runApp(const TetrisApp());
}

// ---------- App ----------
class TetrisApp extends StatelessWidget {
  const TetrisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tetris Flutter Full FX',
      theme: ThemeData.dark(useMaterial3: false),
      home: const TetrisPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ---------- Config ----------
const int cols = 10;
const int rows = 20;
const int initialTickMs = 800;
const int minTickMs = 60;
const int speedStepPerLevel = 70; // giảm tick theo mỗi level
const int linesPerLevel = 10; // số dòng cần để lên level
const double cellPadding = 1.5;

// scoring
const Map<int, int> baseScore = {
  1: 100,
  2: 300,
  3: 700,
  4: 2000, // Tetris
};
const int rowUniformBonus = 250; // per uniform row
const int fourRowsSameColorExtra = 1000; // extra if clearing 4 rows all same color

// shape templates
final Map<String, List<List<int>>> shapeTemplates = {
  'I': [
    [1, 1, 1, 1]
  ],
  'O': [
    [1, 1],
    [1, 1]
  ],
  'T': [
    [0, 1, 0],
    [1, 1, 1]
  ],
  'S': [
    [0, 1, 1],
    [1, 1, 0]
  ],
  'Z': [
    [1, 1, 0],
    [0, 1, 1]
  ],
  'J': [
    [1, 0, 0],
    [1, 1, 1]
  ],
  'L': [
    [0, 0, 1],
    [1, 1, 1]
  ],
};

Color randomColor(Random r) {
  int rC = 70 + r.nextInt(180);
  int gC = 70 + r.nextInt(180);
  int bC = 70 + r.nextInt(180);
  return Color.fromARGB(255, rC, gC, bC);
}

// ---------- Models ----------
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
    for (int i = 0; i < n; i++)
      for (int j = 0; j < m; j++) newShape[j][n - 1 - i] = shape[i][j];
    shape = newShape;
  }

  List<Point<int>> cells() {
    List<Point<int>> out = [];
    for (int r = 0; r < shape.length; r++)
      for (int c = 0; c < shape[r].length; c++)
        if (shape[r][c] != 0) out.add(Point<int>(x + c, y + r));
    return out;
  }
}

// board
class Board {
  final List<List<Color?>> grid;
  Board() : grid = List.generate(rows, (_) => List.filled(cols, null));
  bool inside(int x, int y) => x >= 0 && x < cols && y < rows;
  bool collides(Piece p,
      {int dx = 0,
      int dy = 0,
      int level = 1,
      List<Point<int>> blockers = const []}) {
    for (final c in p.cells()) {
      final nx = c.x + dx;
      final ny = c.y + dy;
      if (nx < 0 || nx >= cols || ny < 0 || ny >= rows) return true;
      if (ny >= 0 && grid[ny][nx] != null) return true;
      if (level >= 3 && blockers.any((b) => b.x == nx && b.y == ny)) return true;
    }
    return false;
  }

  void lockPiece(Piece p) {
    for (final c in p.cells()) {
      if (c.y >= 0 && c.y < rows && c.x >= 0 && c.x < cols)
        grid[c.y][c.x] = p.color;
    }
  }

  // Return list of map {row: idx, uniform: bool, color: Color?}
  List<Map<String, dynamic>> clearFullRowsWithInfo() {
    List<Map<String, dynamic>> cleared = [];
    for (int r = rows - 1; r >= 0; r--) {
      bool full = true;
      Set<Color> colors = {};
      for (int c = 0; c < cols; c++) {
        if (grid[r][c] == null) {
          full = false;
          break;
        } else
          colors.add(grid[r][c]!);
      }
      if (full) {
        cleared.add({
          'row': r,
          'uniform': colors.length == 1,
          'color': colors.length == 1 ? colors.first : null
        });
      }
    }
    if (cleared.isNotEmpty) {
      final toRemove =
          cleared.map<int>((m) => m['row'] as int).toList()..sort();
      for (final rr in toRemove.reversed) grid.removeAt(rr);
      while (grid.length < rows) grid.insert(0, List.filled(cols, null));
    }
    return cleared;
  }

  void reset() {
    for (int r = 0; r < rows; r++)
      for (int c = 0; c < cols; c++) grid[r][c] = null;
  }
}

// particle model
class Particle {
  Offset pos;
  Offset vel;
  final Color color;
  double life;
  Particle(this.pos, this.vel, this.color, this.life);
}

// ---------- SHAKE CONTROLLER (for subtle screen shake) ----------
class ShakeController {
  double power = 0.0;
  void trigger(double p) {
    power = max(power, p);
  }

  Offset tick(Random rnd) {
    if (power <= 0) return Offset.zero;
    final off =
        Offset((rnd.nextDouble() - 0.5) * power, (rnd.nextDouble() - 0.5) * power);
    power = power * 0.85;
    if (power < 0.02) power = 0.0;
    return off;
  }
}

// ---------- TetrisPage ----------
class TetrisPage extends StatefulWidget {
  const TetrisPage({super.key});
  @override
  State<TetrisPage> createState() => _TetrisPageState();
}

class _TetrisPageState extends State<TetrisPage>
    with SingleTickerProviderStateMixin { // <--- Cần cho AnimationController
  late Board board;
  late Piece current;
  late Piece nextPiece;
  late Timer timer;
  int tickMs = initialTickMs;
  int score = 0;
  int highScore = 0;
  List<GameScore> topScoresDetailed = [];
  int linesCleared = 0;
  int level = 1;
  bool paused = false;
  bool gameOver = false;
  final Random rnd = Random();
  SharedPreferences? prefs;
  final List<Particle> particles = [];

  // --- Tối ưu Hiệu suất: Thay Ticker bằng AnimationController ---
  late AnimationController _animationController;
  
  final AudioPlayer audioPlayer = AudioPlayer(); // single player for SFX
  final AudioPlayer bgmPlayer = AudioPlayer();
  bool soundAvailable = true;
  bool started = false;
  List<Point<int>> blockers = [];
  List<Map<String, dynamic>> scoreHistory = [];

  String playerName = 'Player';
  late TextEditingController playerNameController;

  // Effect variables
  final ShakeController shake = ShakeController();
  double flashOpacity = 0.0;
  List<Offset> trailPositions = []; // small trail store (board-space)
  double wavePhase = 0.0; // for wave background inside board
  double hue = 0.0; // for gradient dynamic

  @override
  void initState() {
    super.initState();
    playerNameController = TextEditingController(text: playerName);
    board = Board();
    _initPrefs();

    _spawnInitial();
    
    // Timer cho logic game
    timer = Timer.periodic(const Duration(milliseconds: 16), _tick);

    // --- Tối ưu Hiệu suất: Khởi tạo AnimationController ---
    // Controller này sẽ chạy liên tục để cập nhật hiệu ứng (particles, wave, flash)
    // mà không cần gọi setState().
    _animationController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000));
    _animationController.addListener(_updateEffects); // Gọi hàm cập nhật hiệu ứng
    _animationController.repeat();

    // --- Tối ưu Âm thanh: Cấu hình PlayerMode ---
    audioPlayer.setPlayerMode(PlayerMode.lowLatency); // Tối ưu cho SFX
    bgmPlayer.setPlayerMode(PlayerMode.mediaPlayer); // Tối ưu cho BGM
  }

  Future<void> _initPrefs() async {
    prefs = await SharedPreferences.getInstance();
    setState(() {
      highScore = prefs?.getInt('highscore') ?? 0;
      final savedScores = prefs?.getStringList('topScoresDetailed') ?? [];
      topScoresDetailed = savedScores.map((e) {
        try {
          return GameScore.fromJson(jsonDecode(e) as Map<String, dynamic>);
        } catch (_) {
          return GameScore(
              score: 0, playerName: 'Error', date: DateTime.now());
        }
      }).toList();
      topScoresDetailed.sort((b, a) => a.score.compareTo(b.score));
      if (topScoresDetailed.isNotEmpty) {
        highScore = max(highScore, topScoresDetailed.first.score);
      }
    });
  }

  Piece _randomPiece() {
    final keys = shapeTemplates.keys.toList();
    final name = keys[rnd.nextInt(keys.length)];
    final templ = shapeTemplates[name]!;
    final shape = templ.map((r) => [...r]).toList();
    return Piece(name, shape, randomColor(rnd));
  }

  void _spawnInitial() {
    current = _randomPiece()
      ..x = 3
      ..y = 0;
    nextPiece = _randomPiece();
  }

  void _showGameOverDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('GAME OVER! 💥'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Your Final Score: $score',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              TextField(
                controller: playerNameController,
                decoration: const InputDecoration(
                  labelText: 'Enter your name',
                  border: OutlineInputBorder(),
                  hintText: 'Player Name',
                ),
                onChanged: (value) => playerName = value,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                playerName = playerNameController.text.trim().isEmpty
                    ? 'Player'
                    : playerNameController.text.trim();
                _saveScores();
                Navigator.of(context).pop();
                if (mounted) setState(() {});
              },
              child: const Text('OK', style: TextStyle(fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  void _spawnNext() {
    current = nextPiece
      ..x = 3
      ..y = 0;
    nextPiece = _randomPiece();
    if (board.collides(current)) {
      gameOver = true;
      bgmPlayer.stop(); // Dừng nhạc nền
      _animationController.stop(); // Dừng hiệu ứng
      _showGameOverDialog();
      _playSound('assets/sounds/gameover.wav');
    }
  }

  // --- Tối ưu Hiệu suất: Hàm này chạy 60fps mà không gọi setState() ---
  void _updateEffects() {
    // Cập nhật hạt
    _updateParticles();

    // Cập nhật hiệu ứng sóng
    wavePhase += 0.04;
    hue = (hue + 0.3) % 360;

    // Cập nhật hiệu ứng chớp (fade out)
    if (flashOpacity > 0) {
      // Giảm dần opacity, max(0, ...) để không bị âm
      flashOpacity = max(0, flashOpacity - 0.015); // ~1 giây để mờ hẳn
    }

    // Tự động repaint CustomPaint (vì nó lắng nghe _animationController)
  }

  // Hàm _tick cho logic game (chạy bởi Timer 16ms)
  void _tick(Timer t) {
    if (paused || gameOver) return;
    
    // Tích lũy thời gian
    _accumulate += 16;
    
    // Khi đủ thời gian tick (dựa trên level), thực hiện 1 bước game
    if (_accumulate >= tickMs) {
      _accumulate = 0;
      _dropTick(); // Hàm logic chính
    }

    // KHÔNG CẦN setState cho hiệu ứng ở đây nữa
  }

  int _accumulate = 0;

  void _dropTick() {
    // Hàm logic game CẦN setState để cập nhật UI
    setState(() {
      if (!board.collides(current, dy: 1, level: level, blockers: blockers)) {
        current.y += 1;
        _emitTrailForPiece();
      } else {
        board.lockPiece(current);
        shake.trigger(3.5);
        _playSound('assets/sounds/lock.wav');
        final cleared = board.clearFullRowsWithInfo();
        if (cleared.isNotEmpty) {
          int num = cleared.length;
          int base = baseScore[num] ?? 0;
          int bonus = 0;
          for (final info in cleared) {
            if (info['uniform'] as bool) bonus += rowUniformBonus;
          }
          if (num == 4) {
            bool all = true;
            Color? c0;
            for (final info in cleared) {
              if (!(info['uniform'] as bool)) {
                all = false;
                break;
              }
              if (c0 == null)
                c0 = info['color'] as Color?;
              else if (c0 != info['color']) {
                all = false;
                break;
              }
            }
            if (all) bonus += fourRowsSameColorExtra;
            _triggerFlash(); // Kích hoạt chớp
            _playSound('assets/sounds/tetris.wav');
          }
          score += base + bonus;
          linesCleared += num;

          level = (linesCleared ~/ linesPerLevel) + 1;
          tickMs = max(minTickMs, (initialTickMs * pow(0.75, level - 1)).toInt());
          _checkBlockers();

          for (final info in cleared)
            _emitParticlesForRow(
                info['row'] as int, (info['color'] as Color?) ?? Colors.white);
          _playSound('assets/sounds/clear.wav');
        }
        _spawnNext();
      }
    });
  }

  void _emitTrailForPiece() {
    for (final c in current.cells()) {
      if (c.y >= 0) {
        trailPositions.add(Offset(c.x + 0.0, c.y + 0.0));
      }
    }
    if (trailPositions.length > 60)
      trailPositions.removeRange(0, trailPositions.length - 60);
  }

  // --- Tối ưu Hiệu suất: Chỉ cần đặt opacity, _updateEffects sẽ lo việc mờ dần ---
  void _triggerFlash() {
    flashOpacity = 1.0;
    // Không cần Timer.periodic ở đây nữa
  }

  void _emitParticlesForRow(int rowIndex, Color color) {
    final int count = 24;
    for (int i = 0; i < count; i++) {
      final dx = (i / (count - 1)) * cols;
      final px = dx + rnd.nextDouble() * 0.6;
      final py = rowIndex + rnd.nextDouble();
      final pos = Offset(px, py);
      final vel = Offset((rnd.nextDouble() - 0.5) * 3, -2 - rnd.nextDouble() * 2);
      particles.add(Particle(pos, vel, color, 400 + rnd.nextInt(400).toDouble()));
    }
  }

  // --- Tối ưu Hiệu suất: Xóa bỏ setState() trong hàm này ---
  void _updateParticles() {
    final dt = 16.0;
    // bool changed=false; // Không cần nữa
    for (int i = particles.length - 1; i >= 0; i--) {
      final p = particles[i];
      p.life -= dt;
      if (p.life <= 0) {
        particles.removeAt(i);
        continue;
      }
      final dx = p.vel.dx;
      final dy = p.vel.dy + 0.08; // gravity
      p.vel = Offset(dx * 0.996, dy);
      p.pos = p.pos + p.vel * (dt / 16.0);
    }
    if (trailPositions.isNotEmpty) {
      if (trailPositions.isNotEmpty && rnd.nextInt(3) == 0)
        trailPositions.removeAt(0);
    }
    // KHÔNGG GỌI setState() ở đây
  }

  void _playSound(String asset) async {
    if (!soundAvailable) return;
    try {
      // Giữ nguyên logic replaceFirst của bạn, nó đã đúng
      await audioPlayer.play(AssetSource(asset.replaceFirst('assets/', '')));
    } catch (e) {
      soundAvailable = false;
      if (kDebugMode) print('sound err: $e');
    }
  }

  void _playBackgroundMusic() async {
    try {
      await bgmPlayer.setVolume(0.4);
      await bgmPlayer.setReleaseMode(ReleaseMode.loop);
      // Giữ nguyên logic path của bạn
      await bgmPlayer.play(AssetSource('sounds/game-minecraft-gaming-background-music-402451.mp3'));
    } catch (e) {
      if (kDebugMode) print('bgm err: $e');
    }
  }

  void _moveLeft() {
    setState(() {
      if (!board.collides(current, dx: -1)) current.x -= 1;
      _playSound('assets/sounds/move.wav');
    });
  }

  void _moveRight() {
    setState(() {
      if (!board.collides(current, dx: 1)) current.x += 1;
      _playSound('assets/sounds/move.wav');
    });
  }

  void _softDrop() {
    setState(() {
      if (!board.collides(current, dy: 1)) current.y += 1;
      _emitTrailForPiece();
      _playSound('assets/sounds/drop.wav');
    });
  }

  void _hardDrop() {
    setState(() {
      while (!board.collides(current, dy: 1, level: level, blockers: blockers)) {
        current.y += 1;
        _emitTrailForPiece();
      }
      board.lockPiece(current);
      shake.trigger(5.0);
      _playSound('assets/sounds/lock.wav');
      final cleared = board.clearFullRowsWithInfo();
      if (cleared.isNotEmpty) {
        int num = cleared.length;
        int base = baseScore[num] ?? 0;
        int bonus = 0;
        for (final info in cleared)
          if (info['uniform'] as bool) bonus += rowUniformBonus;
        if (num == 4) {
          bool all = true;
          Color? c0;
          for (final info in cleared) {
            if (!(info['uniform'] as bool)) {
              all = false;
              break;
            }
            if (c0 == null)
              c0 = info['color'] as Color?;
            else if (c0 != info['color']) {
              all = false;
              break;
            }
          }
          if (all) bonus += fourRowsSameColorExtra;
          _triggerFlash();
          _playSound('assets/sounds/tetris.wav');
        }
        score += base + bonus;
        linesCleared += num;

        level = (linesCleared ~/ linesPerLevel) + 1;
        tickMs = max(minTickMs, (initialTickMs * pow(0.75, level - 1)).toInt());
        _checkBlockers();

        for (final info in cleared)
          _emitParticlesForRow(
              info['row'] as int, (info['color'] as Color?) ?? Colors.white);
        _playSound('assets/sounds/clear.wav');
      }
      _spawnNext();
    });
  }

  void _rotate() {
    setState(() {
      final saved = Piece.copy(current);
      current.rotate();
      if (board.collides(current)) {
        if (!board.collides(current, dx: -1))
          current.x -= 1;
        else if (!board.collides(current, dx: 1))
          current.x += 1;
        else
          current = saved;
      }
      _playSound('assets/sounds/rotate.wav');
    });
  }

  void _togglePause() {
    setState(() {
      paused = !paused;
      if (paused) {
        _animationController.stop(); // Dừng hiệu ứng
        bgmPlayer.pause(); // Dừng nhạc
      } else {
        _animationController.repeat(); // Chạy lại hiệu ứng
        bgmPlayer.resume(); // Chạy lại nhạc
      }
    });
  }

  void _restart() {
    setState(() {
      board.reset();
      score = 0;
      linesCleared = 0;
      level = 1;
      tickMs = initialTickMs;
      _spawnInitial();
      paused = false;
      gameOver = false;
      particles.clear();
      trailPositions.clear();
      flashOpacity = 0;
    });
    _animationController.repeat(); // Khởi động lại hiệu ứng
    _playBackgroundMusic(); // Chơi lại nhạc nền
  }

  void _saveScores() {
    final newScore = GameScore(
      score: score,
      playerName: playerName.isEmpty ? 'Player' : playerName,
      date: DateTime.now(),
    );
    topScoresDetailed.add(newScore);
    topScoresDetailed.sort((b, a) => a.score.compareTo(b.score));
    if (topScoresDetailed.length > 10)
      topScoresDetailed = topScoresDetailed.sublist(0, 10);

    highScore = max(highScore, score);
    prefs?.setInt('highscore', highScore);

    final StringList =
        topScoresDetailed.map((e) => jsonEncode(e.toJson())).toList();
    prefs?.setStringList('topScoresDetailed', StringList);
  }

  void _checkBlockers() {
    if (level >= 3) {
      blockers.clear();
      final int count = min(level * 2, 12);
      for (int i = 0; i < count; i++) {
        int bx = rnd.nextInt(cols);
        int by = rnd.nextInt(rows ~/ 2) + rows ~/ 2;
        if (board.grid[by][bx] == null) {
          blockers.add(Point<int>(bx, by));
        }
      }
    } else {
      blockers.clear();
    }
  }

  @override
  void dispose() {
    timer.cancel();
    _animationController.removeListener(_updateEffects); // Hủy listener
    _animationController.dispose(); // Hủy controller
    audioPlayer.dispose();
    bgmPlayer.dispose();
    playerNameController.dispose();
    super.dispose();
  }

  void _handleKey(RawKeyEvent event) {
    if (gameOver) return;
    if (event is RawKeyDownEvent && !event.repeat) {
      final k = event.logicalKey;
      if (k == LogicalKeyboardKey.arrowLeft)
        _moveLeft();
      else if (k == LogicalKeyboardKey.arrowRight)
        _moveRight();
      else if (k == LogicalKeyboardKey.arrowDown)
        _softDrop();
      else if (k == LogicalKeyboardKey.space)
        _hardDrop();
      else if (k == LogicalKeyboardKey.arrowUp)
        _rotate();
      else if (k == LogicalKeyboardKey.keyP)
        _togglePause();
      else if (k == LogicalKeyboardKey.keyR) _restart();
    }
  }

  // =========================================================================
  // ==================== BUILD METHOD ĐÃ ĐƯỢC TỐI ƯU ====================
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    if (!started) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow, size: 40),
            label: const Text('PLAY',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
              backgroundColor: Colors.blueAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () {
              setState(() {
                started = true;
                paused = false;
                gameOver = false;
                score = 0;
                linesCleared = 0;
                level = 1;
                tickMs = initialTickMs;
                board.reset();
                particles.clear();
                trailPositions.clear();
                _spawnInitial();
              });
              _animationController.repeat(); // Đảm bảo hiệu ứng chạy khi Play
              _playBackgroundMusic();
            },
          ),
        ),
      );
    }

    final Size size = MediaQuery.of(context).size;
    
    // --- TỐI ƯU BỐ CỤC ---
    // Tính toán không gian tối đa có thể dùng cho bảng game
    // kToolbarHeight là chiều cao AppBar (thường là 56.0)
    // 120 là chiều cao ước tính cho thanh điều khiển (80) + lề (40)
    final double maxSystemUIHeight = kToolbarHeight + 120;
    final double maxBoardHeight = size.height - maxSystemUIHeight;
    final double maxBoardWidth = size.width;
    
    final bool isNarrowScreen = size.width < 600;

    double cellSize;
    if (!isNarrowScreen) {
      // Màn hình rộng (Tablet/Desktop)
      final double boardAreaWidth = size.width * 0.62;
      final double boardAreaHeight = size.height - kToolbarHeight - 120;
      final double cellSizeByHeight = (boardAreaHeight - 40) / rows;
      final double cellSizeByWidth = (boardAreaWidth - 40) / cols;
      cellSize = min(cellSizeByHeight, cellSizeByWidth).clamp(14.0, 36.0);
    } else {
      // Màn hình hẹp (Điện thoại) - ĐÃ SỬA LẠI LOGIC
      // Tính cell size để vừa cả ngang và dọc
      double cellW = (maxBoardWidth - 24) / cols; // 24 = 12*2 margin
      double cellH = (maxBoardHeight - 24) / rows; // 24 = 12*2 margin
      
      // CellSize phải là min() của cả 2 để đảm bảo board
      // không bị tràn ra ngoài theo cả 2 chiều
      cellSize = min(cellW, cellH).clamp(14.0, 36.0);
    }
    // --- KẾT THÚC TỐI ƯU BỐ CỤC ---


    // Kích thước Board cuối cùng
    final boardDisplayWidth = cols * cellSize;
    final boardDisplayHeight = rows * cellSize;

    final Offset shakeOffset = shake.tick(rnd); 

    Widget nextPieceWidget = Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey), color: Colors.black54),
      child: Column(
        children: [
          const Text('Next', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 4),
          if (level < 3)
            CustomPaint(
              size: Size(cellSize*4, cellSize*4), // Next Piece nhỏ hơn
              painter: NextPiecePainter(nextPiece, cellSize, cellPadding),
            )
          else
            Container(
              width: cellSize*4,
              height: cellSize*4,
              alignment: Alignment.center,
              child: const Text(
                "???",
                style: TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );

    Widget infoPanel = SizedBox(
      width: isNarrowScreen ? null : max(240.0, min(320.0, size.width*0.34)),
      child: Column(
        mainAxisAlignment: isNarrowScreen ? MainAxisAlignment.center : MainAxisAlignment.start,
        crossAxisAlignment: isNarrowScreen ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
        children: [
          // Nếu màn hình hẹp, hiển thị thông tin quan trọng theo chiều ngang
          if (isNarrowScreen)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  nextPieceWidget,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRow('Score', '$score'),
                      _infoRow('Lines', '$linesCleared'),
                      _infoRow('Level', '$level'),
                      _infoRow('High Score', '$highScore'),
                      if (paused) const Text('PAUSED', style: TextStyle(color: Colors.yellow, fontSize: 18, fontWeight: FontWeight.bold)),
                      if (gameOver) const Text('GAME OVER', style: TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            )
          else // Màn hình rộng, hiển thị dọc
            ...[
              const SizedBox(height: 8),
              nextPieceWidget,
              const SizedBox(height: 8),
              _infoRow('Score', '$score'),
              _infoRow('Lines', '$linesCleared'),
              _infoRow('Level', '$level'),
              _infoRow('High Score', '$highScore'),
              const SizedBox(height: 8),
              if (paused) const Text('PAUSED', style: TextStyle(color: Colors.yellow, fontSize: 28, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              if (gameOver) const Text('GAME OVER', style: TextStyle(color: Colors.redAccent, fontSize: 28, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            ],

          const SizedBox(height: 8),
          // Bảng Top Scores
          Container(
            padding: const EdgeInsets.all(8),
            margin: isNarrowScreen ? const EdgeInsets.symmetric(horizontal: 12.0) : const EdgeInsets.all(0),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey), color: Colors.black54),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Top Scores:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                // Chỉ hiển thị top 5 trên điện thoại để tiết kiệm không gian
                for (int i=0;i<min(5, topScoresDetailed.length);i++) 
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${i+1}. ${topScoresDetailed[i].playerName}', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
                        Text(
                          '${topScoresDetailed[i].score} (${topScoresDetailed[i].date.day}/${topScoresDetailed[i].date.month})',
                          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.cyanAccent, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (!isNarrowScreen)
            Column( // Chỉ hiển thị 2 dòng này trên màn hình rộng
              children: [
                const SizedBox(height: 20),
                if (paused) const Text('PAUSED', style: TextStyle(color: Colors.yellow, fontSize: 28, fontWeight: FontWeight.bold)),
                if (gameOver) const Text('GAME OVER', style: TextStyle(color: Colors.redAccent, fontSize: 28, fontWeight: FontWeight.bold)),
              ],
            )
        ],
      ),
    );


    Widget tetrisBoard = Transform.translate(
      offset: shakeOffset, 
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black87,
          border: Border.all(color: Colors.grey.shade800, width: 2),
        ),
        child: Stack(
          children: [
            // --- TỐI ƯU HIỆU SUẤT ---
            // CustomPaint sẽ tự động vẽ lại khi _animationController
            // phát ra tín hiệu, mà không cần build lại toàn bộ widget
            CustomPaint(
              size: Size(boardDisplayWidth, boardDisplayHeight),
              painter: BoardPainterWithEffects(
                board,
                current,
                cellSize,
                cellPadding,
                particles,
                level,
                blockers,
                trailPositions,
                wavePhase,
                hue,
                flashOpacity,
                repaint: _animationController, // <--- GẮN CONTROLLER VÀO ĐÂY
              ),
            ),
          ],
        ),
      ),
    );


    // Bố cục chính
    Widget mainContent;
    if (isNarrowScreen) {
      // Bố cục cho điện thoại (Chiều dọc)
      mainContent = Column(
        children: [
          tetrisBoard, // Board ở trên
          // Panel thông tin cuộn được ở dưới
          Expanded(child: SingleChildScrollView(child: infoPanel)), 
        ],
      );
    } else {
      // Bố cục cho tablet/desktop (Chiều ngang)
      mainContent = Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tetrisBoard,
            infoPanel,
          ],
        ),
      );
    }


    return RawKeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKey: _handleKey,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tetris Flutter - Full FX', style: TextStyle(fontSize: 18)),
          centerTitle: true,
          actions: [
            IconButton(icon: Icon(paused ? Icons.play_arrow : Icons.pause), onPressed: _togglePause),
            IconButton(icon: const Icon(Icons.replay), onPressed: _restart),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: mainContent,
            ),
            Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(8), // Giảm padding 1 chút
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ctrlBtn(Icons.arrow_left, _moveLeft),
                  _ctrlBtn(Icons.arrow_drop_down, _softDrop),
                  _ctrlBtn(Icons.arrow_right, _moveRight),
                  _ctrlBtn(Icons.rotate_right, _rotate),
                  _ctrlBtn(Icons.keyboard_double_arrow_down, _hardDrop),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ctrlBtn(IconData ic, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.grey[800], shape: BoxShape.circle),
        child: Icon(ic, size: 32),
      ),
    );
  }

  Widget _infoRow(String name, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4), // Điều chỉnh padding
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name, style: const TextStyle(fontSize: 13)), // Giảm cỡ chữ 1 chút
          SizedBox(width: 10),
          Text(val, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}

// ---------- BoardPainterWithEffects ----------
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

  // --- TỐI ƯU HIỆU SUẤT: Thêm {Listenable? repaint} vào constructor ---
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
    {Listenable? repaint} // Thêm tham số này
  ) : super(repaint: repaint); // Và truyền nó vào super()

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
    final double amp = 6 + (level.clamp(1, 8) * 0.8); // amplitude depends on level slightly
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
      // Slightly bigger glow rect
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

// ---------- NextPiecePainter ----------
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
          canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(cellSize*0.12)), p);
        }
      }
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate)=>true;
}
