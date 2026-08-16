import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/constants.dart';
import '../../core/network/error_message.dart';
import '../../core/storage/organizer_session_persistence.dart';
import '../../data/repositories/event_repository.dart';
import '../map_setup/map_setup_flow.dart';

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key, required this.organizationId});

  final String organizationId;

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _nameController = TextEditingController(text: 'Friland');
  final _descriptionController = TextEditingController(
    text: 'Økosamfund — gæsteguide til huse og stier',
  );
  final _repository = EventRepository();
  bool _creating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<({double lat, double lng})> _resolveCenter() async {
    try {
      if (await Geolocator.isLocationServiceEnabled()) {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              timeLimit: Duration(seconds: 8),
            ),
          );
          return (lat: position.latitude, lng: position.longitude);
        }
      }
    } on Object {
      // GPS must never block event creation.
    }
    return (
      lat: AppConstants.frilandCenterLat,
      lng: AppConstants.frilandCenterLng,
    );
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Angiv et event-navn')),
      );
      return;
    }

    setState(() => _creating = true);
    try {
      final (:lat, :lng) = await _resolveCenter();

      final eventId = await _repository.createOutdoorEvent(
        name: name,
        organizationId: widget.organizationId,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        centerLat: lat,
        centerLng: lng,
      );

      await persistOrganizerSession(
        eventId: eventId,
        eventName: name,
      );

      if (!mounted) return;
      await MapSetupFlow.startAreaSetup(
        context,
        eventId: eventId,
        eventName: name,
        initialCenter: ll.LatLng(lat, lng),
        replace: true,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nyt kort')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Event-navn',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Beskrivelse (valgfri)',
                border: OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            const Chip(label: Text('Udendørs · GPS + OSM')),
            const Spacer(),
            FilledButton(
              onPressed: _creating ? null : _create,
              child: _creating
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Opret og vælg område'),
            ),
          ],
        ),
      ),
    );
  }
}
