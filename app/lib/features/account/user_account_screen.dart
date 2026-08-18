import 'package:flutter/material.dart';

import '../../core/network/error_message.dart';
import '../../core/storage/session_storage.dart';
import '../../data/models/organization.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/organization_repository.dart';

class UserAccountScreen extends StatefulWidget {
  const UserAccountScreen({super.key});

  @override
  State<UserAccountScreen> createState() => _UserAccountScreenState();
}

class _UserAccountScreenState extends State<UserAccountScreen> {
  final _auth = AuthRepository();
  final _orgRepository = OrganizationRepository();
  final _storage = SessionStorage();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();

  List<Organization> _organizations = const [];
  String? _selectedOrgId;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final orgs = await _orgRepository.listMyOrganizations();
      final savedOrgId = await _storage.loadSelectedOrganizationId();
      final selected = orgs.any((org) => org.id == savedOrgId)
          ? savedOrgId
          : (orgs.isNotEmpty ? orgs.first.id : null);

      if (selected != null) {
        await _storage.saveSelectedOrganizationId(selected);
      }

      final profile = _auth.currentProfile;
      if (mounted) {
        _nameController.text = profile?.displayName ?? '';
        _emailController.text = profile?.email ?? '';
        setState(() {
          _organizations = orgs;
          _selectedOrgId = selected;
          _loading = false;
        });
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    }
  }

  Future<void> _selectWorkspace(String orgId) async {
    await _storage.saveSelectedOrganizationId(orgId);
    if (!mounted) return;
    setState(() => _selectedOrgId = orgId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Workspace skiftet')),
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
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuller'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Opret'),
              ),
            ],
          );
        },
      ),
    );

    if (created != true || controller.text.trim().isEmpty || !mounted) return;

    try {
      final org = await _orgRepository.createOrganization(
        name: controller.text.trim(),
        kind: kind,
      );
      await _storage.saveSelectedOrganizationId(org.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Workspace «${org.name}» oprettet')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final passwordConfirm = _passwordConfirmController.text;

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-mail må ikke være tom')),
      );
      return;
    }

    if (password.isNotEmpty && password != passwordConfirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adgangskoderne matcher ikke')),
      );
      return;
    }

    if (password.isNotEmpty && password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adgangskode skal være mindst 6 tegn')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final profile = _auth.currentProfile;
      if (name != (profile?.displayName ?? '')) {
        await _auth.updateDisplayName(name);
      }
      if (email != (profile?.email ?? '')) {
        await _auth.updateEmail(email);
      }
      if (password.isNotEmpty) {
        await _auth.updatePassword(password);
      }

      if (!mounted) return;
      _passwordController.clear();
      _passwordConfirmController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            email != (profile?.email ?? '')
                ? 'Profil opdateret. Tjek e-mail for bekræftelse af ny adresse.'
                : 'Profil opdateret',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Slet bruger?'),
        content: const Text(
          'Din konto og adgang til workspaces slettes permanent. '
          'Kort i workspaces du ejer kan stadig findes af andre medlemmer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuller'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Slet bruger'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _auth.deleteAccount();
      await _storage.clearSelectedOrganizationId();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bruger')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Workspace', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (_organizations.isEmpty)
                  const Text('Du har ingen workspaces endnu.')
                else
                  ..._organizations.map(
                    (org) {
                      final selected = org.id == _selectedOrgId;
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          title: Text(org.name),
                          subtitle: Text(org.kind.label),
                          trailing: selected
                              ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                              : null,
                          selected: selected,
                          onTap: () => _selectWorkspace(org.id),
                        ),
                      );
                    },
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _createOrganization,
                    icon: const Icon(Icons.add_business_outlined),
                    label: const Text('Opret nyt workspace'),
                  ),
                ),
                const Divider(height: 40),
                Text('Profil', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Brugernavn',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Ny adgangskode',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordConfirmController,
                  decoration: const InputDecoration(
                    labelText: 'Gentag adgangskode',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _saveProfile,
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Gem ændringer'),
                ),
                const Divider(height: 40),
                OutlinedButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Log ud'),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _deleteAccount,
                  icon: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
                  label: Text(
                    'Slet bruger',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ],
            ),
    );
  }
}
