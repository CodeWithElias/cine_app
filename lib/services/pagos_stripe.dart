import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'cine_api.dart';

/// Deja listo el SDK de Stripe con la clave PUBLICABLE que sirve el backend (`GET /pagos/config`).
///
/// La app nunca tiene la clave secreta (`sk_...`): esa vive solo en el `.env` del backend, que es quien crea
/// y verifica los cobros. Aca solo hay una clave publicable (`pk_...`), pensada para ir en la app, y no se escribe
/// en el codigo: asi, si cambia la cuenta de Stripe, la app no hay que recompilarla.
///
/// Si el backend no tiene Stripe configurado (o no responde), `habilitado` queda en false y la app ofrece solo efectivo.
class PagosStripe extends ChangeNotifier {
  bool cargando = true;
  bool habilitado = false;
  bool modoPrueba = false;

  Future<void> iniciar(CineApi api) async {
    try {
      final config = await api.obtenerConfiguracionPagos();
      if (config.habilitado && config.clavePublicable.isNotEmpty) {
        Stripe.publishableKey = config.clavePublicable;
        await Stripe.instance.applySettings();
        habilitado = true;
        modoPrueba = config.clavePublicable.startsWith('pk_test_');
      }
    } catch (e) {
      debugPrint('Stripe no disponible: $e');
      habilitado = false;
    }
    cargando = false;
    notifyListeners();
  }
}
