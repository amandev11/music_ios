import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

/// 0 = mini player, 1 = full player. Dragging writes the value directly; release hands the finger's
/// velocity to a spring so the sheet settles the way a thrown object would.
class PlayerSheetController {
  PlayerSheetController(TickerProvider vsync)
      : animation = AnimationController(vsync: vsync, lowerBound: -0.05, upperBound: 1.05, value: 0);

  final AnimationController animation;

  /// Pixels of travel between collapsed and expanded; set by the host from its layout.
  double travel = 600;

  double get value => animation.value.clamp(0.0, 1.0);
  bool get isExpanded => animation.value > 0.5;

  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 320, ratio: 0.82);

  void dragBy(double dy) {
    animation.stop();
    animation.value = (animation.value - dy / travel).clamp(-0.05, 1.05);
  }

  void release(double velocityPxPerSec) {
    final v = -velocityPxPerSec / travel;
    final target = (v.abs() > 0.8 ? v > 0 : animation.value > 0.5) ? 1.0 : 0.0;
    animation.animateWith(SpringSimulation(_spring, animation.value, target, v));
  }

  void expand() => animation.animateWith(SpringSimulation(_spring, animation.value, 1, 0));
  void collapse() => animation.animateWith(SpringSimulation(_spring, animation.value, 0, 0));

  void dispose() => animation.dispose();
}
