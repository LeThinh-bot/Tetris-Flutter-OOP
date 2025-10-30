import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:flutter/scheduler.dart'; 
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';

// Import các file model và config
import 'config.dart';
import 'models/board.dart';
import 'models/piece.dart';
import 'models/particle.dart';
import 'effects/shake_controller.dart';
import 'models/game_score.dart';
import 'painters/board_painter.dart';
import 'painters/next_piece_painter.dart';


// ---------- TetrisPage ----------
class TetrisPage extends StatefulWidget {
  const TetrisPage({super.key});
  @override
  State<TetrisPage> createState() => _TetrisPageState();
}

class _TetrisPageState extends State<TetrisPage> with SingleTickerProviderStateMixin {
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
  bool paused=false;
  bool gameOver=false;
  final Random rnd = Random();
  SharedPreferences? prefs;
  final List<Particle> particles = [];
  late Ticker particleTicker;
  final AudioPlayer audioPlayer = AudioPlayer(); 
  final AudioPlayer bgmPlayer = AudioPlayer();
  bool soundAvailable = true;
  bool started = false;
  List<Point<int>> blockers = [];
  
  String playerName = 'Player';
  late TextEditingController playerNameController;

  final ShakeController shake = ShakeController();
  double flashOpacity = 0.0;
  List<Offset> trailPositions = []; 
  double wavePhase = 0.0; 
  double hue = 0.0; 

  @override
  void initState() {
    super.initState();
    // Khởi tạo player name controller
    playerNameController = TextEditingController(text: playerName); 
    board = Board();
    _initPrefs();

    _spawnInitial();
    // Timer chính cho game loop
    timer = Timer.periodic(const Duration(milliseconds:16), _tick); 
    // Ticker cho hiệu ứng
    particleTicker = createTicker((_) {
      _updateParticles();
      wavePhase += 0.04;
      hue = (hue + 0.3) % 360;
    })..start();
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
          return GameScore(score: 0, playerName: 'Error', date: DateTime.now());
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
    final shape = templ.map((r)=>[...r]).toList();
    return Piece(name, shape, randomColor(rnd));
  }

  void _spawnInitial() {
    current = _randomPiece()..x=3..y=0;
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
              Text('Your Final Score: $score', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
                playerName = playerNameController.text.trim().isEmpty ? 'Player' : playerNameController.text.trim();
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
    current = nextPiece..x=3..y=0;
    nextPiece = _randomPiece();
    if (board.collides(current)) {
      gameOver = true;
      _showGameOverDialog(); 
      _playSound('assets/sounds/gameover.wav');
    }
  }

  int _accumulate = 0;
  void _tick(Timer t) {
    if (paused || gameOver) return;
    _accumulate += 16;
    if (_accumulate >= tickMs) {
      _accumulate = 0;
      _dropTick();
    }
    if (shake.power > 0 || flashOpacity > 0 || particles.isNotEmpty || trailPositions.isNotEmpty) {
      if (mounted) setState((){});
    }
  }

  void _dropTick() {
    setState(() {
      if (!board.collides(current, dy:1, level: level, blockers: blockers)) {
        current.y +=1;
        _emitTrailForPiece(); 
      } else {
        board.lockPiece(current);
        shake.trigger(3.5); 
        _playSound('assets/sounds/lock.wav');
        final cleared = board.clearFullRowsWithInfo();
        if (cleared.isNotEmpty) {
          int num = cleared.length;
          int base = baseScore[num] ?? 0;
          int bonus=0;
          for (final info in cleared) {
            if (info['uniform'] as bool) bonus+=rowUniformBonus;
          }
          if (num==4) {
            bool all = true; Color? c0;
            for (final info in cleared) {
              if (!(info['uniform'] as bool)) { all=false; break; }
              if (c0==null) c0 = info['color'] as Color?;
              else if (c0 != info['color']) { all=false; break; }
            }
            if (all) bonus+=fourRowsSameColorExtra;
            _triggerFlash(); 
            _playSound('assets/sounds/tetris.wav');
          }
          score += base + bonus;
          linesCleared += num;

          level = (linesCleared ~/ linesPerLevel) + 1;
          tickMs = max(minTickMs, (initialTickMs * pow(0.75, level - 1)).toInt());
          _checkBlockers();

          for (final info in cleared) _emitParticlesForRow(info['row'] as int, (info['color'] as Color?) ?? Colors.white);
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
    if (trailPositions.length > 60) trailPositions.removeRange(0, trailPositions.length - 60);
  }

  void _triggerFlash() {
    flashOpacity = 1.0;
    Timer.periodic(const Duration(milliseconds:40), (t) {
      flashOpacity -= 0.15;
      if (flashOpacity <= 0) {
        flashOpacity = 0;
        t.cancel();
      }
      if (mounted) setState((){});
    });
  }

  void _emitParticlesForRow(int rowIndex, Color color) {
    final int count = 24;
    for (int i=0;i<count;i++){
      final dx = (i/ (count-1)) * cols;
      final px = dx + rnd.nextDouble()*0.6;
      final py = rowIndex + rnd.nextDouble();
      final pos = Offset(px, py);
      final vel = Offset((rnd.nextDouble()-0.5)*3, -2 - rnd.nextDouble()*2);
      particles.add(Particle(pos, vel, color, 400 + rnd.nextInt(400).toDouble()));
    }
  }

  void _updateParticles() {
    final dt = 16.0;
    bool changed=false;
    for (int i=particles.length-1;i>=0;i--){
      final p = particles[i];
      p.life -= dt;
      if (p.life <= 0) { particles.removeAt(i); changed=true; continue; }
      final dx = p.vel.dx;
      final dy = p.vel.dy + 0.08; 
      p.vel = Offset(dx*0.996, dy);
      p.pos = p.pos + p.vel * (dt/16.0);
      changed = true;
    }
    if (trailPositions.isNotEmpty) {
      if (trailPositions.isNotEmpty && rnd.nextInt(3)==0) trailPositions.removeAt(0);
      changed = true;
    }
    if (changed) if (mounted) setState(()=>{});
  }

  void _playSound(String asset) async {
    if (!soundAvailable) return;
    try {
      await audioPlayer.play(AssetSource(asset.replaceFirst('assets/', '')));
    } catch (e) {
      soundAvailable = false;
      if (kDebugMode) print('sound err: $e');
    }
  }

  void _playBackgroundMusic() async {
    try {
      await bgmPlayer.setReleaseMode(ReleaseMode.loop);
      await bgmPlayer.play(AssetSource('sounds/game-minecraft-gaming-background-music-402451.mp3'));
    } catch (e) {
      if (kDebugMode) print('bgm err: $e');
    }
  }

  void _moveLeft() { setState(() { if (!board.collides(current, dx:-1)) current.x -=1; _playSound('assets/sounds/move.wav'); }); }
  void _moveRight(){ setState(() { if (!board.collides(current, dx:1)) current.x +=1; _playSound('assets/sounds/move.wav'); }); }
  void _softDrop(){ setState(() { if (!board.collides(current, dy:1)) current.y +=1; _emitTrailForPiece(); _playSound('assets/sounds/drop.wav'); }); }
  void _hardDrop(){
    setState(() {
      while(!board.collides(current, dy:1, level: level, blockers: blockers)) {
        current.y +=1;
        _emitTrailForPiece();
      }
      board.lockPiece(current);
      shake.trigger(5.0); 
      _playSound('assets/sounds/lock.wav');
      final cleared = board.clearFullRowsWithInfo();
      if (cleared.isNotEmpty) {
        int num = cleared.length;
        int base = baseScore[num] ?? 0;
        int bonus=0;
        for (final info in cleared) if (info['uniform'] as bool) bonus+=rowUniformBonus;
        if (num==4) {
          bool all = true; Color? c0;
          for (final info in cleared) {
            if (!(info['uniform'] as bool)) { all=false; break; }
            if (c0==null) c0 = info['color'] as Color?;
            else if (c0 != info['color']) { all=false; break; }
          }
          if (all) bonus+=fourRowsSameColorExtra;
          _triggerFlash(); 
          _playSound('assets/sounds/tetris.wav');
        }
        score += base + bonus;
        linesCleared += num;

        level = (linesCleared ~/ linesPerLevel) + 1;
        tickMs = max(minTickMs, (initialTickMs * pow(0.75, level - 1)).toInt());
        _checkBlockers();

        for (final info in cleared) _emitParticlesForRow(info['row'] as int, (info['color'] as Color?) ?? Colors.white);
        _playSound('assets/sounds/clear.wav');
      }
      _spawnNext();
    });
  }
  
  void _rotate(){
    setState((){
      final saved = Piece.copy(current);
      current.rotate();
      if (board.collides(current)) {
        if (!board.collides(current, dx:-1)) current.x -=1;
        else if (!board.collides(current, dx:1)) current.x +=1;
        else current = saved;
      }
      _playSound('assets/sounds/rotate.wav');
    });
  }
  
  void _togglePause(){ setState(()=> paused = !paused); }
  
  void _restart(){
    setState(() {
      board.reset();
      score = 0;
      linesCleared = 0;
      level = 1;
      tickMs = initialTickMs;
      _spawnInitial();
      paused = false; gameOver = false;
      particles.clear();
      trailPositions.clear();
      flashOpacity = 0;
    });
    _playBackgroundMusic();
  }

  void _saveScores(){
    final newScore = GameScore(
      score: score,
      playerName: playerName.isEmpty ? 'Player' : playerName,
      date: DateTime.now(),
    );
    topScoresDetailed.add(newScore);

    topScoresDetailed.sort((b,a)=>a.score.compareTo(b.score));
    if (topScoresDetailed.length>10) topScoresDetailed = topScoresDetailed.sublist(0,10); 

    highScore = max(highScore, score);
    prefs?.setInt('highscore', highScore);

    final StringList = topScoresDetailed.map((e)=>jsonEncode(e.toJson())).toList();
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
  void dispose(){
    timer.cancel();
    particleTicker.stop();
    particleTicker.dispose();
    audioPlayer.dispose();
    bgmPlayer.dispose();
    playerNameController.dispose();
    super.dispose();
  }

  void _handleKey(RawKeyEvent event) {
    if (gameOver) return; 
    if (event is RawKeyDownEvent && !event.repeat) {
      final k = event.logicalKey;
      if (k == LogicalKeyboardKey.arrowLeft) _moveLeft();
      else if (k == LogicalKeyboardKey.arrowRight) _moveRight();
      else if (k == LogicalKeyboardKey.arrowDown) _softDrop();
      else if (k == LogicalKeyboardKey.space) _hardDrop();
      else if (k == LogicalKeyboardKey.arrowUp) _rotate();
      else if (k == LogicalKeyboardKey.keyP) _togglePause();
      else if (k == LogicalKeyboardKey.keyR) _restart();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!started) {
      // Giao diện bắt đầu game
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow, size: 40),
            label: const Text('PLAY', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
              backgroundColor: Colors.blueAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              _playBackgroundMusic();
            },
          ),
        ),
      );
    }

    final Size size = MediaQuery.of(context).size;
    final double maxWidth = size.width;
    final double maxHeight = size.height - 140;
    final double cellSizeByHeight = (maxHeight - 40) / rows;
    final double cellSizeByWidth = (maxWidth * 0.62 - 40) / cols;
    final double cellSize = min(cellSizeByHeight, cellSizeByWidth).clamp(14.0, 36.0);

    final Offset shakeOffset = shake.tick(rnd); 

    return RawKeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKey: _handleKey,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tetris Flutter - Full FX'),
          centerTitle: true,
          actions: [
            IconButton(icon: Icon(paused ? Icons.play_arrow : Icons.pause), onPressed: _togglePause),
            IconButton(icon: const Icon(Icons.replay), onPressed: _restart),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Board 
                    Transform.translate(
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
                            CustomPaint(
                              size: Size(cols*cellSize, rows*cellSize),
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
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Side Info Panel
                    SizedBox(
                      width: max(240.0, min(320.0, size.width*0.34)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          // Next Piece
                          Container(
                            margin: const EdgeInsets.all(8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(border: Border.all(color: Colors.grey), color: Colors.black54),
                            child: Column(
                              children: [
                                const Text('Next', style: TextStyle(fontSize: 16)),
                                const SizedBox(height: 4),
                                if (level < 3)
                                  CustomPaint(
                                    size: Size(cellSize*5, cellSize*5),
                                    painter: NextPiecePainter(nextPiece, cellSize, cellPadding),
                                  )
                                else
                                  Container(
                                    width: cellSize*5,
                                    height: cellSize*5,
                                    alignment: Alignment.center,
                                    child: const Text(
                                      "???",
                                      style: TextStyle(color: Colors.redAccent, fontSize: 24, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Stats
                          _infoRow('Score', '$score'),
                          _infoRow('Lines', '$linesCleared'),
                          _infoRow('Level', '$level'),
                          _infoRow('High Score', '$highScore'),
                          const SizedBox(height: 8),
                          // Top Scores
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(border: Border.all(color: Colors.grey), color: Colors.black54),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Top Scores: (Tên - Điểm/Ngày)', style: TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                for (int i=0;i<topScoresDetailed.length;i++)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('${i+1}. ${topScoresDetailed[i].playerName}', style: const TextStyle(fontWeight: FontWeight.w500)),
                                        Text(
                                          '${topScoresDetailed[i].score} (${topScoresDetailed[i].date.day}/${topScoresDetailed[i].date.month})',
                                          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.cyanAccent, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (paused) const Text('PAUSED', style: TextStyle(color: Colors.yellow, fontSize: 28, fontWeight: FontWeight.bold)),
                          if (gameOver) const Text('GAME OVER', style: TextStyle(color: Colors.redAccent, fontSize: 28, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // On-screen controls
            Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(12),
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
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(name), Text(val, style: const TextStyle(fontWeight: FontWeight.bold))],
      ),
    );
  }
}