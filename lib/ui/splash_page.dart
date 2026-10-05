import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'neo.dart';

double _seg(double p, double a, double b) =>
    ((p - a) / (b - a)).clamp(0.0, 1.0).toDouble();

// ===========================================================================
// 3D ANIME SPLASH
// ===========================================================================

class SplashPage extends StatefulWidget {
  final VoidCallback onDone;
  const SplashPage({super.key, required this.onDone});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3800),
  );
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  Offset _tilt = Offset.zero;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _intro.forward().whenComplete(_finish);
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Neo.bg,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        onPanUpdate: (d) => setState(() {
          _tilt = Offset(
            (_tilt.dx + d.delta.dx / 140).clamp(-1.0, 1.0).toDouble(),
            (_tilt.dy + d.delta.dy / 140).clamp(-1.0, 1.0).toDouble(),
          );
        }),
        onPanEnd: (_) => setState(() => _tilt = Offset.zero),
        child: TweenAnimationBuilder<Offset>(
          tween: Tween<Offset>(begin: Offset.zero, end: _tilt),
          duration: const Duration(milliseconds: 160),
          builder: (context, tilt, _) {
            return AnimatedBuilder(
              animation: Listenable.merge([_intro, _loop]),
              builder: (context, _) => _buildScene(context, tilt),
            );
          },
        ),
      ),
    );
  }

  Widget _buildScene(BuildContext context, Offset tilt) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final p = _intro.value;
    final t = _loop.value * 12.0;
    final twoPi = 2 * math.pi;

    final orbSize = math.min(w * 0.62, h * 0.32);
    final posterW = math.min(w * 0.26, h * 0.17);

    final orbIn = Curves.easeOutBack.transform(_seg(p, 0.04, 0.34));
    final cardIn = Curves.easeOutCubic.transform(_seg(p, 0.18, 0.55));
    final fs = (w * 0.085).clamp(24.0, 44.0).toDouble();

    Widget card(int variant, String ep, bool left) {
      final dir = left ? -1.0 : 1.0;
      final bob = math.sin(t / 12 * twoPi * 3 + (left ? 0 : 1.7)) * 6;
      final m = Matrix4.identity()
        ..setEntry(3, 2, 0.0014)
        ..rotateY(-dir * (0.55 + tilt.dx * 0.25))
        ..rotateX(-tilt.dy * 0.2)
        ..rotateZ(dir * 0.06);
      return Opacity(
        opacity: cardIn,
        child: Transform.translate(
          offset: Offset(dir * (1 - cardIn) * w * 0.5, bob),
          child: Transform(
            alignment: Alignment.center,
            transform: m,
            child: _Poster(width: posterW, variant: variant, ep: ep),
          ),
        ),
      );
    }

    final reveal = _seg(p, 0.42, 0.72);
    final shown = (Neo.appName.length * reveal).ceil();
    final titleText = Neo.appName.substring(0, shown);
    final glitchOn = math.sin(t * 37).abs() > 0.97 && p < 0.95;
    final g = glitchOn ? 3.2 : 0.7;
    final titleStyle = TextStyle(
      fontSize: fs,
      fontWeight: FontWeight.w800,
      letterSpacing: 2,
      fontFamily: Neo.mono,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(painter: _ScenePainter(t: t, p: p, tilt: tilt)),
        ),
        Align(
          alignment: const Alignment(-0.9, -0.16),
          child: card(0, 'EP 01', true),
        ),
        Align(
          alignment: const Alignment(0.9, -0.16),
          child: card(1, 'EP 12', false),
        ),
        Align(
          alignment: const Alignment(0, -0.42),
          child: Transform.scale(
            scale: orbIn,
            child: SizedBox(
              width: orbSize,
              height: orbSize,
              child: CustomPaint(painter: NeoOrbPainter(t: t, tilt: tilt)),
            ),
          ),
        ),
        CustomPaint(painter: _PetalPainter(t: t, p: p)),
        Align(
          alignment: const Alignment(0, 0.40),
          child: Opacity(
            opacity: reveal > 0 ? 1 : 0,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.translate(
                  offset: Offset(-g, 0),
                  child: Text(titleText,
                      style: titleStyle.copyWith(color: Neo.cyan.withValues(alpha: 0.85))),
                ),
                Transform.translate(
                  offset: Offset(g, 0),
                  child: Text(titleText,
                      style: titleStyle.copyWith(color: Neo.pink.withValues(alpha: 0.85))),
                ),
                Text(titleText, style: titleStyle.copyWith(color: Colors.white)),
              ],
            ),
          ),
        ),
        Align(
          alignment: const Alignment(0, 0.50),
          child: Opacity(
            opacity: _seg(p, 0.6, 0.8),
            child: const Text(
              'ANIME  ·  STREAMING  ·  HD',
              style: TextStyle(
                color: Neo.muted,
                fontFamily: Neo.mono,
                fontSize: 11,
                letterSpacing: 3,
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(36, 0, 36, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'LOADING',
                        style: TextStyle(
                          color: Neo.muted,
                          fontFamily: Neo.mono,
                          fontSize: 10,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        '${(p * 100).round()}%',
                        style: const TextStyle(
                          color: Neo.cyan,
                          fontFamily: Neo.mono,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 4,
                      child: Stack(
                        children: [
                          Container(color: Colors.white.withValues(alpha: 0.1)),
                          FractionallySizedBox(
                            widthFactor: p,
                            child: Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Neo.cyan, Neo.violet, Neo.pink],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Opacity(
                    opacity: _seg(p, 0.5, 0.7) * 0.6,
                    child: const Text(
                      'TAP TO SKIP  ·  DRAG TO TILT',
                      style: TextStyle(
                        color: Neo.muted,
                        fontFamily: Neo.mono,
                        fontSize: 9,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: Opacity(
            opacity: (1 - _seg(p, 0.0, 0.10)),
            child: const ColoredBox(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// REUSABLE ORB (also used on login / signup)
// ===========================================================================

class NeoOrb extends StatefulWidget {
  final double size;
  const NeoOrb({super.key, this.size = 110});

  @override
  State<NeoOrb> createState() => _NeoOrbState();
}

class _NeoOrbState extends State<NeoOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
            painter: NeoOrbPainter(t: _c.value * 12.0, tilt: Offset.zero),
          ),
        ),
      ),
    );
  }
}

class _V {
  final double x, y, z;
  const _V(this.x, this.y, this.z);
}

class NeoOrbPainter extends CustomPainter {
  final double t;
  final Offset tilt;
  NeoOrbPainter({required this.t, required this.tilt});

  // rotate around X then Y; returns rotated (unprojected) vector
  _V _rot(double x, double y, double z, double ax, double ay) {
    final y1 = y * math.cos(ax) - z * math.sin(ax);
    final z1 = y * math.sin(ax) + z * math.cos(ax);
    final x2 = x * math.cos(ay) + z1 * math.sin(ay);
    final z2 = -x * math.sin(ay) + z1 * math.cos(ay);
    return _V(x2, y1, z2);
  }

  Offset _proj(_V v, Offset c, double s) {
    final k = 3.0 / (3.0 + v.z);
    return Offset(c.dx + v.x * k * s, c.dy + v.y * k * s);
  }

  void _ring(Canvas canvas, Offset c, double s, double ax, double ay,
      Color color, double width) {
    const n = 64;
    final pts = <_V>[];
    for (int i = 0; i <= n; i++) {
      final a = i / n * 2 * math.pi;
      pts.add(_rot(math.cos(a), math.sin(a), 0, ax, ay));
    }
    final glow = Path()..moveTo(_proj(pts[0], c, s).dx, _proj(pts[0], c, s).dy);
    for (int i = 1; i <= n; i++) {
      final o = _proj(pts[i], c, s);
      glow.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      glow,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 3
        ..color = color.withValues(alpha: 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    for (int i = 0; i < n; i++) {
      final zMid = (pts[i].z + pts[i + 1].z) / 2;
      final alpha = (0.2 + 0.8 * ((1 - zMid) / 2)).clamp(0.1, 1.0).toDouble();
      canvas.drawLine(
        _proj(pts[i], c, s),
        _proj(pts[i + 1], c, s),
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.46;
    final base = t / 12 * 2 * math.pi;
    final tx = tilt.dy * 0.6;
    final ty = tilt.dx * 0.8;

    canvas.drawCircle(
      c,
      r * 1.15,
      Paint()
        ..shader = RadialGradient(colors: [
          Neo.violet.withValues(alpha: 0.30),
          Neo.cyan.withValues(alpha: 0.0),
        ]).createShader(Rect.fromCircle(center: c, radius: r * 1.15)),
    );

    _ring(canvas, c, r, 1.15 + tx, base + ty, Neo.cyan, 2.0);
    _ring(canvas, c, r * 0.84, 0.45 + tx, -base * 2 + ty, Neo.violet, 1.8);
    _ring(canvas, c, r * 0.68, base + tx, 0.9 + ty, Neo.pink, 1.6);

    // orbiting spark on outer ring
    final sp = _rot(math.cos(base * 3), math.sin(base * 3), 0, 1.15 + tx, base + ty);
    final spo = _proj(sp, c, r);
    canvas.drawCircle(
      spo,
      5,
      Paint()
        ..color = Colors.white
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // 3D play prism (extruded triangle)
    final ay = 0.7 * math.sin(base) + ty;
    final ax = tx;
    const sc = 1.45;
    const verts = [
      [-0.30, -0.40],
      [-0.30, 0.40],
      [0.42, 0.0],
    ];
    final front = <Offset>[];
    final back = <Offset>[];
    for (final v in verts) {
      front.add(_proj(_rot(v[0] * sc, v[1] * sc, -0.22, ax, ay), c, r * 0.62));
      back.add(_proj(_rot(v[0] * sc, v[1] * sc, 0.22, ax, ay), c, r * 0.62));
    }
    Path poly(List<Offset> o) => Path()
      ..moveTo(o[0].dx, o[0].dy)
      ..lineTo(o[1].dx, o[1].dy)
      ..lineTo(o[2].dx, o[2].dy)
      ..close();

    final bp = poly(back);
    final fp = poly(front);
    canvas.drawPath(bp, Paint()..color = Neo.violet.withValues(alpha: 0.25));
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Neo.violet.withValues(alpha: 0.8);
    canvas.drawPath(bp, edge);
    for (int i = 0; i < 3; i++) {
      canvas.drawLine(front[i], back[i], edge);
    }
    canvas.drawPath(
      fp,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = Neo.cyan.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawPath(
      fp,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Neo.cyan, Neo.violet],
        ).createShader(fp.getBounds()),
    );
    canvas.drawPath(
      fp,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant NeoOrbPainter old) =>
      old.t != t || old.tilt != tilt;
}

// ===========================================================================
// POSTER CARD (procedural anime-style key art, no assets needed)
// ===========================================================================

class _Poster extends StatelessWidget {
  final double width;
  final int variant;
  final String ep;
  const _Poster({required this.width, required this.variant, required this.ep});

  @override
  Widget build(BuildContext context) {
    final col = [Neo.pink, Neo.cyan, Neo.violet][variant % 3];
    return Container(
      width: width,
      height: width * 1.5,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: col.withValues(alpha: 0.65)),
        boxShadow: [
          BoxShadow(color: col.withValues(alpha: 0.35), blurRadius: 24),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _PosterPainter(variant)),
            Positioned(
              left: 8,
              bottom: 8,
              child: NeoTag(ep, color: col),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterPainter extends CustomPainter {
  final int variant;
  _PosterPainter(this.variant);

  @override
  void paint(Canvas canvas, Size s) {
    final pal = [
      [const Color(0xFF1B1464), Neo.pink],
      [const Color(0xFF0B3C5D), Neo.cyan],
      [const Color(0xFF2A1458), Neo.violet],
    ][variant % 3];
    final rect = Offset.zero & s;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [pal[0], pal[1].withValues(alpha: 0.85)],
        ).createShader(rect),
    );
    canvas.drawCircle(
      Offset(s.width * 0.5, s.height * 0.38),
      s.width * 0.27,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
    final city = Paint()..color = const Color(0xFF080A14);
    final rnd = math.Random(variant + 5);
    double x = 0;
    while (x < s.width) {
      final bw = s.width * (0.1 + rnd.nextDouble() * 0.12);
      final bh = s.height * (0.18 + rnd.nextDouble() * 0.22);
      canvas.drawRect(Rect.fromLTWH(x, s.height - bh, bw, bh), city);
      x += bw;
    }
    final slash = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.8;
    canvas.drawLine(Offset(s.width * 0.05, s.height * 0.22),
        Offset(s.width * 0.95, s.height * 0.56), slash);
    canvas.drawLine(Offset(s.width * 0.2, s.height * 0.12),
        Offset(s.width * 0.85, s.height * 0.4), slash..strokeWidth = 1);
    // 4-point sparkle
    final c = Offset(s.width * 0.8, s.height * 0.16);
    final r = s.width * 0.09;
    final star = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r * 0.25, c.dy - r * 0.25)
      ..lineTo(c.dx + r, c.dy)
      ..lineTo(c.dx + r * 0.25, c.dy + r * 0.25)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - r * 0.25, c.dy + r * 0.25)
      ..lineTo(c.dx - r, c.dy)
      ..lineTo(c.dx - r * 0.25, c.dy - r * 0.25)
      ..close();
    canvas.drawPath(star, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _PosterPainter old) => old.variant != variant;
}

// ===========================================================================
// SCENE: neon sky, skyline parallax, retro 3D perspective grid, speed lines
// ===========================================================================

class _ScenePainter extends CustomPainter {
  final double t, p;
  final Offset tilt;
  _ScenePainter({required this.t, required this.p, required this.tilt});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final hz = h * 0.58;
    final twoPi = 2 * math.pi;

    // sky
    final skyRect = Rect.fromLTWH(0, 0, w, hz);
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF05060F), Color(0xFF140B35), Color(0xFF3A1459)],
        ).createShader(skyRect),
    );

    // stars
    final sr = math.Random(7);
    for (int i = 0; i < 45; i++) {
      final sx = sr.nextDouble() * w;
      final sy = sr.nextDouble() * hz * 0.75;
      final a = 0.3 + 0.7 * (0.5 + 0.5 * math.sin(twoPi * (t / 12) * (1 + i % 3) + i));
      canvas.drawCircle(
        Offset(sx - tilt.dx * 4, sy),
        0.6 + sr.nextDouble() * 0.9,
        Paint()..color = Colors.white.withValues(alpha: a * 0.8),
      );
    }

    // retro sun
    final sunR = math.min(w * 0.2, h * 0.14);
    final sunC = Offset(w / 2 - tilt.dx * 10, hz - sunR * 0.55);
    canvas.drawCircle(
      sunC,
      sunR * 2.3,
      Paint()
        ..shader = RadialGradient(colors: [
          Neo.pink.withValues(alpha: 0.35),
          Neo.pink.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: sunC, radius: sunR * 2.3)),
    );
    final sunRect = Rect.fromCircle(center: sunC, radius: sunR);
    canvas.drawCircle(
      sunC,
      sunR,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFD166), Neo.pink, Neo.violet],
        ).createShader(sunRect),
    );
    for (int i = 0; i < 5; i++) {
      final y = sunC.dy + sunR * 0.05 + i * sunR * 0.17;
      canvas.drawRect(
        Rect.fromLTWH(sunC.dx - sunR, y, sunR * 2, 1.5 + i * 1.6),
        Paint()..color = const Color(0xFF1A0B3A),
      );
    }

    // skyline (3 parallax layers)
    _skyline(canvas, w, hz, 21, h * 0.06, h * 0.16, const Color(0xFF150C33), tilt.dx * -6, false);
    _skyline(canvas, w, hz, 33, h * 0.05, h * 0.2, const Color(0xFF0E0A26), tilt.dx * -12, false);
    _skyline(canvas, w, hz, 47, h * 0.04, h * 0.25, const Color(0xFF080A18), tilt.dx * -20, true);

    // floor
    final floor = Rect.fromLTWH(0, hz, w, h - hz);
    canvas.drawRect(
      floor,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF240F4D), Color(0xFF05060F)],
        ).createShader(floor),
    );
    final gridA = _seg(p, 0.0, 0.3);
    final lineP = Paint()
      ..strokeWidth = 1.2
      ..color = Neo.violet.withValues(alpha: 0.5 * gridA);
    const rows = 14;
    final s = (t * 0.5) % 1.0;
    for (int i = 0; i < rows; i++) {
      final f = (i + s) / rows;
      final y = hz + (h - hz) * math.pow(f, 2.4).toDouble();
      lineP.color = Neo.cyan.withValues(alpha: (0.15 + 0.6 * f) * gridA);
      canvas.drawLine(Offset(0, y), Offset(w, y), lineP);
    }
    lineP.color = Neo.violet.withValues(alpha: 0.45 * gridA);
    for (int j = -14; j <= 14; j++) {
      final top = Offset(w / 2 + j * w * 0.012 - tilt.dx * 6, hz);
      final bot = Offset(w / 2 + j * w * 0.24 - tilt.dx * 30, h);
      canvas.drawLine(top, bot, lineP);
    }

    // horizon glow
    final band = Rect.fromLTWH(0, hz - 16, w, 32);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Neo.pink.withValues(alpha: 0),
            Neo.pink.withValues(alpha: 0.45),
            Neo.pink.withValues(alpha: 0),
          ],
        ).createShader(band),
    );

    // anime speed-line burst
    if (p < 0.3) {
      final k = 1 - p / 0.3;
      final cx = w / 2;
      final cy = h * 0.29;
      final maxR = math.sqrt(w * w + h * h) / 2;
      final rnd = math.Random(11);
      final lp = Paint()
        ..color = Colors.white.withValues(alpha: 0.55 * k)
        ..strokeWidth = 1.4;
      for (int i = 0; i < 48; i++) {
        final ang = rnd.nextDouble() * twoPi;
        final inner = maxR * (0.12 + 0.6 * (1 - k));
        final outer = inner + maxR * (0.1 + 0.4 * k * rnd.nextDouble());
        canvas.drawLine(
          Offset(cx + math.cos(ang) * inner, cy + math.sin(ang) * inner),
          Offset(cx + math.cos(ang) * outer, cy + math.sin(ang) * outer),
          lp,
        );
      }
    }
  }

  void _skyline(Canvas canvas, double w, double hz, int seed, double minH,
      double maxH, Color col, double dx, bool windows) {
    final rnd = math.Random(seed);
    final fill = Paint()..color = col;
    double x = -30 + dx;
    while (x < w + 30) {
      final bw = w * (0.05 + rnd.nextDouble() * 0.07);
      final bh = minH + rnd.nextDouble() * (maxH - minH);
      canvas.drawRect(Rect.fromLTWH(x, hz - bh, bw, bh + 2), fill);
      if (windows) {
        canvas.drawLine(
          Offset(x, hz - bh),
          Offset(x + bw, hz - bh),
          Paint()
            ..color = Neo.cyan.withValues(alpha: 0.45)
            ..strokeWidth = 1,
        );
        final rows = (bh / 12).floor();
        for (int r = 0; r < rows; r++) {
          for (int c = 0; c < 2; c++) {
            final on = rnd.nextDouble();
            if (on > 0.62) {
              final flick = 0.55 + 0.45 * math.sin(t * 2.2 + r * 1.3 + c + x);
              canvas.drawRect(
                Rect.fromLTWH(x + bw * (0.25 + 0.35 * c), hz - bh + 6 + r * 12, 3, 4),
                Paint()
                  ..color = (on > 0.82 ? Neo.pink : Neo.cyan)
                      .withValues(alpha: 0.8 * flick.clamp(0.2, 1.0).toDouble()),
              );
            }
          }
        }
      }
      x += bw + rnd.nextDouble() * 4;
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) =>
      old.t != t || old.p != p || old.tilt != tilt;
}

// ===========================================================================
// SAKURA PETALS
// ===========================================================================

class _PetalPainter extends CustomPainter {
  final double t, p;
  _PetalPainter({required this.t, required this.p});

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(3);
    final fade = _seg(p, 0.15, 0.4);
    for (int i = 0; i < 26; i++) {
      final x0 = rnd.nextDouble();
      final k = 1 + rnd.nextInt(3); // integer speed => seamless loop
      final ph = rnd.nextDouble();
      final sz = 3.5 + rnd.nextDouble() * 4.5;
      final y = ((ph + t / 12 * k) % 1.0) * (size.height + 40) - 20;
      final x = x0 * size.width + math.sin(2 * math.pi * (t / 12 * k) + ph * 6) * 22;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(2 * math.pi * (t / 12 * k) + ph * 6);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: sz * 1.8, height: sz),
        Paint()..color = Neo.pink.withValues(alpha: 0.65 * fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _PetalPainter old) => old.t != t || old.p != p;
}
