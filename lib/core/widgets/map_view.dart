import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../theme/theme.dart';
import '../utils/images.dart';
import 'app_avatar.dart';

/// Something placed on a [RijMap] at a latitude and longitude.
@immutable
class MapMarker {
  const MapMarker({
    required this.lat,
    required this.lng,
    required this.child,
    this.anchor = Alignment.bottomCenter,
    this.key,
  });

  final double lat;
  final double lng;
  final Widget child;

  /// Which point of [child] sits on the spot: the bottom of a pin, the
  /// centre of a dot.
  final Alignment anchor;
  final Key? key;
}

/// A named place drawn on the map.
@immutable
class MapLabel {
  const MapLabel(this.text, this.lat, this.lng);

  final String text;
  final double lat;
  final double lng;
}

/// A quiet street map of an area of Abuja, drawn on the device (no tiles, no
/// data used), with people, jobs and places on it. [kmAcross] sets how much
/// of the city fits across.
///
/// The streets are drawn to look like a neighbourhood, not to be read for
/// directions: directions open the phone's maps app.
class RijMap extends StatelessWidget {
  const RijMap({
    super.key,
    required this.lat,
    required this.lng,
    this.kmAcross = 5,
    this.markers = const [],
    this.labels = const [],
    this.showMe = false,
    this.semanticLabel,
    this.fit = false,
    this.route = const [],
  });

  /// The middle of the map.
  final double lat;
  final double lng;
  final double kmAcross;
  final List<MapMarker> markers;
  final List<MapLabel> labels;

  /// Marks the middle as where the person is.
  final bool showMe;

  /// What the map shows, for screen readers: "Map: 6 AC technicians free
  /// near Wuse 2".
  final String? semanticLabel;

  /// Frames the markers (never zooming in past [kmAcross]) instead of
  /// centring on [lat], [lng].
  final bool fit;

  /// A way between places, as (lat, lng) points, drawn under the markers.
  /// Two points draw as a gentle curve, the way a road bends.
  final List<(double, double)> route;

  // Room left around the markers when framing them: pins stand above their
  // spot (about 44pt tall), and a pill often sits along the top, so a pin's
  // spot stays below the pill plus the pin's height.
  static const _padSide = 30.0;
  static const _padTop = 84.0;
  static const _padBottom = 20.0;

  double _east(double plng) =>
      (plng - lng) * 111.320 * math.cos(lat * math.pi / 180);
  double _north(double plat) => (plat - lat) * 110.574;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    return Semantics(
      label: semanticLabel,
      container: true,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = Size(box.maxWidth, box.maxHeight);
          var pxPerKm = size.width / kmAcross;
          var originE = 0.0;
          var originN = 0.0;
          if (fit && markers.isNotEmpty) {
            final es = [for (final m in markers) _east(m.lng), if (showMe) 0.0];
            final ns = [
              for (final m in markers) _north(m.lat),
              if (showMe) 0.0
            ];
            final minE = es.reduce(math.min), maxE = es.reduce(math.max);
            final minN = ns.reduce(math.min), maxN = ns.reduce(math.max);
            final availW = math.max(40.0, size.width - 2 * _padSide);
            final availH = math.max(40.0, size.height - _padTop - _padBottom);
            final spanE = math.max(maxE - minE, 0.3);
            final spanN = math.max(maxN - minN, 0.3);
            pxPerKm =
                math.min(pxPerKm, math.min(availW / spanE, availH / spanN));
            // Centre the markers' box in the padded area.
            originE = (minE + maxE) / 2;
            originN = (minN + maxN) / 2 + (_padTop - _padBottom) / 2 / pxPerKm;
          }
          Offset project(double plat, double plng) => Offset(
                size.width / 2 + (_east(plng) - originE) * pxPerKm,
                size.height / 2 - (_north(plat) - originN) * pxPerKm,
              );

          // Place markers, nudging any that would sit on top of one already
          // placed, so every pin stays readable.
          final placed = <Rect>[];
          final positions = <MapMarker, Offset>{};
          for (final m in markers) {
            var at = project(m.lat, m.lng);
            if (!_inside(at, size)) continue;
            const w = 84.0, h = 34.0;
            Rect rectAt(Offset o) => Rect.fromCenter(
                center: o.translate(0, -h / 2), width: w, height: h);
            const nudges = [
              Offset.zero,
              Offset(0, 30),
              Offset(0, -30),
              Offset(56, 0),
              Offset(-56, 0),
              Offset(40, 30),
              Offset(-40, 30)
            ];
            for (final n in nudges) {
              final r = rectAt(at + n);
              if (!placed.any((p) => p.overlaps(r.deflate(4)))) {
                at = at + n;
                break;
              }
            }
            placed.add(rectAt(at));
            positions[m] = at;
          }

          return ClipRect(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: CustomPaint(
                      painter: _StreetsPainter(
                        dark: dark,
                        seed: (lat * 1000).round() * 7 + (lng * 1000).round(),
                        labels: [
                          for (final l in labels)
                            (l.text, project(l.lat, l.lng)),
                        ],
                        labelStyle: AppText.caption.copyWith(
                          fontSize: 10.5.sp,
                          fontWeight: FontWeight.w600,
                          color: dark
                              ? const Color(0xFF7C7C84)
                              : const Color(0xFF8E887D),
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ),
                ),
                if (route.length > 1)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RoutePainter(
                        points: [
                          for (final (plat, plng) in route) project(plat, plng)
                        ],
                        color: context.colors.textPrimary,
                        casing: dark ? const Color(0xFF1C1C1F) : Colors.white,
                      ),
                    ),
                  ),
                if (showMe)
                  Positioned(
                    left: project(lat, lng).dx,
                    top: project(lat, lng).dy,
                    child: const FractionalTranslation(
                      translation: Offset(-0.5, -0.5),
                      child: MeDot(),
                    ),
                  ),
                for (final entry in positions.entries)
                  Positioned(
                    key: entry.key.key,
                    left: entry.value.dx,
                    top: entry.value.dy,
                    child: FractionalTranslation(
                      translation: Offset(
                        -(entry.key.anchor.x + 1) / 2,
                        -(entry.key.anchor.y + 1) / 2,
                      ),
                      child: entry.key.child,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  static bool _inside(Offset p, Size size) =>
      p.dx > -20 &&
      p.dy > -20 &&
      p.dx < size.width + 20 &&
      p.dy < size.height + 40;
}

class _StreetsPainter extends CustomPainter {
  _StreetsPainter({
    required this.dark,
    required this.seed,
    required this.labels,
    required this.labelStyle,
  });

  final bool dark;
  final int seed;
  final List<(String, Offset)> labels;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final base = dark ? const Color(0xFF1B1B1F) : const Color(0xFFF2F0EB);
    final block = dark ? const Color(0xFF222227) : const Color(0xFFE9E6DF);
    final park = dark ? const Color(0xFF1D2A21) : const Color(0xFFDDEBD3);
    final water = dark ? const Color(0xFF1A2633) : const Color(0xFFCFE2F0);
    final road = dark ? const Color(0xFF2D2D33) : Colors.white;
    final edge = dark ? const Color(0xFF26262B) : const Color(0xFFE1DDD4);
    final rnd = math.Random(seed);

    canvas.drawRect(Offset.zero & size, Paint()..color = base);

    // City blocks on a slightly turned grid.
    final angle = (rnd.nextDouble() - 0.5) * 0.18;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);
    canvas.translate(-size.width / 2, -size.height / 2);
    final step = 78.0 + rnd.nextDouble() * 18;
    final rowStep = 64.0 + rnd.nextDouble() * 14;
    for (var y = -rowStep; y < size.height + rowStep; y += rowStep) {
      for (var x = -step; x < size.width + step; x += step) {
        final w = step - 14 - rnd.nextDouble() * 6;
        final h = rowStep - 14 - rnd.nextDouble() * 6;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x + 7, y + 7, w, h),
            const Radius.circular(6),
          ),
          Paint()..color = block,
        );
      }
    }
    void line(Offset a, Offset b, double width) {
      canvas.drawLine(
          a,
          b,
          Paint()
            ..color = edge
            ..strokeWidth = width + 2
            ..strokeCap = StrokeCap.round);
      canvas.drawLine(
          a,
          b,
          Paint()
            ..color = road
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round);
    }

    for (var y = 0.0; y < size.height + rowStep; y += rowStep) {
      line(Offset(-step, y), Offset(size.width + step, y), 5);
    }
    for (var x = 0.0; x < size.width + step; x += step) {
      line(Offset(x, -rowStep), Offset(x, size.height + rowStep), 5);
    }
    canvas.restore();

    // A park.
    final parkRect = Rect.fromLTWH(
      size.width * (0.55 + rnd.nextDouble() * 0.25),
      size.height * (0.05 + rnd.nextDouble() * 0.2),
      size.width * 0.22,
      size.height * 0.2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(parkRect, const Radius.circular(14)),
      Paint()..color = park,
    );

    // A stream.
    final y0 = size.height * (0.7 + rnd.nextDouble() * 0.15);
    final river = Path()
      ..moveTo(-20, y0)
      ..cubicTo(size.width * 0.3, y0 - 40, size.width * 0.55, y0 + 50,
          size.width + 20, y0 + 10);
    canvas.drawPath(
        river,
        Paint()
          ..color = water
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16
          ..strokeCap = StrokeCap.round);

    // Two main roads: a crescent and an expressway.
    void main(Path path, double width) {
      canvas.drawPath(
          path,
          Paint()
            ..color = edge
            ..style = PaintingStyle.stroke
            ..strokeWidth = width + 3);
      canvas.drawPath(
          path,
          Paint()
            ..color = road
            ..style = PaintingStyle.stroke
            ..strokeWidth = width);
    }

    main(
      Path()
        ..moveTo(-30, size.height * (0.25 + rnd.nextDouble() * 0.1))
        ..quadraticBezierTo(size.width * 0.55, size.height * 0.05,
            size.width + 30, size.height * (0.4 + rnd.nextDouble() * 0.1)),
      12,
    );
    main(
      Path()
        ..moveTo(size.width * (0.15 + rnd.nextDouble() * 0.1), -30)
        ..quadraticBezierTo(size.width * 0.36, size.height * 0.55,
            size.width * 0.24, size.height + 30),
      10,
    );

    // Place names, with a halo so they read over roads. A name that would
    // sit on top of one already drawn, or hang off the edge, is left out.
    final placed = <Rect>[];
    final bounds = Offset.zero & size;
    for (final (text, at) in labels) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 140);
      final halo = TextPainter(
        text: TextSpan(
          text: text,
          style: labelStyle.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = base,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 140);
      final topLeft = at - Offset(painter.width / 2, painter.height / 2);
      final rect = (topLeft & painter.size).inflate(4);
      if (!bounds.contains(rect.topLeft) ||
          !bounds.contains(rect.bottomRight)) {
        continue;
      }
      if (placed.any(rect.overlaps)) continue;
      placed.add(rect);
      halo.paint(canvas, topLeft);
      painter.paint(canvas, topLeft);
    }
  }

  @override
  bool shouldRepaint(covariant _StreetsPainter old) =>
      old.dark != dark || old.seed != seed || !listEquals(old.labels, labels);
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(
      {required this.points, required this.color, required this.casing});

  final List<Offset> points;
  final Color color;
  final Color casing;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    if (points.length == 2) {
      final a = points.first, b = points.last;
      final d = b - a;
      final bend = Offset(-d.dy, d.dx) * 0.18;
      final mid = Offset.lerp(a, b, 0.5)! + bend;
      path.quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
    } else {
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
    }
    Paint stroke(Color c, double w) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(path, stroke(casing, 8))
      ..drawPath(path, stroke(color, 4));
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) =>
      !listEquals(old.points, points) ||
      old.color != color ||
      old.casing != casing;
}

/// Where the person is: a blue dot with a soft halo.
class MeDot extends StatelessWidget {
  const MeDot({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'You are here',
      child: Container(
        width: 44.w,
        height: 44.w,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.info.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Container(
          width: 16.w,
          height: 16.w,
          decoration: BoxDecoration(
            color: c.info,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 6,
                  offset: Offset(0, 2)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A person on the map: their face in a white ring, and an optional label
/// under it (a distance or a price).
class FacePin extends StatelessWidget {
  const FacePin({
    super.key,
    required this.name,
    this.photo,
    this.size = 40,
    this.label,
    this.selected = false,
    this.free = false,
  });

  final String name;
  final String? photo;
  final double size;
  final String? label;
  final bool selected;

  /// Free now: a green dot on the face.
  final bool free;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = size.w;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: EdgeInsets.all(selected ? 3 : 2.5),
              decoration: BoxDecoration(
                color: selected ? c.brand : Colors.white,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x2E000000),
                      blurRadius: 10,
                      offset: Offset(0, 3)),
                ],
              ),
              child: AppAvatar(name: name, image: imageFor(photo), size: s),
            ),
            if (free)
              Positioned(
                right: 1,
                bottom: 1,
                child: Container(
                  width: s * 0.28,
                  height: s * 0.28,
                  decoration: BoxDecoration(
                    color: c.online,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
        if (label != null) ...[
          SizedBox(height: 4.w),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.5.w),
            decoration: BoxDecoration(
              color: selected ? c.brand : Colors.white,
              borderRadius: AppRadius.pillAll,
              boxShadow: const [
                BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 6,
                    offset: Offset(0, 2)),
              ],
            ),
            child: Text(
              label!,
              style: AppText.caption.copyWith(
                fontSize: 11.sp,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : const Color(0xFF171717),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A job's budget pinned on the map. Urgent jobs get a flash.
class PricePin extends StatelessWidget {
  const PricePin(this.text,
      {super.key, this.urgent = false, this.selected = false});

  final String text;
  final bool urgent;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = selected ? c.brand : Colors.white;
    final fg = selected ? Colors.white : const Color(0xFF171717);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 5.w),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: AppRadius.pillAll,
            boxShadow: const [
              BoxShadow(
                  color: Color(0x29000000),
                  blurRadius: 10,
                  offset: Offset(0, 3)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (urgent) ...[
                Icon(
                  IconsaxPlusBold.flash_1,
                  size: 12.w,
                  color: selected ? Colors.white : c.rating,
                ),
                SizedBox(width: 3.w),
              ],
              Text(
                text,
                style: AppText.caption.copyWith(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
        CustomPaint(size: Size(12.w, 6.w), painter: _Nub(fill)),
      ],
    );
  }
}

class _Nub extends CustomPainter {
  _Nub(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(size.width, 0)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _Nub old) => old.color != color;
}

/// A white pill floating over a map: a filter, a count, an action.
class MapPill extends StatelessWidget {
  const MapPill({
    super.key,
    required this.label,
    this.icon,
    this.dotColor,
    this.onTap,
    this.foreground,
    this.dark = false,
  });

  final String label;
  final IconData? icon;
  final Color? dotColor;
  final VoidCallback? onTap;
  final Color? foreground;

  /// Black instead of white, for the active filter.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = foreground ?? (dark ? Colors.white : c.textPrimary);
    final pill = Container(
      height: 34.w,
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        color: dark ? c.surfaceStrong : c.surface,
        borderRadius: AppRadius.pillAll,
        boxShadow: const [
          BoxShadow(
              color: Color(0x1F000000), blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            Container(
              width: 7.w,
              height: 7.w,
              decoration:
                  BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            SizedBox(width: 6.w),
          ],
          if (icon != null) ...[
            Icon(icon, size: 16.w, color: fg),
            SizedBox(width: 6.w),
          ],
          Text(
            label,
            style: AppText.labelSmall.copyWith(fontSize: 13.sp, color: fg),
          ),
        ],
      ),
    );
    if (onTap == null) return pill;
    return Semantics(
      button: true,
      child: GestureDetector(
          onTap: onTap, behavior: HitTestBehavior.opaque, child: pill),
    );
  }
}
