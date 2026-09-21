import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models/estrenos.dart';
import '../theme/app_theme.dart';

/// Reproduce el trailer de un estreno DENTRO de la app (reproductor de YouTube incrustado), igual que el modal de
/// trailers de la web. Se cierra con la X, tocando fuera o con el boton atras.
Future<void> mostrarTrailer(BuildContext context, Estreno estreno) => showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _TrailerDialog(estreno: estreno),
    );

class _TrailerDialog extends StatefulWidget {
  final Estreno estreno;
  const _TrailerDialog({required this.estreno});

  @override
  State<_TrailerDialog> createState() => _TrailerDialogState();
}

class _TrailerDialogState extends State<_TrailerDialog> {
  late final YoutubePlayerController _controller = YoutubePlayerController.fromVideoId(
    videoId: widget.estreno.youtubeId,
    autoPlay: true,
    params: const YoutubePlayerParams(showControls: true, showFullscreenButton: true, strictRelatedVideos: true),
  );

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.estreno;
    return Dialog(
      backgroundColor: LumenColors.surfaceContainer,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(children: [
            const Icon(Icons.play_circle_outline, size: 20, color: LumenColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Tráiler · ${e.titulo}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: LumenColors.onSurface, fontWeight: FontWeight.w800)),
            ),
            IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close), color: LumenColors.onSurfaceVariant),
          ]),
        ),
        YoutubePlayer(controller: _controller, aspectRatio: 16 / 9),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Text('${e.director} · ${e.anio} · ${e.genero}', style: const TextStyle(color: LumenColors.secondary, fontSize: 12)),
        ),
      ]),
    );
  }
}
