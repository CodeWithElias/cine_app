import 'dart:async';

import 'package:flutter/material.dart';

import '../models/cine_models.dart';
import '../models/estrenos.dart';
import '../theme/app_theme.dart';
import 'poster.dart';
import 'trailer_dialog.dart';

/// "Estrenos y adelantos": carrusel de portadas (la del centro grande, las de los lados
/// mas chicas) que rota solo, con la ficha de la pelicula y su trailer. Equivalente movil
/// de `GlassyCarousel.tsx`. El trailer se reproduce dentro de la app; "Comprar" lleva a la pelicula en
/// la cartelera cuando esta en exhibicion.
class EstrenosCarousel extends StatefulWidget {
  final List<Pelicula> cartelera;

  /// El cliente quiere comprar una pelicula que esta en cartelera.
  final void Function(Pelicula pelicula) onComprar;

  /// Avisa cuando se abre (true) y se cierra (false) el trailer: el sonido del video no debe entrar al microfono del asistente.
  final void Function(bool abierto)? alTrailer;

  const EstrenosCarousel({super.key, required this.cartelera, required this.onComprar, this.alTrailer});

  @override
  State<EstrenosCarousel> createState() => _EstrenosCarouselState();
}

class _EstrenosCarouselState extends State<EstrenosCarousel> {
  static const _rotacion = Duration(milliseconds: 4500);

  late final PageController _pagina = PageController(viewportFraction: 0.52);
  Timer? _timer;
  int _actual = 0;
  bool _tocando = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_rotacion, (_) => _siguiente());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pagina.dispose();
    super.dispose();
  }

  void _siguiente() {
    if (_tocando || !_pagina.hasClients) return;
    final total = estrenosConCartelera(widget.cartelera).length;
    _pagina.animateToPage((_actual + 1) % total, duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic);
  }

  Future<void> _verTrailer(Estreno e) async {
    _tocando = true; // la rotacion automatica espera mientras se ve el trailer
    widget.alTrailer?.call(true);
    try {
      await mostrarTrailer(context, e);
    } finally {
      _tocando = false;
      widget.alTrailer?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estrenos = estrenosConCartelera(widget.cartelera);
    final actual = estrenos[_actual.clamp(0, estrenos.length - 1)];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: LumenColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 7, color: LumenColors.primary),
          SizedBox(width: 6),
          Text('ESTRENOS Y TRÁILERS', style: TextStyle(color: LumenColors.primary, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
        ]),
      ),
      const SizedBox(height: 8),
      const Text('Adelantos antes de comprar',
          style: TextStyle(color: LumenColors.onSurface, fontSize: 22, fontWeight: FontWeight.w800, height: 1.1)),
      const SizedBox(height: 12),
      SizedBox(
        height: 250,
        child: Listener(
          onPointerDown: (_) => _tocando = true,
          onPointerUp: (_) => _tocando = false,
          onPointerCancel: (_) => _tocando = false,
          child: PageView.builder(
            controller: _pagina,
            itemCount: estrenos.length,
            onPageChanged: (i) => setState(() => _actual = i),
            itemBuilder: (context, i) => AnimatedBuilder(
              animation: _pagina,
              builder: (context, child) {
                final pagina = _pagina.hasClients && _pagina.position.haveDimensions ? (_pagina.page ?? _actual.toDouble()) : _actual.toDouble();
                final distancia = (pagina - i).abs().clamp(0.0, 1.0);
                return Center(
                  child: Transform.scale(
                    scale: 1 - distancia * 0.2,
                    child: Opacity(opacity: 1 - distancia * 0.45, child: child),
                  ),
                );
              },
              child: GestureDetector(
                onTap: () => _pagina.animateToPage(i, duration: const Duration(milliseconds: 350), curve: Curves.easeOut),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: (i == _actual ? LumenColors.primaryContainer : Colors.black).withValues(alpha: 0.35), blurRadius: 22)],
                  ),
                  child: Stack(fit: StackFit.expand, children: [
                    Poster(url: estrenos[i].posterUrl, radius: 16),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(10)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.star_rounded, size: 13, color: LumenColors.primary),
                          const SizedBox(width: 2),
                          Text(estrenos[i].rating, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                    if (estrenos[i].peliculaReal != null)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: LumenColors.tertiary, borderRadius: BorderRadius.circular(8)),
                          child: const Text('EN CARTELERA', style: TextStyle(color: LumenColors.onTertiary, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < estrenos.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == _actual ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(color: i == _actual ? LumenColors.primary : LumenColors.surfaceContainerHighest, borderRadius: BorderRadius.circular(3)),
          ),
      ]),
      const SizedBox(height: 12),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Column(
          key: ValueKey(actual.titulo),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(actual.titulo, style: const TextStyle(color: LumenColors.onSurface, fontSize: 18, fontWeight: FontWeight.w800)),
            if (actual.subtitulo != null && actual.subtitulo != actual.titulo)
              Text(actual.subtitulo!, style: const TextStyle(color: LumenColors.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 4),
            Text('${actual.director} · ${actual.anio} · ${actual.genero}', style: const TextStyle(color: LumenColors.secondary, fontSize: 12)),
            const SizedBox(height: 6),
            Text(actual.sinopsis, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: LumenColors.onSurfaceVariant, fontSize: 13, height: 1.35)),
            const SizedBox(height: 10),
            Row(children: [
              FilledButton.icon(
                onPressed: () => _verTrailer(actual),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Ver tráiler'),
              ),
              const SizedBox(width: 10),
              if (actual.peliculaReal != null)
                OutlinedButton.icon(
                  onPressed: () => widget.onComprar(actual.peliculaReal!),
                  icon: const Icon(Icons.confirmation_number_outlined, size: 18),
                  label: const Text('Comprar'),
                ),
            ]),
          ],
        ),
      ),
    ]);
  }
}
