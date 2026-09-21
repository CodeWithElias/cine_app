import 'dart:async';

import 'package:flutter/material.dart';

import '../models/cine_models.dart';
import '../state/cine_state.dart';
import '../state/ui_control.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import '../widgets/aviso_datos_guardados.dart';
import '../widgets/estrenos_carousel.dart';
import '../widgets/poster.dart';

/// Cartelera: peliculas activas con sus funciones futuras, filtro por dia y por
/// texto (lo escribe el cliente o lo pide el agente) y resaltado de lo que el
/// agente esta señalando. Espejo de `views/Cartelera.tsx` de la web.
class CarteleraView extends StatefulWidget {
  final CineState cine;
  final UiControl ui;

  /// Se abre o se cierra un trailer (ver `EstrenosCarousel.alTrailer`).
  final void Function(bool abierto)? alTrailer;

  const CarteleraView({super.key, required this.cine, required this.ui, this.alTrailer});

  @override
  State<CarteleraView> createState() => _CarteleraViewState();
}

class _CarteleraViewState extends State<CarteleraView> {
  Map<int, List<Funcion>> _funciones = {};
  List<String> _dias = [];
  String? _dia;
  String _texto = '';
  bool _cargando = true;
  String? _error;

  final _busquedaCtl = TextEditingController();
  final _claves = <int, GlobalKey>{};
  int _resaltadoVisto = 0;
  int? _scrollPendiente; // pelicula a la que hay que desplazarse en cuanto exista su tarjeta
  int _intentosScroll = 0;
  Timer? _reintentoScroll;
  int _filtroVisto = 0;

  @override
  void initState() {
    super.initState();
    _aplicarFiltroDelAgente(); // un filtro pedido justo antes de abrir esta pantalla ("busca Barbie")
    _cargar();
  }

  @override
  void dispose() {
    _reintentoScroll?.cancel();
    widget.ui.filtro = null; // al salir, el filtro del agente no debe reaparecer la proxima vez
    _busquedaCtl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final api = widget.cine.api;
      final resultados = await Future.wait<Object>([api.listarPeliculas(), api.listarFunciones()]);
      final peliculas = (resultados[0] as List<Pelicula>).where((p) => p.estado == 'activa').toList();
      final ahora = DateTime.now();
      final futuras = (resultados[1] as List<Funcion>).where((f) {
        final inicio = f.inicio;
        return f.estado == 'programada' && inicio != null && !inicio.isBefore(ahora);
      }).toList()
        ..sort((a, b) => '${a.fecha}${a.horaInicio}'.compareTo('${b.fecha}${b.horaInicio}'));

      final agrupadas = <int, List<Funcion>>{};
      for (final f in futuras) {
        agrupadas.putIfAbsent(f.idPelicula, () => []).add(f);
      }
      if (!mounted) return;
      widget.cine.setPeliculas(peliculas);
      setState(() {
        _funciones = agrupadas;
        _dias = futuras.map((f) => f.fecha).toSet().toList()..sort();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar la cartelera. Intenta de nuevo.';
        _cargando = false;
      });
    }
  }

  /// El agente pidio filtrar ("busca Barbie", "las del viernes"): se aplica una vez por pedido.
  void _aplicarFiltroDelAgente() {
    final f = widget.ui.filtro;
    if (f == null || widget.ui.filtroN == _filtroVisto) return;
    _filtroVisto = widget.ui.filtroN;
    _texto = f.busqueda ?? '';
    _busquedaCtl.text = _texto;
    _dia = f.dia;
  }

  /// El agente señalo una pelicula ("quiero ver Oppenheimer"): la lista se desplaza hasta su tarjeta. Como la tarjeta puede
  /// no existir todavia (la cartelera aun se esta cargando, o recien se abrio esta pantalla), se reintenta hasta que aparezca.
  void _seguirResaltado() {
    final r = widget.ui.resaltado;
    if (r == null) {
      _scrollPendiente = null;
      return;
    }
    if (r.n == _resaltadoVisto) return;
    _resaltadoVisto = r.n;
    _scrollPendiente = r.ids.firstOrNull;
    _intentosScroll = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => _intentarScroll());
  }

  void _intentarScroll() {
    final id = _scrollPendiente;
    if (id == null || !mounted) return;
    final contexto = _claves[id]?.currentContext;
    if (contexto != null && !_cargando) {
      _scrollPendiente = null;
      Scrollable.ensureVisible(contexto, duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic, alignment: 0.1);
      return;
    }
    if (++_intentosScroll > 80) return; // ~10 s: el resaltado ya se apago
    _reintentoScroll?.cancel();
    _reintentoScroll = Timer(const Duration(milliseconds: 120), _intentarScroll);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.cine, widget.ui]),
      builder: (context, _) {
        _aplicarFiltroDelAgente();
        final q = _texto.toLowerCase();
        final visibles = widget.cine.peliculas
            .where((p) => q.isEmpty || p.titulo.toLowerCase().contains(q) || (p.genero ?? '').toLowerCase().contains(q))
            .toList();
        _seguirResaltado();

        return RefreshIndicator(
          onRefresh: _cargar,
          color: LumenColors.primary,
          // Columna dentro de un scroll (no un ListView): un ListView solo construye lo que se ve, y la tarjeta a la que el
          // agente quiere desplazarse esta mas abajo y todavia no existiria.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              const AvisoDatosGuardados(),
              // Estrenos y trailers (los mismos de la web); "Comprar" señala la pelicula en la lista de abajo.
              EstrenosCarousel(
                cartelera: widget.cine.peliculas,
                onComprar: (p) => widget.ui.resaltarCartelera([p.idPelicula]),
                alTrailer: widget.alTrailer,
              ),
              const SizedBox(height: 26),
              _cabecera(visibles.length),
              const SizedBox(height: 10),
              _filtroDias(),
              const SizedBox(height: 12),
              if (_cargando)
                const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                _mensaje(Icons.cloud_off, _error!, accion: 'Reintentar', onAccion: _cargar)
              else if (visibles.isEmpty)
                _mensaje(Icons.search_off, q.isEmpty ? 'No hay películas en cartelera.' : 'Sin resultados para «$_texto».')
              else
                for (final p in visibles) _tarjeta(p),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cabecera(int cantidad) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CATÁLOGO EN EXHIBICIÓN', style: _etiqueta(LumenColors.primary)),
        const SizedBox(height: 2),
        const Text('Películas en cartelera',
            style: TextStyle(color: LumenColors.onSurface, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        TextField(
          onChanged: (v) => setState(() => _texto = v),
          controller: _busquedaCtl,
          style: const TextStyle(color: LumenColors.onSurface),
          decoration: InputDecoration(
            hintText: 'Buscar título o género…',
            hintStyle: const TextStyle(color: LumenColors.onSurfaceVariant),
            prefixIcon: const Icon(Icons.search, color: LumenColors.onSurfaceVariant),
            suffixIcon: _texto.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, color: LumenColors.onSurfaceVariant),
                    onPressed: () => setState(() {
                      _texto = '';
                      _busquedaCtl.clear();
                    }),
                  ),
            filled: true,
            fillColor: LumenColors.surfaceContainerLow,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        if (cantidad > 0 && !_cargando)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Mostrando $cantidad ${cantidad == 1 ? 'título' : 'títulos'}', style: _etiqueta(LumenColors.onSurfaceVariant)),
          ),
      ],
    );
  }

  Widget _filtroDias() {
    Widget chip(String texto, bool activo, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: activo ? LumenColors.primary : LumenColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(texto,
                  style: TextStyle(
                    color: activo ? LumenColors.onPrimary : LumenColors.onSurface,
                    fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                  )),
            ),
          ),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Text('DÍA', style: _etiqueta(LumenColors.onSurfaceVariant)),
          const SizedBox(width: 10),
          chip('Todos', _dia == null, () => setState(() => _dia = null)),
          if (_dias.isEmpty && !_cargando)
            const Text('Sin funciones programadas', style: TextStyle(color: LumenColors.onSurfaceVariant, fontSize: 12)),
          for (final d in _dias) chip(diaCorto(d), _dia == d, () => setState(() => _dia = d)),
        ],
      ),
    );
  }

  Widget _tarjeta(Pelicula p) {
    final r = widget.ui.resaltado;
    final senalada = r != null && r.ids.contains(p.idPelicula);
    final funciones = (_funciones[p.idPelicula] ?? const <Funcion>[]).where((f) => _dia == null || f.fecha == _dia).toList();
    final clave = _claves.putIfAbsent(p.idPelicula, () => GlobalKey());

    return AnimatedContainer(
      key: clave,
      duration: const Duration(milliseconds: 350),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LumenColors.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: senalada ? LumenColors.primary : Colors.transparent, width: 2),
        boxShadow: senalada ? [BoxShadow(color: LumenColors.primaryContainer.withValues(alpha: 0.45), blurRadius: 28)] : const [],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Poster(url: p.posterUrl, width: 96, height: 144),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.titulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: senalada ? LumenColors.primary : LumenColors.onSurface, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(p.genero ?? 'Género no especificado', style: const TextStyle(color: LumenColors.secondary, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, children: [
                  _pildora(p.clasificacion ?? 'Sin clasificar'),
                  _pildora('${p.duracionMin} min'),
                ]),
                const SizedBox(height: 8),
                if (senalada)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: LumenColors.primary, borderRadius: BorderRadius.circular(10)),
                    child: const Text('SEÑALADA POR LUMEN',
                        style: TextStyle(color: LumenColors.onPrimary, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                  ),
                Text('HORARIOS', style: _etiqueta(LumenColors.onSurfaceVariant)),
                const SizedBox(height: 4),
                if (funciones.isEmpty)
                  const Text('Sin funciones programadas', style: TextStyle(color: LumenColors.onSurfaceVariant, fontSize: 12))
                else
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final f in funciones) _horario(p, f, r)]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _horario(Pelicula p, Funcion f, ResaltadoCartelera? r) {
    final marcado = r?.idFuncion == f.idFuncion;
    return GestureDetector(
      onTap: () {
        widget.cine.seleccionarFuncion(p, f);
        widget.cine.irA(Pantalla.compra);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: marcado ? LumenColors.primary : LumenColors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '${diaCorto(f.fecha)} · ${hora(f.horaInicio)}',
          style: TextStyle(
            color: marcado ? LumenColors.onPrimary : LumenColors.onSurface,
            fontSize: 12,
            fontWeight: marcado ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _pildora(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: LumenColors.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: const TextStyle(color: LumenColors.onSurfaceVariant, fontSize: 11)),
      );

  Widget _mensaje(IconData icono, String texto, {String? accion, VoidCallback? onAccion}) => Padding(
        padding: const EdgeInsets.only(top: 50),
        child: Column(children: [
          Icon(icono, size: 40, color: LumenColors.outline),
          const SizedBox(height: 10),
          Text(texto, textAlign: TextAlign.center, style: const TextStyle(color: LumenColors.onSurfaceVariant)),
          if (accion != null) TextButton(onPressed: onAccion, child: Text(accion)),
        ]),
      );

  TextStyle _etiqueta(Color c) => TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8);
}
