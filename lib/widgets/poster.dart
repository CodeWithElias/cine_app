import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Portada de una pelicula con un marcador si no hay imagen o no carga.
class Poster extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final double radius;

  const Poster({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final vacio = Container(
      width: width,
      height: height,
      color: LumenColors.surfaceContainerHigh,
      alignment: Alignment.center,
      child: const Icon(
        Icons.movie_outlined,
        color: LumenColors.outline,
        size: 28,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: (url == null || url!.isEmpty)
          ? vacio
          : Image.network(
              url!,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => vacio,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : vacio,
            ),
    );
  }
}
