import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/cash_screen.dart';
import '../screens/profile_screen.dart';
import '../session.dart';
import '../theme.dart';
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

/// Acceso rápido a la caja, a la izquierda del perfil (con permiso de caja).
class CashButton extends StatelessWidget {
  const CashButton({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final me = session.me;
    if (me == null || !me.can('cash_view') || HomeShell.maybeOf(context) == null) return const SizedBox.shrink();
    final open = session.openCash.isNotEmpty;
    // Punto verde = hay caja abierta · rojo = todas cerradas.
    return IconButton(
      tooltip: open ? 'Caja abierta' : 'Caja cerrada',
      onPressed: () => openCashFlow(context),
      icon: Badge(
        smallSize: 10,
        backgroundColor: open ? Brand.success : Brand.danger,
        child: Icon(open ? Icons.point_of_sale : Icons.point_of_sale_outlined, color: open ? Brand.primary : null),
      ),
    );
  }
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
