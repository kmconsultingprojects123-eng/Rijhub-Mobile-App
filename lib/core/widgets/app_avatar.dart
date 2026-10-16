import 'package:flutter/material.dart';

import '../theme/theme.dart';

enum AvatarShape { circle, rounded }

/// A person's photo, or their initials when there is no photo.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.image,
    this.size = 48,
    this.shape = AvatarShape.circle,
  });

  final String name;
  final ImageProvider? image;
  final double size;
  final AvatarShape shape;

  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = shape == AvatarShape.circle
        ? BorderRadius.circular(size / 2)
        : BorderRadius.circular(size * 0.28);
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return Semantics(
      label: name,
      image: true,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox.square(
          dimension: size,
          child: image != null
              ? Image(
                  image: ResizeImage.resizeIfNeeded(
                    (size * dpr).round(),
                    null,
                    image!,
                  ),
                  fit: BoxFit.cover,
                )
              : ColoredBox(
                  color: c.brandSubtle,
                  child: Center(
                    child: Text(
                      initialsOf(name),
                      style: AppText.labelSmall.copyWith(
                        fontSize: size * 0.36,
                        height: 1,
                        color: c.brandText,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
