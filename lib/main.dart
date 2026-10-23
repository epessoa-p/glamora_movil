import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'api/api_client.dart';
import 'config.dart';
import 'screens/company_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'session.dart';
import 'theme.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');

  final session = Session(ApiClient(baseUrl: AppConfig.apiUrl), const SecureSessionStore());
  runApp(GlamoraApp(session: session));
  session.restore();
}

class GlamoraApp extends StatelessWidget {
  const GlamoraApp({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: session,
      child: MaterialApp(
        title: 'Glamora',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const _Root(),
      ),
    );
  }
}

/// Elige la pantalla según el estado de la sesión.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();

    return switch (session.status) {
      SessionStatus.starting => const _Splash(),
      SessionStatus.loggedOut => const LoginScreen(),
      SessionStatus.choosingCompany => const CompanyScreen(),
      // La clave reinicia las pestañas al cambiar de salón.
      SessionStatus.ready => HomeScreen(key: ValueKey(session.me!.company.id)),
      SessionStatus.failed => Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Expanded(child: ErrorView(message: session.error ?? 'No se pudo cargar tu perfil.', onRetry: session.refresh)),
                TextButton(onPressed: session.logout, child: const Text('Cerrar sesión')),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
    };
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/glamora-icon-512.png', width: 96),
            const SizedBox(height: 24),
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
          ],
        ),
      ),
    );
  }
}
