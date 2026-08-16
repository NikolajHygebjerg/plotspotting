import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/branding/app_branding.dart';
import 'core/config/supabase_config.dart';
import 'core/deep_link/deep_link_service.dart';
import 'features/auth/auth_gate.dart';
import 'features/visitor/open_published_event_screen.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
    };

    await SupabaseConfig.load();

    if (SupabaseConfig.isConfigured) {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey, // ignore: deprecated_member_use
      );
    }

    runApp(const PlotspottingApp());
  }, (error, stack) {
    debugPrint('Uncaught app error: $error\n$stack');
  });
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
  StreamSubscription<DeepLinkRequest>? _deepLinkSub;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _initialWebLink = _deepLinks.parseUri(Uri.base);
    }
    _initDeepLinks();
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    super.dispose();
  }

  Future<void> _initDeepLinks() async {
    if (kIsWeb && _initialWebLink != null) {
      _deepLinkSub = _deepLinks.linkStream.listen(
        _openDeepLink,
        onError: (Object error, StackTrace stack) {
          debugPrint('Deep link stream error: $error\n$stack');
        },
      );
      return;
    }

    try {
      final initial = await _deepLinks.getInitialLink();
      if (initial != null) {
        _openDeepLink(initial);
      }
    } on Object catch (error, stack) {
      debugPrint('Initial deep link error: $error\n$stack');
    }

    _deepLinkSub = _deepLinks.linkStream.listen(
      _openDeepLink,
      onError: (Object error, StackTrace stack) {
        debugPrint('Deep link stream error: $error\n$stack');
      },
    );
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
