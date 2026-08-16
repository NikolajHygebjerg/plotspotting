import 'package:flutter/material.dart';

import '../../core/network/error_message.dart';
import '../../core/storage/organizer_session_persistence.dart';
import '../../core/storage/session_storage.dart';
import '../../data/models/organization.dart';
import '../../core/branding/app_branding.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/event_repository.dart';
import '../../data/repositories/organization_repository.dart';
import '../create_event/create_event_screen.dart';
import '../map_setup/map_setup_flow.dart';
import '../visitor/open_published_event_screen.dart';

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

  List<OrganizerSession> _sessions = const [];
  List<Organization> _organizations = const [];
  List<OrganizationEventSummary> _orgEvents = const [];
  String? _selectedOrgId;
  String? _orgError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    final sessions = await _storage.loadSessions();
    try {
      await _auth.bootstrapAccount(displayName: _auth.currentProfile?.displayName);
      final orgs = await _orgRepository.listMyOrganizations();
      if (mounted) {
        setState(() {
          _organizations = orgs;
          _selectedOrgId = orgs.isNotEmpty ? orgs.first.id : null;
          _orgError = orgs.isEmpty
              ? 'Intet workspace endnu — tryk + for at oprette et'
              : null;
        });
      }
      if (_selectedOrgId != null) {
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
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    }
  }

  Future<void> _loadOrgEvents() async {
    final orgId = _selectedOrgId;
    if (orgId == null) return;
    final events = await _orgRepository.listEvents(orgId);
    if (mounted) setState(() => _orgEvents = events);
  }

  Future<void> _openOrgEvent(OrganizationEventSummary event) async {
    try {
      final data = await _repository.loadForEdit(eventId: event.id);
      await persistOrganizerSession(
        eventId: event.id,
        eventName: data.event.name,
        publicSlug: data.event.publicSlug,
      );
      if (!mounted) return;
      await MapSetupFlow.openEditorOrSetup(
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

  Future<void> _createOrganization() async {
    final controller = TextEditingController();
    var kind = OrganizationKind.customer;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Nyt workspace'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Navn',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<OrganizationKind>(
                  initialValue: kind,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: OrganizationKind.customer,
                      child: Text('Kunde / self-service'),
                    ),
                    DropdownMenuItem(
                      value: OrganizationKind.agency,
                      child: Text('Bureau'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => kind = value);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuller')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Opret')),
            ],
          );
        },
      ),
    );

    if (created != true || controller.text.trim().isEmpty || !mounted) return;

    try {
      await _orgRepository.createOrganization(
        name: controller.text.trim(),
        kind: kind,
      );
      await _bootstrap();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  Future<void> _openSession(OrganizerSession session) async {
    try {
      final data = await _repository.loadForEdit(eventId: session.eventId);
      await persistOrganizerSession(
        eventId: session.eventId,
        eventName: data.event.name,
        publicSlug: data.event.publicSlug ?? session.publicSlug,
      );
      if (!mounted) return;
      await MapSetupFlow.openEditorOrSetup(
        context,
        eventId: session.eventId,
        eventName: data.event.name,
        data: data,
      );
      await _bootstrap();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
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

  Future<void> _removeSession(OrganizerSession session) async {
    await _storage.removeSession(session.eventId);
    await _bootstrap();
  }

  bool _isInCurrentWorkspace(String eventId) {
    return _orgEvents.any((event) => event.id == eventId);
  }

  String? _publishedSlugForSession(OrganizerSession session) {
    for (final event in _orgEvents) {
      if (event.id == session.eventId && event.isPublished && event.publicSlug != null) {
        return event.publicSlug;
      }
    }
    final slug = session.publicSlug?.trim();
    if (slug != null && slug.isNotEmpty) return slug;
    return null;
  }

  Widget _visitorIconButton(String slug) {
    return IconButton(
      tooltip: 'Se som besøgende',
      icon: const Icon(Icons.visibility_outlined),
      onPressed: () => _openPublishedEvent(slug),
    );
  }

  Future<String?> _pickTargetOrganizationId() async {
    if (_organizations.isEmpty) return null;
    if (_organizations.length == 1) return _organizations.first.id;

    var selected = _selectedOrgId ?? _organizations.first.id;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Vælg workspace'),
            content: DropdownButtonFormField<String>(
              initialValue: selected,
              decoration: const InputDecoration(
                labelText: 'Workspace',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final org in _organizations)
                  DropdownMenuItem(value: org.id, child: Text(org.name)),
              ],
              onChanged: (value) {
                if (value != null) setDialogState(() => selected = value);
              },
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuller')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Flyt')),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return null;
    return selected;
  }

  Future<void> _moveSessionToWorkspace(OrganizerSession session) async {
    if (_isInCurrentWorkspace(session.eventId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kortet er allerede i dit workspace')),
      );
      return;
    }

    final orgId = await _pickTargetOrganizationId();
    if (orgId == null || !mounted) return;

    try {
      await _repository.assignEventToOrganization(
        eventId: session.eventId,
        organizationId: orgId,
      );
      if (!mounted) return;
      setState(() => _selectedOrgId = orgId);
      await _bootstrap();
      if (!mounted) return;
      final orgName = _organizations.firstWhere((org) => org.id == orgId).name;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('«${session.eventName}» er flyttet til $orgName')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _auth.currentProfile;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppBranding.name),
        actions: [
          IconButton(
            tooltip: 'Log ud',
            onPressed: () async {
              await _auth.signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (profile != null)
                  Text('Hej ${profile.label}', style: Theme.of(context).textTheme.titleMedium),
                if (_orgError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _orgError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedOrgId,
                        decoration: const InputDecoration(
                          labelText: 'Workspace',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final org in _organizations)
                            DropdownMenuItem(
                              value: org.id,
                              child: Text(org.name),
                            ),
                        ],
                        onChanged: (value) async {
                          setState(() => _selectedOrgId = value);
                          await _loadOrgEvents();
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Nyt workspace',
                      onPressed: _createOrganization,
                      icon: const Icon(Icons.add_business_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
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
                    (event) => Card(
                      child: ListTile(
                        title: Text(event.name),
                        subtitle: Text(event.isPublished ? 'Publiceret · ${event.publicSlug}' : 'Kladde'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (event.isPublished && event.publicSlug != null)
                              _visitorIconButton(event.publicSlug!),
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                              onPressed: () => _deleteOrgEvent(event),
                            ),
                          ],
                        ),
                        onTap: () => _openOrgEvent(event),
                      ),
                    ),
                  ),
                if (_sessions.isNotEmpty) ...[
                  const Divider(height: 40),
                  Text('Seneste', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Lokale genveje — kort uden workspace kan flyttes op.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  ..._sessions.map(
                    (session) {
                      final inWorkspace = _isInCurrentWorkspace(session.eventId);
                      return Card(
                        child: ListTile(
                          title: Text(session.eventName),
                          subtitle: Text(
                            inWorkspace
                                ? (session.publicSlug ?? 'I workspace')
                                : 'Ikke i workspace · ${session.publicSlug ?? session.eventId}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_publishedSlugForSession(session) case final slug?)
                                _visitorIconButton(slug),
                              if (!inWorkspace)
                                IconButton(
                                  tooltip: 'Flyt til workspace',
                                  icon: const Icon(Icons.drive_file_move_outline),
                                  onPressed: () => _moveSessionToWorkspace(session),
                                ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => _removeSession(session),
                              ),
                            ],
                          ),
                          onTap: () => _openSession(session),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
    );
  }
}
