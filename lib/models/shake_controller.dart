import 'dart:ui';
import 'dart:math';

// Shake Controller (for subtle screen shake)
class ShakeController {
  double power = 0.0;

  void trigger(double p){ power = max(power, p); }

  Offset tick(Random rnd){
    if (power <= 0) return Offset.zero;
    final off = Offset((rnd.nextDouble()-0.5)*power, (rnd.nextDouble()-0.5)*power);
    power = power * 0.85;
    if (power < 0.02) power = 0.0;
    return off;
  }
}