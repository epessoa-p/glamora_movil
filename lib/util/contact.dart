import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../widgets/common.dart';

/// Código de país por defecto para números locales (Bolivia: 8 dígitos).
const _countryCode = '591';

/// `+591 7000-0000` → `59170000000`. Un número local de 8 dígitos recibe el código de país.
String normalizePhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  return digits.length == 8 ? '$_countryCode$digits' : digits;
}

Uri callUri(String phone) => Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^\d+]'), ''));

Uri whatsappUri(String phone, [String? message]) => Uri.https(
      'wa.me',
      '/${normalizePhone(phone)}',
      message == null || message.isEmpty ? null : {'text': message},
    );

/// Abre un enlace fuera de la app. Las pruebas lo reemplazan para no abrir nada.
Future<bool> Function(Uri uri) urlOpener = (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

Future<void> openContact(BuildContext context, Uri uri) async {
  final ok = await urlOpener(uri);
  if (!ok && context.mounted) {
    showMessage(context, uri.scheme == 'tel' ? 'No se pudo abrir el teléfono.' : 'No se pudo abrir WhatsApp.', error: true);
  }
}

/// Botones "Llamar" y "WhatsApp" para un teléfono.
class ContactButtons extends StatelessWidget {
  const ContactButtons({super.key, required this.phone, this.message});

  final String phone;

  /// Texto inicial del chat de WhatsApp.
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => openContact(context, callUri(phone)),
            icon: const Icon(Icons.call_outlined),
            label: const Text('Llamar'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: const Color(0xFFDCF8C6), foregroundColor: const Color(0xFF075E54)),
            onPressed: () => openContact(context, whatsappUri(phone, message)),
            icon: const Icon(Icons.chat_outlined),
            label: const Text('WhatsApp'),
          ),
        ),
      ],
    );
  }
}

/// Pide al servidor el mensaje armado (y registrado) y abre WhatsApp con él.
/// Devuelve true si se pudo abrir.
Future<bool> sendWhatsapp(BuildContext context, ApiClient api, Map<String, Object?> body) async {
  try {
    final data = await api.post('/messages/whatsapp', body) as Map<String, dynamic>;
    if (!context.mounted) return false;
    await openContact(context, Uri.parse(data['url'] as String));
    return true;
  } catch (e) {
    if (context.mounted) showMessage(context, errorText(e), error: true);
    return false;
  }
}
