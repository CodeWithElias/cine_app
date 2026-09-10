import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class VoiceChatResult {
  final String transcript;
  final String replyText;

  /// Ruta local (archivo temporal) del audio .wav de respuesta, listo para
  /// reproducir.
  final String audioPath;

  VoiceChatResult({
    required this.transcript,
    required this.replyText,
    required this.audioPath,
  });
}

class VoiceApiException implements Exception {
  final String message;
  VoiceApiException(this.message);

  @override
  String toString() => message;
}

/// Cliente del agente de voz (back_agent, FastAPI) - mismo endpoint
/// POST /voice-chat que usa el frontend web (src/api/voice.api.ts).
class VoiceApiService {
  /// Envia el audio grabado (archivo en [audioPath]) al agente y guarda la
  /// respuesta en un archivo temporal (.wav) en [outputPath].
  Future<VoiceChatResult> sendVoiceMessage({
    required String audioPath,
    required String outputPath,
  }) async {
    final uri = Uri.parse('$kVoiceAgentUrl/voice-chat');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('audio', audioPath));

    final http.StreamedResponse streamed;
    try {
      streamed = await request.send();
    } catch (e) {
      throw VoiceApiException('No se pudo conectar con el agente de voz: $e');
    }

    if (streamed.statusCode != 200) {
      final body = await streamed.stream.bytesToString();
      throw VoiceApiException('Error ${streamed.statusCode} del agente: $body');
    }

    final transcript = Uri.decodeComponent(
      streamed.headers['x-transcript'] ?? '',
    );
    final replyText = Uri.decodeComponent(
      streamed.headers['x-reply-text'] ?? '',
    );

    final bytes = await streamed.stream.toBytes();
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(bytes);

    return VoiceChatResult(
      transcript: transcript,
      replyText: replyText,
      audioPath: outputPath,
    );
  }
}
