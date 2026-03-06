import 'dart:math' show sin, pi;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class StaticSplashWidget extends StatefulWidget {
  const StaticSplashWidget({super.key});

  // Router identifiers
  static String routeName = 'StaticSplash';
  static String routePath = '/static_splash_page';

  @override
  State<StaticSplashWidget> createState() => _StaticSplashWidgetState();
}

class _StaticSplashWidgetState extends State<StaticSplashWidget> with TickerProviderStateMixin {
  late final AnimationController _logoCtrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  // subtle breathing animation that runs after the entrance so the logo stays visible
  late final AnimationController _logoBreathCtrl;
  late final Animation<double> _logoBreath;

  @override
  void initState() {
    super.initState();
    // longer entrance so users notice the logo while loading
    _logoCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _logoScale = Tween<double>(begin: 0.92, end: 1.0).animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack));
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.easeIn));

    // breathing animation (very subtle) that begins after entrance finishes
    _logoBreathCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
    _logoBreath = Tween<double>(begin: 1.0, end: 1.02).animate(CurvedAnimation(parent: _logoBreathCtrl, curve: Curves.easeInOut));

    // start entrance and then start breathing loop so the logo remains gently animated
    _logoCtrl.forward().then((_) {
      try {
        _logoBreathCtrl.repeat(reverse: true);
      } catch (_) {}
    });

    // After a short, visible delay, navigate to /splash2. Use GoRouter so the
    // router handles the navigation. This keeps startup sequence deterministic
    // and avoids automatic redirects to other areas of the app.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Wait briefly to allow the entrance animation to play and give users a
      // moment to see the logo.
      await Future.delayed(const Duration(milliseconds: 1400));
      if (!mounted) return;
      try {
        // Use GoRouter navigation to replace the current location.
        GoRouter.of(context).go('/splash2');
      } catch (_) {
        // If GoRouter is not available for some reason, do nothing — the
        // rest of the app can still proceed via manual taps on the splash.
      }
    });
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _logoBreathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Responsive logo sizing: use 35% of the smallest screen dimension, clamped
    final mq = MediaQuery.of(context);
    final screenWidth = mq.size.width;
    final screenHeight = mq.size.height;
    final base = screenWidth < screenHeight ? screenWidth : screenHeight;
    final computedSize = base * 0.35; // occupy up to 35% of the smaller dimension
    final logoSize = computedSize.clamp(80.0, 320.0);

    // Choose logo depending on current brightness (theme)
    final logoAsset = Theme.of(context).brightness == Brightness.dark
        ? 'assets/images/logo_white.png'
        : 'assets/images/logo_black.png';

    // Background should adapt to theme
    final backgroundColor = Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white;

    // Use a fixed brand red color for the loader on both light and dark themes
    final primaryColor = Theme.of(context).colorScheme.primary;
    final loaderColor = primaryColor == Colors.transparent ? const Color(0xFFA20025) : primaryColor;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        top: true,
        bottom: true,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Responsive, theme-aware logo with subtle entrance animation and a gentle breathing loop
              ScaleTransition(
                scale: _logoBreath,
                child: FadeTransition(
                  opacity: _logoOpacity,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: Image.asset(
                      logoAsset,
                      width: logoSize,
                      height: logoSize,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        // Fallback to an existing repo logo if the themed asset isn't available
                        return Image.asset(
                          'assets/images/app_logo_RH.jpg',
                          width: logoSize,
                          height: logoSize,
                          fit: BoxFit.contain,
                        );
                      },
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Modern themed loading indicator (breathing rings)
              _BreathingRingLoader(
                color: loaderColor,
                size: (logoSize * 0.28).clamp(40.0, 120.0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Simple breathing ring loader: two expanding/fading rings and a pulsing center dot.
class _BreathingRingLoader extends StatefulWidget {
  const _BreathingRingLoader({required this.color, this.size = 64.0});
  final Color color;
  final double size;

  @override
  State<_BreathingRingLoader> createState() => _BreathingRingLoaderState();
}

class _BreathingRingLoaderState extends State<_BreathingRingLoader> with TickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ring1Max = widget.size; // max diameter for ring1
    final ring2Max = widget.size * 1.4; // ring2 slightly larger
    final centerSize = widget.size * 0.18;

    return SizedBox(
      width: ring2Max,
      height: ring2Max,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          final t = _anim.value; // 0..1
          // ring progress stagger: ring2 is half-phase offset
          final r1Scale = 0.6 + 0.4 * (0.5 + 0.5 * sin(2 * pi * t));
          final r2Scale = 0.6 + 0.4 * (0.5 + 0.5 * sin(2 * pi * ((t + 0.5) % 1.0)));
          final r1Opacity = (0.35 + 0.65 * (0.5 + 0.5 * sin(2 * pi * t))).clamp(0.05, 1.0);
          final r2Opacity = (0.25 + 0.75 * (0.5 + 0.5 * sin(2 * pi * ((t + 0.5) % 1.0)))).clamp(0.03, 1.0);
          final centerScale = 0.92 + 0.12 * sin(2 * pi * t);

          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer subtle glow circle to give depth (soft radial)
              Container(
                width: ring2Max,
                height: ring2Max,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      widget.color.withAlpha((0.06 * 255).round()),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 1.0],
                    radius: 0.6,
                  ),
                ),
              ),

              // Ring 2 (larger, more subtle)
              Opacity(
                opacity: r2Opacity,
                child: Container(
                  width: ring2Max * r2Scale,
                  height: ring2Max * r2Scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.color.withAlpha((0.22 * 255).round()),
                      width: 3.0,
                    ),
                  ),
                ),
              ),

              // Ring 1 (smaller, brighter)
              Opacity(
                opacity: r1Opacity,
                child: Container(
                  width: ring1Max * r1Scale,
                  height: ring1Max * r1Scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.color.withAlpha((0.95 * 255).round()),
                      width: 3.5,
                    ),
                  ),
                ),
              ),

              // Center pulsing dot with soft radial glow (no drop shadow)
              Transform.scale(
                scale: centerScale,
                child: Container(
                  width: centerSize,
                  height: centerSize,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        widget.color.withAlpha((0.95 * 255).round()),
                        widget.color.withAlpha((0.5 * 255).round()),
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
