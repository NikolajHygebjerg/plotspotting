import 'package:supabase_flutter/supabase_flutter.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    this.displayName,
    this.email,
  });

  final String id;
  final String? displayName;
  final String? email;

  String get label => displayName?.trim().isNotEmpty == true
      ? displayName!.trim()
      : email ?? 'Bruger';
}

class AuthRepository {
  AuthRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  bool get isSignedIn => currentUser != null;

  UserProfile? get currentProfile {
    final user = currentUser;
    if (user == null) return null;
    return UserProfile(
      id: user.id,
      email: user.email,
      displayName: user.userMetadata?['display_name'] as String?,
    );
  }

  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    await _client.auth.signUp(
      email: email,
      password: password,
      data: {
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
      },
    );
    await bootstrapAccount(displayName: displayName);
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    await bootstrapAccount(
      displayName: currentUser?.userMetadata?['display_name'] as String?,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<void> updateDisplayName(String displayName) async {
    final user = currentUser;
    if (user == null) throw StateError('not_authenticated');

    final trimmed = displayName.trim();
    await _client.auth.updateUser(
      UserAttributes(data: {'display_name': trimmed}),
    );
    await _client.from('profiles').update({'display_name': trimmed}).eq('id', user.id);
  }

  Future<void> updateEmail(String email) async {
    await _client.auth.updateUser(UserAttributes(email: email.trim()));
  }

  Future<void> updatePassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  Future<void> deleteAccount() async {
    await _client.rpc('delete_my_account');
    await signOut();
  }

  Future<void> bootstrapAccount({String? displayName}) async {
    if (!isSignedIn) return;
    await _client.rpc(
      'bootstrap_user_account',
      params: {'p_display_name': displayName},
    );
  }
}
