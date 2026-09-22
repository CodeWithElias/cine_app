import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../offline/gestor_modelos.dart';
import '../offline/sin_conexion.dart';
import '../services/auth_service.dart';
import '../services/cine_api.dart';
import '../services/pagos_stripe.dart';
import '../services/voice_session.dart';
import '../state/cine_state.dart';
import '../state/ui_action_handler.dart';
import '../state/ui_control.dart';
import '../theme/app_theme.dart';
import '../utils/responsivo.dart';
import '../views/cartelera_view.dart';
import '../views/compra_view.dart';
import '../views/inicio_view.dart';
import '../views/mis_compras_view.dart';
import '../widgets/edge_rings_painter.dart';
import '../widgets/ventanas_layer.dart';
import 'login_screen.dart';
import 'modo_sin_conexion_screen.dart';

const double _kButtonBottomMargin = 20;

/// Modo "Voz + UI dinamica" del cliente: una conversacion continua con el agente
/// (WebSocket) mientras la pantalla se mueve sola con lo que va pidiendo
/// (cartelera, asientos, dulceria, compra) y sigue siendo tactil. El boton de
/// abajo abre y cierra la conversacion.
///
/// Es el equivalente movil de `VoiceAgent.tsx` + `VoiceSessionProvider.tsx` +
/// `useUiActionHandler.ts` del frontend web.
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen>
    with TickerProviderStateMixin {
  late final CineState _cine;
  late final UiControl _ui;
  late final UiActionHandler _handler;
  late final VoiceSession _voz;
  final PagosStripe _pagos = PagosStripe();
  final GestorModelos _gestor = GestorModelos.instance;
  late final SinConexion _sinConexion = SinConexion(_gestor);

  late final AnimationController _ringController;
  late final AnimationController _pulseController;

  // Un solo id para toda esta pantalla (agrupa los turnos de la conversacion para el FSM de confirmacion del agente, RF19).
  final String _sesionId = DateTime.now().microsecondsSinceEpoch.toString();

  /// Version de la ultima tanda de acciones del servidor que la pantalla ya aplico (ver `contexto`).
  int _versionUi = 0;
  Timer? _pausaContexto;
  String? _ultimoContexto;

  @override
  void initState() {
    super.initState();
    _cine = CineState(CineApi());
    _ui = UiControl();
    _handler = UiActionHandler(
      cine: _cine,
      ui: _ui,
      alAplicar: (v) {
        _versionUi = v;
        _programarContexto(inmediato: true);
      },
    );
    _voz = VoiceSession(
      sesionId: _sesionId,
      onUiAction: _handler.aplicar,
      sinConexion: _sinConexion,
    )..addListener(_alCambiarVoz);
    _cine.addListener(_programarContexto);
    CineApi.onSesionVencida = _sesionVencida;
    // Stripe: la clave publicable la sirve el backend. Si hay tarjeta, el agente puede ofrecerla (`pantalla`).
    _pagos
        .iniciar(_cine.api)
        .then((_) => _voz.setTarjetaDisponible(_pagos.habilitado));
    _gestor.iniciar().then((_) => _ofrecerModoSinConexion());

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    if (CineApi.onSesionVencida == _sesionVencida) {
      CineApi.onSesionVencida = null;
    }
    _pausaContexto?.cancel();
    _cine.removeListener(_programarContexto);
    _voz.removeListener(_alCambiarVoz);
    _ringController.dispose();
    _pulseController.dispose();
    _voz.dispose();
    _pagos.dispose();
    _ui.dispose();
    _cine.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ contexto de la compra

  /// El agente no ve lo que el cliente marca TOCANDO la pantalla: se le cuenta (solo ids) cada vez que cambia,
  /// y al abrirse la conversacion. Va con la version de lo ultimo que el servidor mando y la pantalla ya aplico:
  /// asi el servidor descarta una foto de ANTES de un cambio suyo.
  void _programarContexto({bool inmediato = false}) {
    _pausaContexto?.cancel();
    if (!_voz.conversando) return;
    if (inmediato) {
      _enviarContexto();
    } else {
      _pausaContexto = Timer(
        const Duration(milliseconds: 350),
        _enviarContexto,
      );
    }
  }

  void _enviarContexto() {
    if (!_voz.conversando) return;
    final compra = _cine.contexto();
    final clave = '$_versionUi|${jsonEncode(compra)}';
    if (clave == _ultimoContexto) return;
    _ultimoContexto = clave;
    _voz.enviarContexto(_versionUi, compra);
  }

  EstadoConversacion? _estadoVisto;

  void _alCambiarVoz() {
    final estado = _voz.estado;
    if (estado != _estadoVisto) {
      final abrio = !_voz.conversando
          ? false
          : (_estadoVisto == null ||
                _estadoVisto == EstadoConversacion.conectando ||
                _estadoVisto == EstadoConversacion.apagada);
      _estadoVisto = estado;
      if (abrio) {
        _ultimoContexto =
            null; // conversacion nueva (o reconectada): se vuelve a contar lo marcado
        _programarContexto(inmediato: true);
      }
      if (estado == EstadoConversacion.error && mounted && _voz.error != null) {
        _mostrarError(_voz.error!);
      }
    }
  }

  // ------------------------------------------------------------------ acciones

  void _mostrarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: LumenColors.errorContainer,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _tocarBoton() {
    switch (_voz.estado) {
      case EstadoConversacion.apagada:
      case EstadoConversacion.error:
        _voz.iniciar();
      case EstadoConversacion.hablando:
        _voz.interrumpir(); // corta al asistente y sigue escuchando
      case EstadoConversacion.conectando:
      case EstadoConversacion.escuchando:
      case EstadoConversacion.pensando:
        _voz.terminar();
    }
  }

  void _alternarSilencio() => _voz.silenciar(!_voz.silenciado);

  void _abrirModoSinConexion() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ModoSinConexionScreen(gestor: _gestor, api: _cine.api),
      ),
    );
  }

  /// La primera vez se le ofrece al cliente llevar los modelos al telefono (es opcional); si dice que no, no se vuelve a preguntar.
  Future<void> _ofrecerModoSinConexion() async {
    if (!mounted || _gestor.listoParaVoz || _gestor.descargando) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('sinconexion_ofrecido') ?? false) return;
    await prefs.setBool('sinconexion_ofrecido', true);
    if (!mounted) return;
    final elegir = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: LumenColors.surfaceContainer,
        icon: const Icon(
          Icons.cloud_off_outlined,
          color: LumenColors.secondary,
        ),
        title: const Text(
          '¿Usar Lumen sin internet?',
          style: TextStyle(color: LumenColors.onSurface),
        ),
        content: const Text(
          'Puedes descargar los modelos de voz al teléfono (unos 190 MB) para hablar con Lumen y consultar la cartelera aunque no tengas internet. Es opcional y lo puedes hacer más tarde desde el inicio.',
          style: TextStyle(color: LumenColors.onSurfaceVariant, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Elegir'),
          ),
        ],
      ),
    );
    if (elegir == true && mounted) _abrirModoSinConexion();
  }

  bool _silenciadoAntesDelTrailer = false;

  /// Mientras suena un trailer el microfono se silencia (el video se oiria como si fuera el cliente hablando) y al
  /// cerrarlo vuelve a como estaba.
  void _alTrailer(bool abierto) {
    if (abierto) {
      _silenciadoAntesDelTrailer = _voz.silenciado;
      _voz.silenciar(true);
    } else {
      _voz.silenciar(_silenciadoAntesDelTrailer);
    }
  }

  bool _cerrandoPorVencimiento = false;

  /// El backend rechazo el token: la sesion vencio. Se vuelve al login (como hace la web con `auth:unauthorized`).
  Future<void> _sesionVencida() async {
    if (_cerrandoPorVencimiento || !mounted) return;
    _cerrandoPorVencimiento = true;
    await _voz.terminar();
    await AuthService.instance.logout();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tu sesión venció. Inicia sesión de nuevo.'),
      ),
    );
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _confirmarCerrarSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: LumenColors.surfaceContainer,
        title: const Text(
          'Cerrar sesión',
          style: TextStyle(color: LumenColors.onSurface),
        ),
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
            child: const Text(
              'Cerrar sesión',
              style: TextStyle(color: LumenColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmar == true) {
      await _voz.terminar();
      await AuthService.instance.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _abrirConfiguracionIp() async {
    final controller = TextEditingController(text: AppConfig.hostIp);
    final nueva = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: LumenColors.surfaceContainer,
        title: const Row(
          children: [
            Icon(Icons.dns_outlined, color: LumenColors.primary, size: 22),
            SizedBox(width: 10),
            Text(
              'IP del Servidor',
              style: TextStyle(color: LumenColors.onSurface, fontSize: 18),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Por defecto la app se conecta al servidor en la nube (AWS). Si trabajas en una red local, indica la IP de tu PC o la URL del backend:',
                style: TextStyle(
                  color: LumenColors.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: LumenColors.onSurface),
                decoration: const InputDecoration(
                  labelText: 'IP o Host',
                  hintText: 'Ej: 192.168.1.6 o ${AppConfig.hostNube}',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.wifi, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Atajos rápidos:',
                style: TextStyle(
                  color: LumenColors.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  ActionChip(
                    label: const Text(
                      'Nube (AWS)',
                      style: TextStyle(fontSize: 11),
                    ),
                    onPressed: () => controller.text = AppConfig.hostNube,
                  ),
                  ActionChip(
                    label: const Text(
                      '192.168.1.6 (Casa)',
                      style: TextStyle(fontSize: 11),
                    ),
                    onPressed: () => controller.text = '192.168.1.6',
                  ),
                  ActionChip(
                    label: const Text(
                      '10.0.2.2 (Emulador)',
                      style: TextStyle(fontSize: 11),
                    ),
                    onPressed: () => controller.text = '10.0.2.2',
                  ),
                  ActionChip(
                    label: const Text(
                      '100.114.60.117 (Tailscale)',
                      style: TextStyle(fontSize: 11),
                    ),
                    onPressed: () => controller.text = '100.114.60.117',
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (nueva != null && nueva.isNotEmpty) {
      await AppConfig.setHostIp(nueva);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Servidor actualizado a: ${AppConfig.hostIp}')),
      );
      if (_voz.activa) {
        await _voz.terminar();
        await _voz.iniciar();
      }
    }
  }

  // ------------------------------------------------------------------ interfaz

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final r = Responsivo.de(context);
    final tamBoton = r.tamanoBoton;
    final altoSub = r.altoSubtitulos;
    final reserva = tamBoton + _kButtonBottomMargin + mq.padding.bottom + 16;
    final anchor = Offset(
      mq.size.width / 2,
      mq.size.height - mq.padding.bottom - _kButtonBottomMargin - tamBoton / 2,
    );
    // En una tablet el contenido queda en una columna centrada; en un telefono ocupa todo el ancho.
    final margenLado = math.max(
      r.margenLateral,
      (r.ancho - r.anchoContenido) / 2 + r.margenLateral,
    );

    return ListenableBuilder(
      listenable: _cine,
      builder: (context, _) => PopScope(
        // Atras vuelve al inicio de la app antes de salir de ella.
        canPop: _cine.pantalla == Pantalla.inicio,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _cine.irA(Pantalla.inicio);
        },
        child: Scaffold(
          backgroundColor: LumenColors.surfaceContainerLowest,
          body: Stack(
            children: [
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    ListenableBuilder(
                      listenable: _voz,
                      builder: (_, _) => _Cabecera(
                        cine: _cine,
                        onCerrarSesion: _confirmarCerrarSesion,
                        onConfigurarIp: _abrirConfiguracionIp,
                        sinConexion: _voz.modoLocal,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: _cine.pantalla == Pantalla.compra
                              ? 0
                              : reserva,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: r.anchoContenido,
                            ),
                            child: _vista(),
                          ),
                        ),
                      ),
                    ),
                    // En la compra la barra de resumen (asientos, total, Cancelar/Continuar) va pegada abajo: se le reserva el espacio
                    // del boton del asistente Y, cuando hay algo que decir, el de los subtitulos, para que nada se tape.
                    if (_cine.pantalla == Pantalla.compra)
                      ListenableBuilder(
                        listenable: _voz,
                        builder: (_, _) => AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          height:
                              reserva +
                              (_lineasSubtitulo(_voz).visible ? altoSub : 0),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned.fill(child: _anillos(anchor)),
              Positioned(
                left: margenLado,
                right: margenLado,
                bottom: reserva - 4,
                child: SizedBox(
                  height: altoSub,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: _Subtitulos(voz: _voz),
                  ),
                ),
              ),
              VentanasLayer(
                ui: _ui,
                reservaInferior: reserva + 6,
                onDecir: _voz.enviarTexto,
              ),
              Positioned(
                bottom: _kButtonBottomMargin + mq.padding.bottom,
                left: 0,
                right: 0,
                child: Center(child: _boton()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vista() {
    final nombre = AuthService.instance.usuario?.nombre ?? 'cliente';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
      child: switch (_cine.pantalla) {
        Pantalla.inicio => ListenableBuilder(
          key: const ValueKey('inicio'),
          listenable: _voz,
          builder: (_, _) => InicioView(
            cine: _cine,
            nombre: nombre,
            conversando: _voz.conversando,
            gestor: _gestor,
            onSinConexion: _abrirModoSinConexion,
          ),
        ),
        Pantalla.cartelera => CarteleraView(
          key: const ValueKey('cartelera'),
          cine: _cine,
          ui: _ui,
          alTrailer: _alTrailer,
        ),
        Pantalla.compra => CompraView(
          key: const ValueKey('compra'),
          cine: _cine,
          ui: _ui,
          pagos: _pagos,
          onPagoCampos: (id, campos) {
            if (_voz.conversando) _voz.enviarPagoCampos(id, campos);
          },
          onPagoEvento: (id, evento, [mensaje]) {
            if (_voz.conversando) _voz.enviarPagoEvento(id, evento, mensaje);
          },
        ),
        Pantalla.misCompras => MisComprasView(
          key: const ValueKey('mis_compras'),
          cine: _cine,
        ),
      },
    );
  }

  Widget _anillos(Offset anchor) => IgnorePointer(
    child: ListenableBuilder(
      listenable: Listenable.merge([_ringController, _voz]),
      builder: (context, _) => CustomPaint(
        painter: EdgeRingsPainter(
          anchor: anchor,
          shimmer: _ringController.value,
          intensity: _voz.conversando ? 1.0 : 0.25,
          colorA: LumenColors.primaryContainer,
          colorB: LumenColors.secondary,
        ),
      ),
    ),
  );

  Widget _boton() {
    return ListenableBuilder(
      listenable: _voz,
      builder: (context, _) {
        final tamano = Responsivo.de(context).tamanoBoton;
        final silenciado = _voz.silenciado;
        final activa = _voz.conversando;
        final gradiente = silenciado
            ? const LinearGradient(
                colors: [
                  LumenColors.surfaceContainer,
                  LumenColors.surfaceContainerHigh,
                ],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  LumenColors.surfaceContainer,
                  LumenColors.primaryContainer,
                  LumenColors.secondary,
                ],
              );

        final IconData icono;
        if (silenciado && activa) {
          icono = Icons.mic_off;
        } else {
          icono = switch (_voz.estado) {
            EstadoConversacion.apagada => Icons.mic,
            EstadoConversacion.conectando => Icons.more_horiz,
            EstadoConversacion.escuchando => Icons.graphic_eq,
            EstadoConversacion.pensando => Icons.more_horiz,
            EstadoConversacion.hablando => Icons.stop_rounded,
            EstadoConversacion.error => Icons.refresh,
          };
        }

        return GestureDetector(
          onTap: _tocarBoton,
          onLongPress: _confirmarCerrarSesion,
          onDoubleTap: _voz.activa ? _alternarSilencio : null,
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final latido =
                  (activa &&
                      (_voz.usuarioHablando ||
                          _voz.estado == EstadoConversacion.hablando))
                  ? 1 + _pulseController.value * 0.09
                  : 1.0;
              return Transform.scale(scale: latido, child: child);
            },
            child: Container(
              width: tamano,
              height: tamano,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: gradiente,
                boxShadow: silenciado
                    ? const []
                    : [
                        BoxShadow(
                          color: LumenColors.primaryContainer.withValues(
                            alpha: activa ? 0.6 : 0.35,
                          ),
                          blurRadius: 44,
                          spreadRadius: 2,
                        ),
                      ],
              ),
              child: Icon(
                icono,
                size: tamano * 0.43,
                color: silenciado
                    ? LumenColors.onSurfaceVariant
                    : LumenColors.onPrimaryContainer,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------- cabecera

class _Cabecera extends StatelessWidget {
  final CineState cine;
  final VoidCallback onCerrarSesion;
  final VoidCallback onConfigurarIp;

  /// La conversacion se atiende en el telefono (sin internet).
  final bool sinConexion;
  const _Cabecera({
    required this.cine,
    required this.onCerrarSesion,
    required this.onConfigurarIp,
    this.sinConexion = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget boton(IconData icono, String texto, Pantalla destino) {
      final activo = cine.pantalla == destino;
      return Expanded(
        child: GestureDetector(
          onTap: () => cine.irA(destino),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: activo
                  ? LumenColors.primary.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icono,
                    size: 17,
                    color: activo
                        ? LumenColors.primary
                        : LumenColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    texto,
                    style: TextStyle(
                      color: activo
                          ? LumenColors.primary
                          : LumenColors.onSurfaceVariant,
                      fontSize: 12.5,
                      fontWeight: activo ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(
        children: [
          boton(Icons.home_outlined, 'Inicio', Pantalla.inicio),
          boton(Icons.local_movies_outlined, 'Cartelera', Pantalla.cartelera),
          boton(
            Icons.confirmation_number_outlined,
            'Mis compras',
            Pantalla.misCompras,
          ),
          if (sinConexion)
            const Tooltip(
              message: 'Modo sin conexión',
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.cloud_off,
                  size: 19,
                  color: LumenColors.secondary,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Servidor / IP',
            onPressed: onConfigurarIp,
            icon: const Icon(Icons.dns_outlined, size: 20),
            color: LumenColors.onSurfaceVariant,
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: onCerrarSesion,
            icon: const Icon(Icons.logout, size: 20),
            color: LumenColors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------- subtitulos

/// Lo que se entendio y lo que respondio el agente (el panel de voz de "Voz + UI dinamica" en la web).
/// Lo que dicen los subtitulos ahora: lo que se le entendio al cliente, la respuesta del asistente o un aviso de estado.
({String? linea1, String? linea2, Color color, bool visible}) _lineasSubtitulo(
  VoiceSession voz,
) {
  final t = voz.turno;
  String? linea1;
  String? linea2;
  var color = LumenColors.onSurface;

  if (voz.estado == EstadoConversacion.error) {
    linea2 = voz.error ?? 'No se pudo iniciar la conversación.';
    color = LumenColors.error;
  } else if (voz.estado == EstadoConversacion.conectando) {
    linea2 = voz.reconectando
        ? 'Reconectando con el asistente…'
        : 'Conectando…';
  } else if (t.error != null) {
    linea2 = t.error;
    color = LumenColors.error;
  } else if (!t.vacio) {
    linea1 = t.transcript.isEmpty ? null : 'Tú: ${t.transcript}';
    linea2 = t.respuesta.isEmpty
        ? (voz.estado == EstadoConversacion.pensando ? 'Pensando…' : null)
        : t.respuesta;
  } else if (voz.estado == EstadoConversacion.escuchando) {
    linea2 = voz.silenciado
        ? 'Micrófono en silencio (doble toque para activar)'
        : (voz.usuarioHablando ? 'Te escucho…' : null);
  }
  return (
    linea1: linea1,
    linea2: linea2,
    color: color,
    visible: linea1 != null || linea2 != null,
  );
}

class _Subtitulos extends StatelessWidget {
  final VoiceSession voz;
  const _Subtitulos({required this.voz});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: voz,
      builder: (context, _) {
        final l = _lineasSubtitulo(voz);
        return IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: l.visible ? 1 : 0,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: LumenColors.surfaceContainer.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (l.linea1 != null)
                    Text(
                      l.linea1!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: LumenColors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  if (l.linea1 != null && l.linea2 != null)
                    const SizedBox(height: 3),
                  if (l.linea2 != null)
                    Text(
                      l.linea2!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: l.color,
                        fontSize: 14,
                        height: 1.3,
                      ),
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
