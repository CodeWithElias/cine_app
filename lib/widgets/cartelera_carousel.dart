import 'package:flutter/material.dart';

import '../models/pelicula.dart';
import '../theme/app_theme.dart';
import 'staggered_entrance.dart';

/// Vista generativa disparada por voz ("muéstrame la cartelera"). Ocupa
/// toda la pantalla disponible: una pelicula grande por pagina, deslizable.
/// Datos de prueba por ahora - se conecta a un catalogo real mas adelante.
class CarteleraCarousel extends StatelessWidget {
  const CarteleraCarousel({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text(
              'CARTELERA HOY • DESLIZA PARA VER MÁS',
              style: TextStyle(
                color: LumenColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: constraints.maxHeight - 40,
              child: PageView.builder(
                controller: PageController(viewportFraction: 0.86),
                itemCount: mockPeliculas.length,
                itemBuilder: (context, index) => StaggeredEntrance(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: _PeliculaCard(pelicula: mockPeliculas[index]),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PeliculaCard extends StatelessWidget {
  final Pelicula pelicula;
  const _PeliculaCard({required this.pelicula});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: LumenColors.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  pelicula.posterUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: LumenColors.surfaceContainerHigh,
                    child: const Icon(Icons.movie, color: LumenColors.outline, size: 64),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: LumenColors.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          pelicula.clasificacion,
                          style: const TextStyle(color: LumenColors.onPrimary, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        pelicula.titulo,
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pelicula.genero,
                        style: const TextStyle(color: LumenColors.secondary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      pelicula.sinopsis,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: LumenColors.onSurfaceVariant, fontSize: 13, height: 1.4),
                    ),
                  ),
                  Text(
                    'HORARIOS',
                    style: TextStyle(color: LumenColors.outline.withValues(alpha: 0.9), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: pelicula.horarios
                        .map((h) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: LumenColors.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  h,
                                  style: const TextStyle(color: LumenColors.onSurface, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${pelicula.duracionMinutos} min',
                    style: const TextStyle(color: LumenColors.outline, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
