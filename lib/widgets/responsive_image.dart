import 'package:flutter/material.dart';

class ResponsiveImage extends StatelessWidget {
  final ImageProvider? image;
  final String? asset;
  final double? maxWidth;
  final BoxFit fit;
  final double? aspectRatio;

  const ResponsiveImage({
    super.key,
    this.image,
    this.asset,
    this.maxWidth,
    this.fit = BoxFit.cover,
    this.aspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final double constrained = maxWidth ?? (w > 800 ? 600 : w);

    Widget img;
    if (image != null) {
      img = Image(image: image!, fit: fit);
    } else if (asset != null) {
      img = Image.asset(asset!, fit: fit);
    } else {
      img = SizedBox.shrink();
    }

    if (aspectRatio != null) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constrained),
          child: AspectRatio(aspectRatio: aspectRatio!, child: img),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: constrained), child: img),
    );
  }
}

