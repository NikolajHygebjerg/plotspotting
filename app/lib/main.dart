import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/branding/app_branding.dart';
import 'core/config/supabase_config.dart';
import 'core/deep_link/deep_link_service.dart';
import 'features/auth/auth_gate.dart';
import 'features/visitor/open_published_event_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseConfig.load();

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey, // ignore: deprecated_member_use
    );
  }

  runApp(const PlotspottingApp());
}

class PlotspottingApp extends StatefulWidget {
  const PlotspottingApp({super.key});

  @override
  State<PlotspottingApp> createState() => _PlotspottingAppState();
}

class _PlotspottingAppState extends State<PlotspottingApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _deepLinks = DeepLinkService();
  DeepLinkRequest? _initialWebLink;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _initialWebLink = _deepLinks.parseUri(Uri.base);
    }
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    if (kIsWeb && _initialWebLink != null) {
      _deepLinks.linkStream.listen(_openDeepLink);
      return;
    }

    final initial = await _deepLinks.getInitialLink();
    if (initial != null) {
      _openDeepLink(initial);
    }
    _deepLinks.linkStream.listen(_openDeepLink);
  }

  void _openDeepLink(DeepLinkRequest link) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => OpenPublishedEventScreen(
            slug: link.slug,
            initialSearch: link.searchQuery,
            treasureHuntSlug: link.treasureHuntSlug,
            embed: link.embed,
          ),
        ),
      );
    });
  }

  Widget _homeScreen() {
    if (!SupabaseConfig.isConfigured) {
      return const _MissingConfigScreen();
    }

    final link = _initialWebLink;
    if (link != null) {
      return OpenPublishedEventScreen(
        slug: link.slug,
        initialSearch: link.searchQuery,
        treasureHuntSlug: link.treasureHuntSlug,
        embed: link.embed,
      );
    }

    return const AuthGate();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: AppBranding.name,
      theme: AppBranding.theme(),
      home: _homeScreen(),
    );
  }
}

class _MissingConfigScreen extends StatelessWidget {
  const _MissingConfigScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppBranding.name)),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Supabase er ikke konfigureret.\n\n'
          '1. Kopiér assets/env.json.example til assets/env.json\n'
          '2. Indsæt Project URL + anon key fra Supabase → Settings → API\n'
          '3. Kør flutter run igen',
        ),
      ),
    );
  }
}
