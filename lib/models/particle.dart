import 'dart:ui';

class Particle {
  Offset pos;
  Offset vel;
  final Color color;
  double life;
  Particle(this.pos, this.vel, this.color, this.life);
}