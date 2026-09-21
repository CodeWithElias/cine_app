import 'package:flutter/material.dart';

import '../services/cine_api.dart';
import '../theme/app_theme.dart';

/// Franja que avisa que lo que se ve viene de la copia guardada porque no hay internet. No ocupa lugar si los datos son en vivo.
class AvisoDatosGuardados extends StatelessWidget {
  const AvisoDatosGuardados({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: CineApi.datosGuardadosDesde,
      builder: (context, desde, _) {
        if (desde == null) return const SizedBox.shrink();
        final hora = '${desde.hour.toString().padLeft(2, '0')}:${desde.minute.toString().padLeft(2, '0')}';
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: LumenColors.secondaryContainer.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.cloud_off_outlined, size: 17, color: LumenColors.secondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Sin conexión: mostrando datos guardados el ${desde.day}/${desde.month} a las $hora.',
                  style: const TextStyle(color: LumenColors.secondary, fontSize: 12.5)),
            ),
          ]),
        );
      },
    );
  }
}
