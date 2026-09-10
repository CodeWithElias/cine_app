import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/auth_service.dart';
import '../services/voice_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/butacas_grid.dart';
import '../widgets/cartelera_carousel.dart';
import '../widgets/edge_rings_painter.dart';
import '../widgets/manipulable_canvas.dart';
import 'login_screen.dart';

const double _kButtonSize = 96;
const double _kButtonBottomMargin = 28;

enum OrbState { idle, listening, thinking, speaking }

/// Lo que el canvas generativo esta mostrando ahora mismo, segun lo ultimo
/// que el usuario pidio por voz. 'none' = todavia no pidio nada.
enum CanvasView { none, cartelera, butacas }

/// Pantalla de voz minimalista: solo el boton central y, detras, el canvas
/// generativo con lo que el usuario va pidiendo (cartelera, butacas, etc.).
/// Sin barras ni texto de estado permanente - el propio boton (icono, color,
/// anillos) comunica si esta escuchando, pensando o respondiendo.
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> with TickerProviderStateMixin {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final _voiceApi = VoiceApiService();

  late final AnimationController _ringController;
  late final AnimationController _pulseController;
  StreamSubscription<PlayerState>? _playerSub;

  OrbState _orbState = OrbState.idle;
  bool _isMuted = false;
  CanvasView _canvasView = CanvasView.none;

  bool get _isActive => _orbState == OrbState.listening || _orbState == OrbState.speaking;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _playerSub = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      if (state == PlayerState.playing) {
        setState(() => _orbState = OrbState.speaking);
      } else if (state == PlayerState.completed || state == PlayerState.stopped) {
        setState(() => _orbState = OrbState.idle);
      }
    });
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    _ringController.dispose();
    _pulseController.dispose();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        _showError('No se pudo acceder al micrófono. Revisa los permisos de la app.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/lumen_pregunta_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.wav), path: path);
      setState(() => _orbState = OrbState.listening);
    } catch (e) {
      _showError('No se pudo acceder al micrófono. Revisa los permisos de la app.');
    }
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    if (path != null) {
      await _sendToAgent(path);
    }
  }

  Future<void> _sendToAgent(String audioPath) async {
    setState(() => _orbState = OrbState.thinking);
    try {
      final dir = await getTemporaryDirectory();
      final outputPath = '${dir.path}/lumen_respuesta_${DateTime.now().millisecondsSinceEpoch}.wav';
      final result = await _voiceApi.sendVoiceMessage(
        audioPath: audioPath,
        outputPath: outputPath,
      );
      _updateCanvasFromTranscript(result.transcript);
      await _player.play(DeviceFileSource(result.audioPath));
    } catch (e) {
      setState(() => _orbState = OrbState.idle);
      _showError(e is VoiceApiException ? e.message : 'No se pudo hablar con el agente.');
    }
  }

  /// Deteccion de intencion por palabras clave sobre lo que dijo el usuario.
  /// Mock: no depende de un backend de catalogo todavia. Si no reconoce
  /// ningun pedido, deja el canvas como estaba (no interrumpe lo que ya se
  /// estaba mostrando).
  void _updateCanvasFromTranscript(String text) {
    final t = text.toLowerCase();
    final pideCartelera = t.contains('cartelera') || t.contains('película') || t.contains('peliculas') || t.contains('películas');
    final pideButacas = t.contains('butaca') || t.contains('asiento');

    if (pideCartelera) {
      setState(() => _canvasView = CanvasView.cartelera);
    } else if (pideButacas) {
      setState(() => _canvasView = CanvasView.butacas);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: LumenColors.errorContainer,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleOrbTap() {
    if (_isMuted) return;
    if (_orbState == OrbState.idle) {
      _startRecording();
    } else if (_orbState == OrbState.listening) {
      _stopRecording();
    }
  }

  void _toggleMute() {
    if (!_isMuted && _orbState == OrbState.listening) {
      _stopRecording();
    }
    setState(() => _isMuted = !_isMuted);
  }

  Future<void> _confirmLogout() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: LumenColors.surfaceContainer,
        title: const Text('Cerrar sesión', style: TextStyle(color: LumenColors.onSurface)),
        content: const Text(
          '¿Quieres cerrar sesión?',
          style: TextStyle(color: LumenColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cerrar sesión', style: TextStyle(color: LumenColors.error)),
          ),
        ],
      ),
    );
    if (confirmar == true) {
      await AuthService.instance.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  IconData get _orbIcon {
    if (_isMuted) return Icons.mic_off;
    switch (_orbState) {
      case OrbState.listening:
        return Icons.stop_circle;
      case OrbState.thinking:
        return Icons.more_horiz;
      case OrbState.speaking:
        return Icons.graphic_eq;
      case OrbState.idle:
        return Icons.mic;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final anchor = Offset(
      mq.size.width / 2,
      mq.size.height - mq.padding.bottom - _kButtonBottomMargin - _kButtonSize / 2,
    );

    return Scaffold(
      backgroundColor: LumenColors.surfaceContainerLowest,
      body: Stack(
        children: [
          Positioned.fill(child: SafeArea(child: _buildCanvas())),
          Positioned.fill(child: _buildEdgeRings(anchor)),
          Positioned(
            bottom: _kButtonBottomMargin + mq.padding.bottom,
            left: 0,
            right: 0,
            child: Center(child: _buildOrb()),
          ),
        ],
      ),
    );
  }

  Widget _buildEdgeRings(Offset anchor) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ringController,
        builder: (context, _) {
          final intensity = _isActive ? 1.0 : 0.25;
          return CustomPaint(
            painter: EdgeRingsPainter(
              anchor: anchor,
              shimmer: _ringController.value,
              intensity: intensity,
              colorA: LumenColors.primaryContainer,
              colorB: LumenColors.secondary,
            ),
          );
        },
      ),
    );
  }

  Widget _buildCanvas() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
      child: switch (_canvasView) {
        CanvasView.cartelera => SizedBox.expand(
            key: const ValueKey('cartelera'),
            child: ManipulableCanvas(child: const CarteleraCarousel()),
          ),
        CanvasView.butacas => SizedBox.expand(
            key: const ValueKey('butacas'),
            child: ManipulableCanvas(child: const Center(child: ButacasGrid())),
          ),
        CanvasView.none => const SizedBox.expand(key: ValueKey('idle')),
      },
    );
  }

  Widget _buildOrb() {
    final Gradient gradient = _isMuted
        ? const LinearGradient(colors: [LumenColors.surfaceContainer, LumenColors.surfaceContainerHigh])
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [LumenColors.surfaceContainer, LumenColors.primaryContainer, LumenColors.secondary],
          );

    return GestureDetector(
      onTap: _handleOrbTap,
      onLongPress: _confirmLogout,
      onDoubleTap: _toggleMute,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final scale = _isActive ? 1 + (_pulseController.value * 0.08) : 1.0;
          return Transform.scale(scale: scale, child: child);
        },
        child: Container(
          width: _kButtonSize,
          height: _kButtonSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: gradient,
            boxShadow: _isMuted
                ? []
                : [
                    BoxShadow(
                      color: LumenColors.primaryContainer.withValues(alpha: 0.5),
                      blurRadius: 50,
                      spreadRadius: 2,
                    ),
                  ],
          ),
          child: Icon(
            _orbIcon,
            size: 40,
            color: _isMuted ? LumenColors.onSurfaceVariant : LumenColors.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}
