import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_palette.dart';
import 'app_shell.dart';

/// Placeholder colours for content that is loading: the theme's shimmer
/// tokens ([AppPalette.shimmerBase] and [AppPalette.shimmerHighlight]).
@immutable
class SkeletonColors {
  const SkeletonColors(this.base, this.highlight);

  final Color base;
  final Color highlight;

  static final light = SkeletonColors(
    AppPalette.light.shimmerBase,
    AppPalette.light.shimmerHighlight,
  );
  static final dark = SkeletonColors(
    AppPalette.dark.shimmerBase,
    AppPalette.dark.shimmerHighlight,
  );

  static SkeletonColors of(BuildContext context) {
    final p = AppPalette.of(context);
    return SkeletonColors(p.shimmerBase, p.shimmerHighlight);
  }

  @override
  bool operator ==(Object other) =>
      other is SkeletonColors &&
      other.base == base &&
      other.highlight == highlight;

  @override
  int get hashCode => Object.hash(base, highlight);
}

/// A loading placeholder for one region of a screen. Its [child] is laid
/// out from [Bone]s in the shape of the content to come, so nothing jumps
/// when the content arrives, and a soft highlight sweeps across the bones
/// (cards and other surfaces around them stay as they are).
///
/// One animation drives the whole region, and only the bones repaint for
/// it; nothing rebuilds. The bones are still when the system asks for
/// reduced motion, and the ticker pauses while the region is hidden (an
/// inactive tab, a screen under another) and stops when it's removed. Use
/// it only for content loading; actions keep their spinners.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child, this.label = 'Loading'});

  final Widget child;

  /// What screen readers announce instead of the placeholder shapes.
  final String label;

  static const period = Duration(milliseconds: 1500);

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final _sweep = AnimationController(
    vsync: this,
    duration: Skeleton.period,
  );
  final _region = GlobalKey();
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_still) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: widget.label,
      excludeSemantics: true,
      child: _SkeletonScope(
        sweep: _still ? null : _sweep,
        region: _region,
        child: KeyedSubtree(key: _region, child: widget.child),
      ),
    );
  }
}

class _SkeletonScope extends InheritedWidget {
  const _SkeletonScope({
    required this.sweep,
    required this.region,
    required super.child,
  });

  /// Null when the bones are still.
  final Animation<double>? sweep;

  /// The whole skeleton, which the highlight crosses as one.
  final GlobalKey region;

  static _SkeletonScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SkeletonScope>();

  @override
  bool updateShouldNotify(_SkeletonScope old) =>
      sweep != old.sweep || region != old.region;
}

/// One placeholder shape in the skeleton colour.
class Bone extends StatelessWidget {
  /// A rounded bar.
  const Bone({super.key, this.width, required this.height, this.radius = 8})
    : _style = null,
      widthFactor = null;

  /// A circle, for avatars and icon badges.
  const Bone.circle({super.key, required double size})
    : width = size,
      height = size,
      radius = 999,
      _style = null,
      widthFactor = null;

  /// A line of text in [style]: as tall as that line would be at the
  /// current text size, so the real text takes the same space. Give a
  /// [width], or a [widthFactor] of the space available.
  const Bone.text(TextStyle style, {super.key, this.width, this.widthFactor})
    : _style = style,
      height = null,
      radius = 6;

  final double? width;
  final double? height;
  final double radius;
  final double? widthFactor;
  final TextStyle? _style;

  @override
  Widget build(BuildContext context) {
    final scope = _SkeletonScope.of(context);
    final shape = _BoneShape(
      colors: SkeletonColors.of(context),
      radius: radius,
      sweep: scope?.sweep,
      region: scope?.region,
    );
    final style = _style;
    if (style == null) {
      return SizedBox(width: width, height: height, child: shape);
    }
    final size = MediaQuery.textScalerOf(context).scale(style.fontSize ?? 14);
    final line = SizedBox(
      width: width,
      height: size * (style.height ?? 1.2),
      child: Center(
        child: SizedBox(height: size * 0.75, child: shape),
      ),
    );
    return widthFactor == null
        ? line
        : FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: widthFactor,
            child: line,
          );
  }
}

class _BoneShape extends LeafRenderObjectWidget {
  const _BoneShape({
    required this.colors,
    required this.radius,
    required this.sweep,
    required this.region,
  });

  final SkeletonColors colors;
  final double radius;
  final Animation<double>? sweep;
  final GlobalKey? region;

  @override
  _RenderBone createRenderObject(BuildContext context) =>
      _RenderBone(colors, radius, sweep, region);

  @override
  void updateRenderObject(BuildContext context, _RenderBone bone) => bone
    ..colors = colors
    ..radius = radius
    ..sweep = sweep
    ..region = region;
}

/// Fills its space with a rounded shape. While sweeping it repaints alone
/// (its own layer), drawing its part of the region-wide highlight.
class _RenderBone extends RenderBox {
  _RenderBone(this._colors, this._radius, this._sweep, this.region);

  SkeletonColors _colors;
  set colors(SkeletonColors value) {
    if (value == _colors) return;
    _colors = value;
    markNeedsPaint();
  }

  double _radius;
  set radius(double value) {
    if (value == _radius) return;
    _radius = value;
    markNeedsPaint();
  }

  Animation<double>? _sweep;
  set sweep(Animation<double>? value) {
    if (value == _sweep) return;
    if (attached) _sweep?.removeListener(markNeedsPaint);
    _sweep = value;
    if (attached) _sweep?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  GlobalKey? region;

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
    Size(
      constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
      constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
    ),
  );

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _sweep?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _sweep?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final paint = Paint()..color = _colors.base;
    final sweep = _sweep;
    final box = region?.currentContext?.findRenderObject();
    if (sweep != null && box is RenderBox && box.attached && box.hasSize) {
      // The region's rectangle in this canvas, so all bones share one
      // highlight moving across the whole skeleton.
      final origin = localToGlobal(Offset.zero, ancestor: box);
      paint.shader = LinearGradient(
        begin: const Alignment(-1, -0.3),
        end: const Alignment(1, 0.3),
        colors: [_colors.base, _colors.highlight, _colors.base],
        stops: const [0.35, 0.5, 0.65],
        transform: _Slide(sweep.value),
      ).createShader((offset - origin) & box.size);
    }
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(offset & size, Radius.circular(_radius)),
      paint,
    );
  }
}

/// Moves the highlight from just off the left edge to just off the right.
class _Slide extends GradientTransform {
  const _Slide(this.t);

  final double t;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (2 * t - 1), 0, 0);
}

/// The app's white content card around placeholder [child]ren.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(kSpaceMd),
    this.radius = kRadiusLg,
    this.shadow = kShadowSm,
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final List<BoxShadow>? shadow;

  /// Defaults to the card surface.
  final Color? color;

  @override
  Widget build(BuildContext context) => DmCard(
    color: color ?? AppColors.surfaceContainerLowest,
    padding: padding,
    radius: radius,
    shadow: shadow,
    child: child,
  );
}

/// Bones in a column, [gap] apart. Text bones are already as tall as their
/// lines, so stacked text lines need no gap.
class BoneColumn extends StatelessWidget {
  const BoneColumn({super.key, required this.children, this.gap = 0});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, c) in children.indexed) ...[
        if (i > 0) SizedBox(height: gap),
        c,
      ],
    ],
  );
}
