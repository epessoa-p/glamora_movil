import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../session.dart';
import '../util/format.dart';
import '../widgets/common.dart';

/// Fotos antes/después de un cliente: galería, subir desde la cámara o la
/// galería del celular, y ver en grande. Las fotos son privadas: se cargan
/// con el token de la sesión.
class ClientPhotosSection extends StatefulWidget {
  const ClientPhotosSection({super.key, required this.clientId});

  final int clientId;

  @override
  State<ClientPhotosSection> createState() => _ClientPhotosSectionState();
}

class _ClientPhotosSectionState extends State<ClientPhotosSection> {
  List<ClientPhotoInfo>? _photos;
  String? _error;
  bool _uploading = false;

  ApiClient get _api => context.read<Session>().api;
  Me get _me => context.read<Session>().me!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.get('/clients/${widget.clientId}/photos');
      if (mounted) setState(() => _photos = (data as List).whereType<Map<String, dynamic>>().map(ClientPhotoInfo.fromJson).toList());
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _add() async {
    final choice = await showModalBottomSheet<(ImageSource, String)>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _AddPhotoSheet(),
    );
    if (choice == null || !mounted) return;
    final (source, kind) = choice;

    final file = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
    if (file == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      await _api.upload('/clients/${widget.clientId}/photos',
          field: 'photo', bytes: await file.readAsBytes(), filename: file.name, fields: {'kind': kind});
      if (!mounted) return;
      showMessage(context, 'Foto guardada.');
      await _load();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _open(ClientPhotoInfo photo) async {
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PhotoViewer(photo: photo, headers: _api.imageHeaders, canDelete: _me.can('photos_delete'), api: _api)),
    );
    if (deleted == true && mounted) {
      showMessage(context, 'Foto eliminada.');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = _me.can('photos_create');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Fotos antes / después', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            if (canAdd)
              TextButton.icon(
                onPressed: _uploading ? null : _add,
                icon: _uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_a_photo_outlined),
                label: Text(_uploading ? 'Subiendo…' : 'Agregar'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (_error != null)
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
        else if (_photos == null)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
        else if (_photos!.isEmpty)
          Text('Sin fotos todavía.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
        else
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [
              for (final p in _photos!)
                GestureDetector(
                  key: ValueKey('photo-${p.id}'),
                  onTap: () => _open(p),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          p.thumbUrl,
                          headers: _api.imageHeaders,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(color: Colors.black12, child: const Icon(Icons.broken_image_outlined)),
                        ),
                      ),
                      Positioned(left: 4, top: 4, child: _KindChip(kind: p.kind, label: p.kindLabel)),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.kind, required this.label});

  final String kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = switch (kind) { 'before' => Colors.blueGrey, 'after' => Colors.green, _ => Colors.black54 };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: .85), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

/// Elegir de dónde sale la foto y si es de antes o después.
class _AddPhotoSheet extends StatefulWidget {
  const _AddPhotoSheet();

  @override
  State<_AddPhotoSheet> createState() => _AddPhotoSheetState();
}

class _AddPhotoSheetState extends State<_AddPhotoSheet> {
  String _kind = 'before';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Nueva foto', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'before', label: Text('Antes')),
                ButtonSegment(value: 'after', label: Text('Después')),
                ButtonSegment(value: 'other', label: Text('Otra')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, (ImageSource.camera, _kind)),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Tomar foto'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => Navigator.pop(context, (ImageSource.gallery, _kind)),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Elegir de la galería'),
            ),
            const SizedBox(height: 8),
            Text('Las fotos son privadas: solo las ve el personal del salón con permiso.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// Foto a pantalla completa con zoom. Devuelve true si se eliminó.
class PhotoViewer extends StatelessWidget {
  const PhotoViewer({super.key, required this.photo, required this.headers, required this.canDelete, required this.api});

  final ClientPhotoInfo photo;
  final Map<String, String> headers;
  final bool canDelete;
  final ApiClient api;

  Future<void> _delete(BuildContext context) async {
    final ok = await confirm(context, title: 'Eliminar foto', message: '¿Eliminar esta foto? No se puede deshacer.', ok: 'Eliminar');
    if (!ok || !context.mounted) return;
    try {
      await api.delete('/photos/${photo.id}');
      if (context.mounted) Navigator.pop(context, true);
    } catch (e) {
      if (context.mounted) showMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${photo.kindLabel} · ${shortDay(photo.takenOn)}', style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          if (canDelete) IconButton(tooltip: 'Eliminar', onPressed: () => _delete(context), icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: Image.network(photo.url, headers: headers, fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64)),
              ),
            ),
          ),
          if (photo.service != null || photo.notes != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text([photo.service, photo.notes].whereType<String>().join(' · '), style: const TextStyle(color: Colors.white70)),
            ),
        ],
      ),
    );
  }
}
