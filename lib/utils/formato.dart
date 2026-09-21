/// Formatos de fecha/hora en español, sin depender de `intl`.
const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const _dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

/// "2026-09-21" -> "21 sep".
String diaCorto(String fecha) {
  final d = DateTime.tryParse(fecha);
  return d == null ? fecha : '${d.day} ${_meses[d.month - 1]}';
}

/// "2026-09-21" -> "lun 21 sep".
String diaLargo(String fecha) {
  final d = DateTime.tryParse(fecha);
  return d == null ? fecha : '${_dias[d.weekday - 1]} ${d.day} ${_meses[d.month - 1]}';
}

/// "20:30:00" -> "20:30".
String hora(String horaInicio) => horaInicio.length >= 5 ? horaInicio.substring(0, 5) : horaInicio;

String bs(num v) => '${v.toStringAsFixed(2)} Bs';
