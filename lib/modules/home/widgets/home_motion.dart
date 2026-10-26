import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Home's motion. Every piece runs once (or a few beats) and settles, and
/// all of it is skipped when the system asks for reduced motion.

bool _still(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Fades and slides [child] in when it first appears, [order] steps after
/// the first item so a column of cards arrives one after another.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.order = 0,
    this.from = const Offset(0, 14),
  });

  final Widget child;
  final int order;

  /// Starting offset in logical pixels.
  final Offset from;

  static const _step = Duration(milliseconds: 70);
  static const _length = Duration(milliseconds: 520);

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    final delay = Reveal._step * widget.order;
    final total = delay + Reveal._length;
    _c = AnimationController(vsync: this, duration: total);
    // The delay is the start of the interval: no timers to outlive the
    // widget.
    _t = CurvedAnimation(
      parent: _c,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted) return;
    _still(context) ? _c.value = 1 : _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (_, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: widget.from * (1 - _t.value),
          child: child,
        ),
      ),
    );
  }
}

/// Shrinks [child] slightly while a finger is down, without taking the tap
/// from the button inside.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child});

  final Widget child;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: _still(context)
            ? Duration.zero
            : const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A dot that sends out a few soft rings to draw the eye, then rests.
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  static const beats = 3;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  var _beat = 0;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && ++_beat < PulseDot.beats) {
        _c.forward(from: 0);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_beat == 0 && !_c.isAnimating && !_still(context)) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox.square(
      dimension: s,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = Curves.easeOut.transform(_c.value);
          final ring = _c.isAnimating ? t : 0.0;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: [
                if (ring > 0)
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.45 * (1 - ring)),
                    spreadRadius: 8 * ring,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A round progress ring that sweeps to [value] (0–1), and on to each new
/// value.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    required this.color,
    required this.track,
    this.size = 100,
    this.stroke = 10,
    this.child,
  });

  final double value;
  final Color color;
  final Color track;
  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1)),
      duration: _still(context)
          ? Duration.zero
          : const Duration(milliseconds: 950),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => CustomPaint(
        painter: _RingPainter(v, color, track, stroke),
        child: child,
      ),
      child: SizedBox.square(
        dimension: size,
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.value, this.color, this.track, this.stroke);

  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.color != color ||
      old.track != track ||
      old.stroke != stroke;
}
