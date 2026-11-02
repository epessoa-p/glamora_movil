import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../util/format.dart';

/// Mensaje de error a pantalla completa con botón de reintento.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry, this.icon});

  final String message;
  final VoidCallback? onRetry;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return _Centered(
      icon: icon ?? Icons.cloud_off_rounded,
      text: message,
      action: onRetry == null ? null : OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
    );
  }
}

/// Estado vacío ("No hay citas este día").
class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.text, this.icon = Icons.inbox_outlined, this.action});

  final String text;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => _Centered(icon: icon, text: text, action: action);
}

class _Centered extends StatelessWidget {
  const _Centered({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    // ListView para que funcione el "deslizar para actualizar" aun vacío.
    return LayoutBuilder(
      builder: (context, box) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 56, color: muted.withValues(alpha: .5)),
                  const SizedBox(height: 12),
                  Text(text, textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 15)),
                  if (action != null) ...[const SizedBox(height: 16), action!],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Píldora de color para estados (cita, asistencia, comisión).
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.radius = 20});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      child: Text(initials(name), style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700, fontSize: radius * .7)),
    );
  }
}

/// Texto del error para mostrar: los de la API ya vienen en español.
String errorText(Object e) => e is ApiException ? e.message : 'Ocurrió un error inesperado.';

void showMessage(BuildContext context, String text, {bool error = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: error ? Theme.of(context).colorScheme.error : null,
  ));
}

Future<bool> confirm(BuildContext context, {required String title, required String message, String ok = 'Aceptar'}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: () => Navigator.pop(context, true),
          child: Text(ok),
        ),
      ],
    ),
  );

  return result ?? false;
}

/// Logo de la empresa en un círculo blanco. Sin logo, si la imagen no carga
/// o mientras carga, muestra las iniciales del salón (nunca un error).
class CompanyLogo extends StatelessWidget {
  const CompanyLogo({super.key, required this.name, this.url, this.radius = 28});

  final String name;
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(initials(name), style: TextStyle(color: Brand.primary, fontWeight: FontWeight.w800, fontSize: radius * .7)),
    );
    final hasUrl = url != null && url!.trim().isNotEmpty && Uri.tryParse(url!)?.hasScheme == true;

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 6)]),
      clipBehavior: Clip.antiAlias,
      child: hasUrl
          ? Image.network(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
              loadingBuilder: (_, child, progress) => progress == null ? child : fallback,
            )
          : fallback,
    );
  }
}
