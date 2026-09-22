import 'package:flutter_test/flutter_test.dart';

import 'package:cine_app/theme/app_theme.dart';

void main() {
  test('el theme de Lumen Cinema usa los colores de marca', () {
    expect(lumenTheme.colorScheme.primary, LumenColors.primary);
    expect(lumenTheme.colorScheme.secondary, LumenColors.secondary);
    expect(
      lumenTheme.scaffoldBackgroundColor,
      LumenColors.surfaceContainerLowest,
    );
  });

  // Nota: no se agrega un widget test de arranque completo (pumpWidget(CineApp()))
  // porque _StartupGate llama a plugins con canales de plataforma (SharedPreferences,
  // GoogleSignIn) que no estan disponibles en el entorno de test sin mocks.
}
