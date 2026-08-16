import 'package:flutter/material.dart';

import '../../data/models/map_bounds.dart';
import 'basemap_alignment_screen.dart';
import 'map_setup_flow.dart';
import 'map_setup_step_header.dart';

/// Guide til AI-tegnet kort + upload, georefereret til det valgte område.
class IllustratedMapSetupScreen extends StatefulWidget {
  const IllustratedMapSetupScreen({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.bounds,
  });

  final String eventId;
  final String eventName;
  final MapBounds bounds;

  @override
  State<IllustratedMapSetupScreen> createState() =>
      _IllustratedMapSetupScreenState();
}

class _IllustratedMapSetupScreenState extends State<IllustratedMapSetupScreen> {
  bool _uploading = false;

  Future<void> _upload() async {
    setState(() => _uploading = true);
    try {
      await pickAndAlignBasemap(
        context,
        eventId: widget.eventId,
        eventName: widget.eventName,
        bounds: widget.bounds,
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _skipForNow() {
    MapSetupFlow.openEditor(
      context,
      eventId: widget.eventId,
      eventName: widget.eventName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Illustreret kort'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const MapSetupStepHeader(currentStep: 2),
          const SizedBox(height: 24),
          Text(
            'Lav et tegnet kort til dit område',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Appen har gemt dit kortudsnit. Når du uploader et billede, '
            'lægger vi det præcist over det område — så GPS og navigation '
            'virker som på et almindeligt kort.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          _StepTile(
            number: 1,
            title: 'Tag et kortudsnit',
            body:
                'Zoom ind på det område du lige valgte (fx i Google Maps, '
                'Apple Maps eller OpenStreetMap) og tag et screenshot. '
                'Udsnittet skal matche det du valgte i appen.',
          ),
          _StepTile(
            number: 2,
            title: 'Få AI til at tegne kortet',
            body:
                'Upload screenshotet til Gemini (gemini.google.com) og bed om '
                'et håndtegnet kort i din stil — fx vandfarve set oppefra. '
                'Bed den om at beholde samme layout og proportioner.',
          ),
          _StepTile(
            number: 3,
            title: 'Upload og match manuelt',
            body:
                'Vælg billedet fra telefonen. Appen viser det halvgennemsigtigt '
                'over kortet — træk og skaler indtil tegningen matcher kortet nedenunder.',
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Eksempel-prompt til Gemini', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SelectableText(
                    'Tegn dette kort som et smukt håndtegnet vandfarve-kort set oppefra. '
                    'Behold præcis samme layout, vejforløb, bygninger og grønne områder. '
                    'Stil: blød akvarel, varme jordfarver. Samme proportioner som billedet.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _uploading ? null : _upload,
            icon: _uploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
            label: const Text('Vælg tegnet kort'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _uploading ? null : _skipForNow,
            child: const Text('Upload senere — gå til korttegning'),
          ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.number,
    required this.title,
    required this.body,
  });

  final int number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            child: Text('$number', style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
