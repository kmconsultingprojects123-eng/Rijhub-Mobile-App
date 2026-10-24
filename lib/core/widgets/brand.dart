import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum LogoVariant {
  /// The pin in crimson and black, "employi" in black. For light
  /// backgrounds.
  color,

  /// The pin in crimson and white, "employi" in white. For dark backgrounds
  /// and photos.
  onDark,

  /// All white. For crimson backgrounds.
  white,
}

/// The Employi logo: the pin beside "employi", with "powered by RijHub"
/// under it, drawn from the chosen artwork.
class RijHubLogo extends StatelessWidget {
  const RijHubLogo({
    super.key,
    this.height = 40,
    this.variant = LogoVariant.color,
  });

  final double height;
  final LogoVariant variant;

  /// Width / height of the artwork.
  static const aspectRatio = 1261 / 400;

  @override
  Widget build(BuildContext context) {
    final asset = switch (variant) {
      LogoVariant.color => 'assets/brand/rijhub_logo.png',
      LogoVariant.onDark => 'assets/brand/rijhub_logo_on_dark.png',
      LogoVariant.white => 'assets/brand/rijhub_logo_white.png',
    };
    return Image.asset(
      asset,
      height: height,
      width: height * aspectRatio,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'Employi',
    );
  }
}

/// The official Google "G", for "Continue with Google".
class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/icons/google_g.svg',
        width: size,
        height: size,
        excludeFromSemantics: true,
      );
}

/// The Employi mark (the pin with a handshake) on its own, for small spaces
/// such as Employi's avatar in a conversation.
class RijHubMark extends StatelessWidget {
  const RijHubMark({super.key, this.size = 24, this.white = false});

  final double size;

  /// White, for crimson and dark backgrounds.
  final bool white;

  @override
  Widget build(BuildContext context) => Image.asset(
        white
            ? 'assets/brand/rijhub_mark_white.png'
            : 'assets/brand/rijhub_mark.png',
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      );
}
