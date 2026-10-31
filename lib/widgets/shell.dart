import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/profile_screen.dart';
import '../session.dart';
import 'common.dart';

/// Da a las pestañas del inicio acceso al menú lateral. Las pantallas abiertas
/// con `push` quedan fuera (otra ruta), así que conservan su flecha de volver.
class HomeShell extends InheritedWidget {
  const HomeShell({super.key, required this.openDrawer, required super.child});

  final VoidCallback openDrawer;

  static HomeShell? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<HomeShell>();

  @override
  bool updateShouldNotify(HomeShell oldWidget) => false;
}

/// Botón del menú lateral para el `leading` del AppBar (null fuera del inicio).
Widget? shellLeading(BuildContext context) {
  final shell = HomeShell.maybeOf(context);
  if (shell == null) return null;
  return IconButton(tooltip: 'Menú', onPressed: shell.openDrawer, icon: const Icon(Icons.menu));
}

/// Avatar arriba a la derecha que abre el perfil (solo en las pestañas del inicio).
class ProfileButton extends StatelessWidget {
  const ProfileButton({super.key});

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me;
    if (me == null || HomeShell.maybeOf(context) == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IconButton(
        tooltip: 'Perfil',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
        icon: Avatar(name: me.personal?.fullName ?? me.user.name, radius: 16),
      ),
    );
  }
}
