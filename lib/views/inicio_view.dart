import 'package:flutter/material.dart';

import '../offline/gestor_modelos.dart';
import '../state/cine_state.dart';
import '../theme/app_theme.dart';

/// Pantalla de inicio: invita a hablar con el asistente y ofrece los atajos tactiles.
class InicioView extends StatelessWidget {
  final CineState cine;
  final String nombre;
  final bool conversando;
  final GestorModelos gestor;
  final VoidCallback onSinConexion;

  const InicioView({
    super.key,
    required this.cine,
    required this.nombre,
    required this.conversando,
    required this.gestor,
    required this.onSinConexion,
  });

  static const _ejemplos = [
    '«¿Qué hay en cartelera?»',
    '«Quiero dos entradas para Oppenheimer a las ocho»',
    '«Agrégame unos pochoclos»',
    '«¿Qué compras hice?»',
  ];

  @override
  Widget build(BuildContext context) {
    final primerNombre = nombre.split(' ').first;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const Text(
          'LUMEN CINEMA',
          style: TextStyle(
            color: LumenColors.secondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Hola, $primerNombre',
          style: const TextStyle(
            color: LumenColors.onSurface,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          conversando
              ? 'Te estoy escuchando. Pídeme lo que quieras: la pantalla se mueve mientras hablamos.'
              : 'Toca el botón de abajo para hablar con el asistente. Compra entradas y dulcería sin tocar la pantalla.',
          style: const TextStyle(
            color: LumenColors.onSurfaceVariant,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: _Atajo(
                icono: Icons.local_movies_outlined,
                texto: 'Cartelera',
                onTap: () => cine.irA(Pantalla.cartelera),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Atajo(
                icono: Icons.confirmation_number_outlined,
                texto: 'Mis compras',
                onTap: () => cine.irA(Pantalla.misCompras),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _TarjetaSinConexion(gestor: gestor, onTap: onSinConexion),
        const SizedBox(height: 26),
        const Text(
          'PRUEBA DICIENDO',
          style: TextStyle(
            color: LumenColors.primary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        for (final e in _ejemplos)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: LumenColors.surfaceContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.graphic_eq,
                  size: 18,
                  color: LumenColors.secondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    e,
                    style: const TextStyle(
                      color: LumenColors.onSurface,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Entrada al modo sin conexion: dice en que estado esta (sin descargar, descargando o listo).
class _TarjetaSinConexion extends StatelessWidget {
  final GestorModelos gestor;
  final VoidCallback onTap;
  const _TarjetaSinConexion({required this.gestor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: gestor,
      builder: (context, _) {
        final listo = gestor.listoParaVoz;
        final bajando = gestor.descargando;
        final texto = listo
            ? 'Activado: Lumen funciona aunque no tengas internet.'
            : bajando
            ? 'Descargando…'
            : 'Descarga los modelos de voz para usar Lumen sin internet (opcional).';
        return Material(
          color: LumenColors.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    listo
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    color: listo ? LumenColors.tertiary : LumenColors.secondary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Modo sin conexión',
                          style: TextStyle(
                            color: LumenColors.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          texto,
                          style: const TextStyle(
                            color: LumenColors.onSurfaceVariant,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: LumenColors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Atajo extends StatelessWidget {
  final IconData icono;
  final String texto;
  final VoidCallback onTap;
  const _Atajo({required this.icono, required this.texto, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: LumenColors.surfaceContainer,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            Icon(icono, color: LumenColors.primary, size: 30),
            const SizedBox(height: 8),
            Text(
              texto,
              style: const TextStyle(
                color: LumenColors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
