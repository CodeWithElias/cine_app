/// Modelos del catalogo y de la compra. Espejo de los tipos del frontend web
/// (Parcial1_Sw2_Frontend/src/core/types/*.types.ts): mismos campos, mismos
/// nombres, para que los JSON del backend y las `ui_action` del agente se lean igual.
library;

double _num(dynamic v, [double porDefecto = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? porDefecto;
  return porDefecto;
}

int _int(dynamic v, [int porDefecto = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? porDefecto;
  return porDefecto;
}

String? _str(dynamic v) => v?.toString();

class Pelicula {
  final int idPelicula;
  final String titulo;
  final String? genero;
  final int duracionMin;
  final String? clasificacion;
  final String estado;
  final String? posterUrl;
  final String? sinopsis;

  const Pelicula({
    required this.idPelicula,
    required this.titulo,
    this.genero,
    required this.duracionMin,
    this.clasificacion,
    required this.estado,
    this.posterUrl,
    this.sinopsis,
  });

  factory Pelicula.fromJson(Map<String, dynamic> j) => Pelicula(
    idPelicula: _int(j['idPelicula']),
    titulo: _str(j['titulo']) ?? '',
    genero: _str(j['genero']),
    duracionMin: _int(j['duracionMin']),
    clasificacion: _str(j['clasificacion']),
    estado: _str(j['estado']) ?? 'activa',
    posterUrl: _str(j['posterUrl']),
    sinopsis: _str(j['sinopsis']),
  );

  Map<String, dynamic> toJson() => {
    'idPelicula': idPelicula,
    'titulo': titulo,
    'genero': genero,
    'duracionMin': duracionMin,
    'clasificacion': clasificacion,
    'estado': estado,
    'posterUrl': posterUrl,
    'sinopsis': sinopsis,
  };
}

class Funcion {
  final int idFuncion;
  final int idPelicula;
  final int idSala;
  final int? idPrecio;
  final String fecha; // AAAA-MM-DD
  final String horaInicio; // HH:MM:SS
  final String horaFin;
  final String estado;

  const Funcion({
    required this.idFuncion,
    required this.idPelicula,
    required this.idSala,
    this.idPrecio,
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    required this.estado,
  });

  factory Funcion.fromJson(Map<String, dynamic> j) => Funcion(
    idFuncion: _int(j['idFuncion']),
    idPelicula: _int(j['idPelicula']),
    idSala: _int(j['idSala']),
    idPrecio: j['idPrecio'] == null ? null : _int(j['idPrecio']),
    fecha: _str(j['fecha']) ?? '',
    horaInicio: _str(j['horaInicio']) ?? '',
    horaFin: _str(j['horaFin']) ?? '',
    estado: _str(j['estado']) ?? 'programada',
  );

  Map<String, dynamic> toJson() => {
    'idFuncion': idFuncion,
    'idPelicula': idPelicula,
    'idSala': idSala,
    'idPrecio': idPrecio,
    'fecha': fecha,
    'horaInicio': horaInicio,
    'horaFin': horaFin,
    'estado': estado,
  };

  /// Inicio de la funcion como fecha (hora local del dispositivo).
  DateTime? get inicio => DateTime.tryParse('${fecha}T$horaInicio');
}

class Sala {
  final int idSala;
  final String nombre;
  final String? tipo;

  const Sala({required this.idSala, required this.nombre, this.tipo});

  factory Sala.fromJson(Map<String, dynamic> j) => Sala(
    idSala: _int(j['idSala']),
    nombre: _str(j['nombre']) ?? 'Sala',
    tipo: _str(j['tipo']),
  );
}

/// Un asiento de la sala con su estado para una funcion concreta
/// (`GET /funciones/:id/disponibilidad`).
class AsientoDisponibilidad {
  final int idAsiento;
  final String fila;
  final int numero;
  final String estado; // disponible | ocupado | cancelada

  const AsientoDisponibilidad({
    required this.idAsiento,
    required this.fila,
    required this.numero,
    required this.estado,
  });

  factory AsientoDisponibilidad.fromJson(Map<String, dynamic> j) {
    final a = (j['asiento'] as Map?)?.cast<String, dynamic>() ?? const {};
    return AsientoDisponibilidad(
      idAsiento: _int(j['idAsiento'] ?? a['idAsiento']),
      fila: _str(a['fila']) ?? '?',
      numero: _int(a['numero']),
      estado: _str(j['estado']) ?? 'disponible',
    );
  }

  bool get disponible => estado == 'disponible';
}

class Butaca {
  final String id; // "A5"
  final int idAsiento;
  final String fila;
  final int columna;
  final double precio;

  const Butaca({
    required this.id,
    required this.idAsiento,
    required this.fila,
    required this.columna,
    required this.precio,
  });

  factory Butaca.fromJson(Map<String, dynamic> j) => Butaca(
    id: _str(j['id']) ?? '',
    idAsiento: _int(j['idAsiento']),
    fila: _str(j['fila']) ?? '',
    columna: _int(j['columna']),
    precio: _num(j['precio']),
  );
}

class CategoriaDulceria {
  final int idCategoria;
  final String nombre;

  const CategoriaDulceria({required this.idCategoria, required this.nombre});

  factory CategoriaDulceria.fromJson(Map<String, dynamic> j) =>
      CategoriaDulceria(
        idCategoria: _int(j['idCategoria']),
        nombre: _str(j['nombre']) ?? '',
      );

  Map<String, dynamic> toJson() => {
    'idCategoria': idCategoria,
    'nombre': nombre,
  };
}

class ProductoDulceria {
  final int idProducto;
  final int idCategoria;
  final String nombre;
  final String? descripcion;
  final double precioBase;
  final bool disponible;
  final String? imagenUrl;

  const ProductoDulceria({
    required this.idProducto,
    required this.idCategoria,
    required this.nombre,
    this.descripcion,
    required this.precioBase,
    required this.disponible,
    this.imagenUrl,
  });

  factory ProductoDulceria.fromJson(Map<String, dynamic> j) => ProductoDulceria(
    idProducto: _int(j['idProducto']),
    idCategoria: _int(j['idCategoria']),
    nombre: _str(j['nombre']) ?? '',
    descripcion: _str(j['descripcion']),
    precioBase: _num(j['precioBase']),
    disponible: j['disponible'] != false,
    imagenUrl: _str(j['imagenUrl']),
  );

  Map<String, dynamic> toJson() => {
    'idProducto': idProducto,
    'idCategoria': idCategoria,
    'nombre': nombre,
    'descripcion': descripcion,
    'precioBase': precioBase,
    'disponible': disponible,
    'imagenUrl': imagenUrl,
  };
}

class ItemDulceria {
  final String id; // idProducto como texto (igual que en la web)
  final String nombre;
  final String descripcion;
  final double precio;
  final String imagenUrl;
  final int cantidad;

  const ItemDulceria({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.precio,
    required this.imagenUrl,
    required this.cantidad,
  });

  factory ItemDulceria.fromJson(Map<String, dynamic> j) => ItemDulceria(
    id: _str(j['id']) ?? '',
    nombre: _str(j['nombre']) ?? '',
    descripcion: _str(j['descripcion']) ?? '',
    precio: _num(j['precio']),
    imagenUrl: _str(j['imagenUrl']) ?? '',
    cantidad: _int(j['cantidad']),
  );

  ItemDulceria conCantidad(int c) => ItemDulceria(
    id: id,
    nombre: nombre,
    descripcion: descripcion,
    precio: precio,
    imagenUrl: imagenUrl,
    cantidad: c,
  );
}

class Venta {
  final int idVenta;
  final int idFuncion;
  final double total;
  final String estado;
  final String? metodoPagoElegido;
  final String? fechaHora;

  /// 'voz' si la creo el agente al confirmar; 'manual' si la creo la pantalla.
  final String tipoRegistro;

  const Venta({
    required this.idVenta,
    required this.idFuncion,
    required this.total,
    required this.estado,
    this.metodoPagoElegido,
    this.fechaHora,
    this.tipoRegistro = 'manual',
  });

  factory Venta.fromJson(Map<String, dynamic> j) => Venta(
    idVenta: _int(j['idVenta']),
    idFuncion: _int(j['idFuncion']),
    total: _num(j['total']),
    estado: _str(j['estado']) ?? '',
    metodoPagoElegido: _str(j['metodoPagoElegido']),
    fechaHora: _str(j['fechaHora']),
    tipoRegistro: _str(j['tipoRegistro']) ?? 'manual',
  );

  Map<String, dynamic> toJson() => {
    'idVenta': idVenta,
    'idFuncion': idFuncion,
    'total': total,
    'estado': estado,
    'metodoPagoElegido': metodoPagoElegido,
    'fechaHora': fechaHora,
    'tipoRegistro': tipoRegistro,
  };
}

/// `GET /pagos/config`: si el pago con tarjeta esta disponible y con que clave PUBLICABLE de Stripe
/// (la secreta nunca sale del backend ni llega a la app).
class ConfigPagos {
  final bool habilitado;
  final String clavePublicable;
  final String moneda;

  const ConfigPagos({
    required this.habilitado,
    required this.clavePublicable,
    required this.moneda,
  });

  factory ConfigPagos.fromJson(Map<String, dynamic> j) {
    final s = (j['stripe'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ConfigPagos(
      habilitado: s['habilitado'] == true,
      clavePublicable: _str(s['clavePublicable']) ?? '',
      moneda: _str(s['moneda']) ?? 'bob',
    );
  }
}

/// `POST /pagos/stripe/iniciar`: el `clientSecret` es lo unico que necesita Stripe para confirmar el cobro.
class InicioPagoStripe {
  final int idPago;
  final int idVenta;
  final String clientSecret;

  const InicioPagoStripe({
    required this.idPago,
    required this.idVenta,
    required this.clientSecret,
  });

  factory InicioPagoStripe.fromJson(Map<String, dynamic> j) => InicioPagoStripe(
    idPago: _int(j['idPago']),
    idVenta: _int(j['idVenta']),
    clientSecret: _str(j['clientSecret']) ?? '',
  );
}

/// `POST /pagos/:id/verificar`: el SERVIDOR le pregunta a Stripe como quedo el cobro; la venta solo
/// queda `pagada` si Stripe lo confirmo.
class VerificacionPago {
  final String estado;
  final Venta venta;
  final String? mensaje;

  const VerificacionPago({
    required this.estado,
    required this.venta,
    this.mensaje,
  });

  factory VerificacionPago.fromJson(Map<String, dynamic> j) => VerificacionPago(
    estado: _str(j['estado']) ?? '',
    venta: Venta.fromJson((j['venta'] as Map).cast<String, dynamic>()),
    mensaje: _str(j['mensaje']),
  );
}

/// Una compra del historial (`GET /ventas`), con su funcion, pelicula y sala.
class CompraHistorial {
  final Venta venta;
  final String pelicula;
  final String sala;
  final String fecha;
  final String horaInicio;

  const CompraHistorial({
    required this.venta,
    required this.pelicula,
    required this.sala,
    required this.fecha,
    required this.horaInicio,
  });

  factory CompraHistorial.fromJson(Map<String, dynamic> j) {
    final f = (j['funcion'] as Map?)?.cast<String, dynamic>() ?? const {};
    final p = (f['pelicula'] as Map?)?.cast<String, dynamic>() ?? const {};
    final s = (f['sala'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CompraHistorial(
      venta: Venta.fromJson(j),
      pelicula: _str(p['titulo']) ?? 'Película',
      sala: _str(s['nombre']) ?? '',
      fecha: _str(f['fecha']) ?? '',
      horaInicio: _str(f['horaInicio']) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    ...venta.toJson(),
    'funcion': {
      'fecha': fecha,
      'horaInicio': horaInicio,
      'pelicula': {'titulo': pelicula},
      'sala': {'nombre': sala},
    },
  };
}

/// Detalle de una compra (`GET /ventas/:id`): asientos y dulceria.
class DetalleCompra {
  final List<String> asientos;
  final List<String> dulceria; // "2 × Pochoclo"

  const DetalleCompra({required this.asientos, required this.dulceria});

  factory DetalleCompra.fromJson(Map<String, dynamic> j) {
    final entradas = (j['detalleEntradas'] as List?) ?? const [];
    final dulces = (j['detalleDulceria'] as List?) ?? const [];
    return DetalleCompra(
      asientos: entradas.map((e) {
        final a =
            ((e as Map)['asiento'] as Map?)?.cast<String, dynamic>() ??
            const {};
        return '${_str(a['fila']) ?? ''}${_str(a['numero']) ?? ''}';
      }).toList(),
      dulceria: dulces.map((d) {
        final m = (d as Map).cast<String, dynamic>();
        final p = (m['producto'] as Map?)?.cast<String, dynamic>() ?? const {};
        return '${_int(m['cantidad'])} × ${_str(p['nombre']) ?? 'Producto'}';
      }).toList(),
    );
  }
}

enum EstadoCompra {
  seleccionandoAsientos,
  seleccionandoCandybar,
  pago,
  completado,
}

EstadoCompra estadoCompraDeDestino(String destino) => switch (destino) {
  'candybar' => EstadoCompra.seleccionandoCandybar,
  'pago' => EstadoCompra.pago,
  _ => EstadoCompra.seleccionandoAsientos,
};
