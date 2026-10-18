import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum LogoVariant {
  /// "Rij" in crimson, "HUB" in black. For light backgrounds.
  color,

  /// "Rij" in crimson, "HUB" in white. For dark backgrounds and photos.
  onDark,

  /// All white. For crimson backgrounds.
  white,
}

/// The RijHub wordmark with its tagline, cropped from the original artwork.
class RijHubLogo extends StatelessWidget {
  const RijHubLogo({
    super.key,
    this.height = 40,
    this.variant = LogoVariant.color,
  });

  final double height;
  final LogoVariant variant;

  /// Width / height of the cropped artwork.
  static const aspectRatio = 975 / 318;

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
      semanticLabel: 'RijHub',
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

/// The RijHub mark (the "R" monogram) on its own, for small spaces such as
/// RijHub's avatar in a conversation.
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
