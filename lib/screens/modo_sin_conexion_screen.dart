import 'package:flutter/material.dart';

import '../offline/cache_local.dart';
import '../offline/gestor_modelos.dart';
import '../services/cine_api.dart';
import '../theme/app_theme.dart';

String _mb(num bytes) => bytes >= 1024 * 1024 * 1024
    ? '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB'
    : '${(bytes / 1024 / 1024).round()} MB';

/// Aqui el cliente elige si quiere llevar los modelos de voz al telefono para usar a Lumen sin internet: los descarga (solo por
/// Wi‑Fi si quiere), los pausa, los reanuda o los borra. Con ellos descargados, la app pasa sola al asistente del telefono
/// cuando no hay internet.
class ModoSinConexionScreen extends StatefulWidget {
  final GestorModelos gestor;
  final CineApi api;
  const ModoSinConexionScreen({
    super.key,
    required this.gestor,
    required this.api,
  });

  @override
  State<ModoSinConexionScreen> createState() => _ModoSinConexionScreenState();
}

class _ModoSinConexionScreenState extends State<ModoSinConexionScreen> {
  DateTime? _copia;
  bool _actualizando = false;

  GestorModelos get g => widget.gestor;

  @override
  void initState() {
    super.initState();
    g.iniciar();
    _leerCopia();
  }

  Future<void> _leerCopia() async {
    final c = await CacheLocal.instance.fechaDeCartelera();
    if (mounted) setState(() => _copia = c);
  }

  Future<void> _actualizarDatos() async {
    setState(() => _actualizando = true);
    try {
      await Future.wait<Object>([
        widget.api.listarPeliculas(),
        widget.api.listarFunciones(),
        widget.api.listarCategoriasDulceria(),
        widget.api.listarProductosDulceria(),
        widget.api.listarMisCompras().then<Object>(
          (l) => l,
          onError: (Object _) => <Object>[],
        ),
      ]);
      await Future<void>.delayed(
        const Duration(milliseconds: 300),
      ); // deja terminar de escribir las copias
      await _leerCopia();
      if (CineApi.datosGuardadosDesde.value != null) {
        _aviso('No hay conexión: se siguen usando los datos guardados.');
      } else {
        _aviso('Datos guardados al día.');
      }
    } catch (_) {
      _aviso('No se pudieron actualizar los datos.');
    } finally {
      if (mounted) setState(() => _actualizando = false);
    }
  }

  void _aviso(String t) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _confirmarBorrar(PaqueteModelo p) async {
    final si = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: LumenColors.surfaceContainer,
        title: const Text(
          'Borrar del teléfono',
          style: TextStyle(color: LumenColors.onSurface),
        ),
        content: Text(
          'Se borra «${p.nombre}» (${_mb(p.bytesTotal)}). Para usar el modo sin conexión tendrías que descargarlo otra vez.',
          style: const TextStyle(color: LumenColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text(
              'Borrar',
              style: TextStyle(color: LumenColors.error),
            ),
          ),
        ],
      ),
    );
    if (si == true) await g.eliminar(p.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LumenColors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: LumenColors.surfaceContainerLowest,
        foregroundColor: LumenColors.onSurface,
        title: const Text(
          'Modo sin conexión',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListenableBuilder(
        listenable: g,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            _intro(),
            const SizedBox(height: 12),
            _estadoGeneral(),
            const SizedBox(height: 16),
            _titulo('AJUSTES'),
            _interruptor(
              titulo: 'Descargar solo con Wi‑Fi',
              detalle:
                  'Evita gastar tus datos móviles: son varios cientos de MB.',
              valor: g.soloWifi,
              onCambio: g.setSoloWifi,
            ),
            _interruptor(
              titulo: 'Usar siempre el asistente del teléfono',
              detalle: g.listoParaVoz
                  ? 'Aunque haya internet. Sin esto, el teléfono solo se usa cuando no hay conexión.'
                  : 'Disponible cuando termines de descargar los modelos.',
              valor: g.preferirLocal,
              onCambio: g.listoParaVoz ? g.setPreferirLocal : null,
            ),
            const SizedBox(height: 16),
            _titulo('RECONOCIMIENTO DE VOZ (elige uno)'),
            _tarjetaModelo(paquete('stt_tiny'), elegible: true),
            _tarjetaModelo(paquete('stt_base'), elegible: true),
            const SizedBox(height: 8),
            _titulo('VOZ DEL ASISTENTE'),
            _tarjetaModelo(paquete('tts')),
            const SizedBox(height: 12),
            if (!g.listoParaVoz) _botonRecomendado(),
            const SizedBox(height: 20),
            _titulo('DATOS GUARDADOS'),
            _datos(),
          ],
        ),
      ),
    );
  }

  Widget _intro() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: LumenColors.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.cloud_off_outlined, color: LumenColors.secondary),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Descarga los modelos de voz para hablar con Lumen y consultar la cartelera, los horarios y tus compras aunque no tengas internet.\n\nComprar y pagar siempre necesitan conexión.',
            style: TextStyle(
              color: LumenColors.onSurface,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _estadoGeneral() {
    final listo = g.listoParaVoz;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            (listo
                    ? LumenColors.tertiaryContainer
                    : LumenColors.surfaceContainerHigh)
                .withValues(alpha: listo ? 0.18 : 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            listo ? Icons.check_circle : Icons.download_for_offline_outlined,
            color: listo ? LumenColors.tertiary : LumenColors.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              listo
                  ? 'Listo. Sin internet, Lumen usa automáticamente el asistente del teléfono.'
                  : 'Todavía no descargaste el modo sin conexión. Es opcional: sin él, la app necesita internet para hablar con Lumen.',
              style: TextStyle(
                color: listo ? LumenColors.tertiary : LumenColors.onSurface,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _titulo(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6, left: 2),
    child: Text(
      t,
      style: const TextStyle(
        color: LumenColors.primary,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.9,
      ),
    ),
  );

  Widget _interruptor({
    required String titulo,
    required String detalle,
    required bool valor,
    required ValueChanged<bool>? onCambio,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: LumenColors.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: SwitchListTile(
      value: valor,
      onChanged: onCambio,
      activeThumbColor: LumenColors.primary,
      title: Text(
        titulo,
        style: const TextStyle(
          color: LumenColors.onSurface,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        detalle,
        style: const TextStyle(
          color: LumenColors.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    ),
  );

  Widget _botonRecomendado() {
    final total = paquete(g.sttElegido).bytesTotal + paquete('tts').bytesTotal;
    return FilledButton.icon(
      onPressed: g.descargando ? null : g.descargarRecomendados,
      icon: const Icon(Icons.download),
      label: Text('Descargar lo recomendado (≈ ${_mb(total)})'),
    );
  }

  Widget _tarjetaModelo(PaqueteModelo p, {bool elegible = false}) {
    final e = g.estado(p.id);
    final elegido = elegible && g.sttElegido == p.id;
    final descargandoEste = e == EstadoPaquete.descargando;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LumenColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: elegido ? LumenColors.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (elegible)
                GestureDetector(
                  onTap: () => g.setSttElegido(p.id),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Icon(
                      elegido
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: elegido
                          ? LumenColors.primary
                          : LumenColors.onSurfaceVariant,
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  p.nombre,
                  style: const TextStyle(
                    color: LumenColors.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '≈ ${_mb(p.bytesTotal)}',
                style: const TextStyle(
                  color: LumenColors.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            p.descripcion,
            style: const TextStyle(
              color: LumenColors.onSurfaceVariant,
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
          if (e == EstadoPaquete.descargando || e == EstadoPaquete.pausado) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: g.progreso(p.id),
                minHeight: 7,
                backgroundColor: LumenColors.surfaceContainerHighest,
                color: LumenColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_mb(g.bytesDescargados(p.id))} de ${_mb(p.bytesTotal)} · ${(g.progreso(p.id) * 100).round()} %${e == EstadoPaquete.pausado ? ' · en pausa' : ''}',
              style: const TextStyle(
                color: LumenColors.onSurfaceVariant,
                fontSize: 11.5,
              ),
            ),
          ],
          if (e == EstadoPaquete.error && g.error(p.id) != null) ...[
            const SizedBox(height: 8),
            Text(
              g.error(p.id)!,
              style: const TextStyle(color: LumenColors.error, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (e == EstadoPaquete.listo) ...[
                const Icon(
                  Icons.check_circle,
                  size: 18,
                  color: LumenColors.tertiary,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Descargado',
                  style: TextStyle(
                    color: LumenColors.tertiary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _confirmarBorrar(p),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Borrar'),
                ),
              ] else ...[
                if (descargandoEste)
                  OutlinedButton.icon(
                    onPressed: g.pausar,
                    icon: const Icon(Icons.pause),
                    label: const Text('Pausar'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: g.descargando ? null : () => g.descargar(p.id),
                    icon: Icon(
                      e == EstadoPaquete.pausado || e == EstadoPaquete.error
                          ? Icons.play_arrow
                          : Icons.download,
                    ),
                    label: Text(
                      e == EstadoPaquete.pausado || e == EstadoPaquete.error
                          ? 'Reanudar'
                          : 'Descargar',
                    ),
                  ),
                const Spacer(),
                if (e == EstadoPaquete.pausado || e == EstadoPaquete.error)
                  TextButton(
                    onPressed: () => _confirmarBorrar(p),
                    child: const Text('Descartar'),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _datos() {
    final c = _copia;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LumenColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c == null
                ? 'Todavía no hay una copia de la cartelera. Se guarda sola cada vez que abres la cartelera con internet.'
                : 'Cartelera guardada el ${c.day}/${c.month} a las ${c.hour.toString().padLeft(2, '0')}:${c.minute.toString().padLeft(2, '0')}. Se actualiza sola cada vez que tienes internet.',
            style: const TextStyle(
              color: LumenColors.onSurface,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _actualizando ? null : _actualizarDatos,
            icon: _actualizando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: const Text('Actualizar ahora'),
          ),
        ],
      ),
    );
  }
}
