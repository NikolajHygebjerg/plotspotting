import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/constants.dart';
import '../../core/network/error_message.dart';
import '../../core/storage/organizer_session_persistence.dart';
import '../../data/models/event_map_data.dart';
import '../../data/models/publish_status.dart';
import '../../data/repositories/event_repository.dart';

class PublishScreen extends StatefulWidget {
  const PublishScreen({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.mapData,
  });

  final String eventId;
  final String eventName;
  final EventMapData mapData;

  @override
  State<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<PublishScreen> {
  final _repository = EventRepository();
  bool _publishing = false;
  bool _loadingStatus = true;
  String? _slug;
  String? _error;
  PublishStatus? _publishStatus;

  bool get _mapReady =>
      widget.mapData.edges.isNotEmpty && widget.mapData.vertices.isNotEmpty;

  bool get _standaloneHuntReady =>
      widget.mapData.treasureHuntCatalog.hasStandaloneHunt && _mapReady;

  bool get _contentReady => _mapReady || _standaloneHuntReady;

  bool get _canPublish =>
      _contentReady && (_publishStatus?.allowed ?? false);

  @override
  void initState() {
    super.initState();
    _loadPublishStatus();
  }

  Future<void> _loadPublishStatus() async {
    try {
      final status = await _repository.getPublishStatus(
        eventId: widget.eventId,
      );
      if (!mounted) return;
      setState(() {
        _publishStatus = status;
        _loadingStatus = false;
        if (status.alreadyPublished && widget.mapData.event.publicSlug != null) {
          _slug = widget.mapData.event.publicSlug;
        }
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingStatus = false;
        _error = friendlyApiError(error);
      });
    }
  }

  Future<void> _publish() async {
    if (!_canPublish) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_publishStatus?.message ?? 'Kan ikke publicere endnu')),
      );
      return;
    }

    setState(() {
      _publishing = true;
      _error = null;
    });

    try {
      final slug = await _repository.publishEvent(
        eventId: widget.eventId,
      );
      await persistOrganizerSession(
        eventId: widget.eventId,
        eventName: widget.eventName,
        publicSlug: slug,
      );
      if (!mounted) return;
      setState(() => _slug = slug);
    } catch (error) {
      setState(() => _error = friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  String get _publicUrl =>
      AppConstants.publicEventUrl(_slug ?? '');

  String get _embedUrl =>
      AppConstants.publicEventUrl(_slug ?? '', embed: true);

  String get _embedSnippet =>
      AppConstants.embedIframeSnippet(_slug ?? '');

  @override
  Widget build(BuildContext context) {
    final status = _publishStatus;

    return Scaffold(
      appBar: AppBar(title: const Text('Publicér & del')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.eventName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (_loadingStatus)
              const LinearProgressIndicator()
            else if (!_contentReady)
              Text(
                'Tegn officielle stier under Ruter — skattejagten bruger dem til navigation. Tilføj evt. jagt-specifikke stier under Skattejagt.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else if (status != null && !status.allowed)
              _PublishGateCard(status: status)
            else
              Text(
                status?.message ?? 'Kortet er klar til deling med besøgende.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            const SizedBox(height: 24),
            if (_slug != null) ...[
              Center(
                child: QrImageView(
                  data: _publicUrl,
                  size: 180,
                ),
              ),
              const SizedBox(height: 16),
              SelectableText(_publicUrl, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Text(
                'Indlejr på hjemmeside',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Kopiér linket eller iframe-koden til kundens website.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              SelectableText(_embedUrl, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              SelectableText(
                _embedSnippet,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.pop(context, _slug),
                child: const Text('Færdig'),
              ),
            ] else ...[
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              FilledButton(
                onPressed: _publishing || !_canPublish ? null : _publish,
                child: _publishing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(status?.alreadyPublished == true ? 'Opdater publicering' : 'Publicér kort'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PublishGateCard extends StatelessWidget {
  const _PublishGateCard({required this.status});

  final PublishStatus status;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Text(
                  'Udgivelse låst',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(status.message),
            if (status.organizationName != null) ...[
              const SizedBox(height: 8),
              Text(
                'Workspace: ${status.organizationName} · plan: ${status.plan ?? 'free'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Du kan stadig redigere kortet som kladde. Betalingsflow kommer senere.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
