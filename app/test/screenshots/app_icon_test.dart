// Renders the Wyrd app icon masters with the app's own fonts and colours:
// an ember ring around a Cinzel "W" over the dark backdrop.
//
//   flutter test --dart-define=SCREENSHOTS=true --update-goldens test/screenshots/app_icon_test.dart
//   python3 ../tool/app_icons.py
//
// Skipped in normal test runs. Output: 1024 px masters in app/build/icons/,
// which tool/app_icons.py cuts into every size Android, iOS and the web need.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrd/design/tokens.dart';

import 'support.dart';

const _out = '../../build/icons';

enum _Kind {
  /// Full-bleed square for iOS and as the base of every other variant.
  square,

  /// Rounded square on transparency, for Android's legacy launcher icon,
  /// web icons and the favicon.
  rounded,

  /// Full-bleed with the mark inside the central 80 %, for web "maskable".
  maskable,

  /// Mark only on transparency, inside the central 66 %, for Android's
  /// adaptive-icon foreground layer (and, as a silhouette, its themed icon).
  foreground,

  /// Backdrop only, for Android's adaptive-icon background layer.
  background,
}

Future<void> _render(WidgetTester tester, _Kind kind) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size.square(1024);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      home: Material(type: MaterialType.transparency, child: _Icon(kind)),
    ),
  );
  await tester.pump();
  await expectLater(find.byType(_Icon), matchesGoldenFile('$_out/icon-${kind.name}.png'));
}

void main() {
  setUpAll(() async {
    if (screenshotsEnabled) await loadAppFonts();
  });

  for (final kind in _Kind.values) {
    testWidgets('app icon (${kind.name})', skip: !screenshotsEnabled, (tester) => _render(tester, kind));
  }
}

class _Icon extends StatelessWidget {
  const _Icon(this.kind);

  final _Kind kind;

  @override
  Widget build(BuildContext context) {
    const size = 1024.0;
    final background = kind != _Kind.foreground;
    final mark = kind != _Kind.background;
    // How much of the canvas the mark may use for each target's safe zone.
    final markScale = switch (kind) {
      _Kind.square || _Kind.rounded || _Kind.background => 1.0,
      _Kind.maskable => 0.8,
      _Kind.foreground => 0.66,
    };
    Widget icon = SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (background)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-0.35, -0.45),
                    radius: 1.05,
                    colors: [Color(0xFF2B1B3E), Color(0xFF120E1C), Color(0xFF09090E)],
                    stops: [0, 0.55, 1],
                  ),
                ),
              ),
            ),
          if (background)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.7, 0.85),
                    radius: 0.9,
                    colors: [Color(0x553A1018), Color(0x0009090E)],
                  ),
                ),
              ),
            ),
          if (mark) Transform.scale(scale: markScale, child: const _Mark()),
        ],
      ),
    );
    if (kind == _Kind.rounded) {
      // Rounded square with a hairline rim, like a carved seal.
      icon = ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.225),
        child: Stack(
          children: [
            icon,
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size * 0.225),
                  border: Border.all(color: const Color(0x33FF8A4C), width: size * 0.008),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return icon;
  }
}

/// The ember ring and the Cinzel "W", centred on a 1024 canvas.
class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 1024,
    child: CustomPaint(
      painter: _RingPainter(),
      child: Center(
        child: Padding(
          // Cinzel's W sits a touch high; nudge it to the optical centre.
          padding: const EdgeInsets.only(top: 34),
          child: ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFC3A0), AppColors.ember, AppColors.crimson],
              stops: [0, 0.45, 1],
            ).createShader(r),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 48, vertical: 24),
              child: Text(
                'W',
                style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 470,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  fontVariations: [FontVariation.weight(700)],
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.385;
    final stroke = size.width * 0.052;
    // A soft halo: wide translucent passes instead of a blur.
    for (final (w, a) in [(4.2, 0.025), (3.6, 0.03), (3.0, 0.04), (2.5, 0.05), (2.0, 0.06), (1.6, 0.08)]) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * w
          ..color = AppColors.ember.withValues(alpha: a),
      );
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..shader = const SweepGradient(
          colors: [AppColors.crimson, AppColors.ember, AppColors.emberGlow, AppColors.ember, AppColors.crimson],
          stops: [0, 0.3, 0.5, 0.75, 1],
          transform: GradientRotation(-math.pi / 2),
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // A thin inner rim for depth.
    canvas.drawCircle(
      c,
      r - stroke * 0.95,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.006
        ..color = AppColors.emberGlow.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => false;
}
