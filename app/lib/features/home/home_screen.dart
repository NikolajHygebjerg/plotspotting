import 'package:flutter/material.dart';

import '../../core/storage/session_storage.dart';
import '../../core/branding/app_branding.dart';
import '../../data/models/organization.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/event_repository.dart';
import '../../data/repositories/organization_repository.dart';
import '../account/user_account_screen.dart';
import '../create_event/create_event_screen.dart';
import '../map_setup/map_setup_flow.dart';
import '../visitor/open_published_event_screen.dart';
import '../../core/storage/organizer_session_persistence.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repository = EventRepository();
  final _orgRepository = OrganizationRepository();
  final _auth = AuthRepository();
  final _storage = SessionStorage();

  List<OrganizationEventSummary> _orgEvents = const [];
  String? _selectedOrgId;
  String? _orgError;
  bool _loading = true;
  String? _openingEventId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      await _auth.bootstrapAccount(displayName: _auth.currentProfile?.displayName);
      final orgs = await _orgRepository.listMyOrganizations();
      final savedOrgId = await _storage.loadSelectedOrganizationId();
      final selected = orgs.any((org) => org.id == savedOrgId)
          ? savedOrgId
          : (orgs.isNotEmpty ? orgs.first.id : null);

      if (selected != null) {
        await _storage.saveSelectedOrganizationId(selected);
      }

      if (mounted) {
        setState(() {
          _selectedOrgId = selected;
          _orgError = orgs.isEmpty
              ? 'Opret et workspace under bruger-menuen (øverst til højre)'
              : null;
        });
      }
      if (selected != null) {
        await _loadOrgEvents();
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _orgError = 'Kunne ikke hente workspaces: $error';
        });
      }
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadOrgEvents() async {
    final orgId = _selectedOrgId;
    if (orgId == null) return;
    final events = await _orgRepository.listEvents(orgId);
    if (mounted) setState(() => _orgEvents = events);
  }

  Future<void> _openOrgEvent(OrganizationEventSummary event) async {
    if (_openingEventId != null) return;

    setState(() => _openingEventId = event.id);
    try {
      final data = await _repository.loadForEdit(eventId: event.id);
      await persistOrganizerSession(
        eventId: event.id,
        eventName: data.event.name,
        publicSlug: data.event.publicSlug,
      );
      if (!mounted) return;
      await MapSetupFlow.openOrganizerPreview(
        context,
        eventId: event.id,
        eventName: data.event.name,
        data: data,
      );
      await _bootstrap();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _openingEventId = null);
    }
  }

  Future<void> _openPublishedEvent(String slug) async {
    final normalized = slug.trim().toLowerCase();
    if (normalized.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OpenPublishedEventScreen(slug: normalized),
      ),
    );
  }

  Future<void> _deleteOrgEvent(OrganizationEventSummary event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Slet kort?'),
        content: Text('«${event.name}» slettes permanent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuller')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Slet'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _repository.deleteEvent(eventId: event.id);
      await _storage.removeSession(event.id);
      await _bootstrap();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke slette: $error')),
      );
    }
  }

  Widget _visitorIconButton(String slug) {
    return IconButton(
      tooltip: 'Se som besøgende',
      icon: const Icon(Icons.visibility_outlined),
      onPressed: () => _openPublishedEvent(slug),
    );
  }

  Future<void> _openAccount() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const UserAccountScreen()),
    );
    await _bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Image.asset(
          AppBranding.logoAsset,
          height: 36,
          fit: BoxFit.contain,
        ),
        actions: [
          IconButton(
            tooltip: 'Bruger',
            onPressed: _openAccount,
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_orgError != null) ...[
                  Text(
                    _orgError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 16),
                ],
                FilledButton.icon(
                  onPressed: _selectedOrgId == null
                      ? null
                      : () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CreateEventScreen(
                                organizationId: _selectedOrgId!,
                              ),
                            ),
                          );
                          await _bootstrap();
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('Nyt kort'),
                ),
                const SizedBox(height: 24),
                Text('Dine kort', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (_orgEvents.isEmpty)
                  const Text('Ingen kort endnu')
                else
                  ..._orgEvents.map(
                    (event) {
                      final opening = _openingEventId == event.id;
                      return Card(
                        child: ListTile(
                          enabled: _openingEventId == null,
                          title: Text(event.name),
                          subtitle: Text(
                            event.isPublished
                                ? 'Publiceret · ${event.publicSlug}'
                                : 'Kladde',
                          ),
                          trailing: opening
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (event.isPublished && event.publicSlug != null)
                                      _visitorIconButton(event.publicSlug!),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete_outline,
                                        color: Theme.of(context).colorScheme.error,
                                      ),
                                      onPressed: () => _deleteOrgEvent(event),
                                    ),
                                  ],
                                ),
                          onTap: opening ? null : () => _openOrgEvent(event),
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}
