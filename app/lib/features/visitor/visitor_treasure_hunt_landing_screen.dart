import 'package:flutter/material.dart';

import '../../data/models/event_map_data.dart';
import '../../data/models/treasure_hunt.dart';
import 'visitor_treasure_hunt_screen.dart';

/// Landingsside for en skattejagt der deles som selvstændig hjemmeside.
class VisitorTreasureHuntLandingScreen extends StatelessWidget {
  const VisitorTreasureHuntLandingScreen({
    super.key,
    required this.mapData,
    required this.hunt,
  });

  final EventMapData mapData;
  final TreasureHuntConfig hunt;

  void _start(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => VisitorTreasureHuntScreen(
          mapData: mapData,
          hunt: hunt,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final postCount = hunt.orderedPosts.length;
    final cover = hunt.coverImage;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (cover != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: AspectRatio(
                          aspectRatio: 16 / 10,
                          child: Image.network(
                            cover.url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Center(
                                child: Icon(Icons.image_not_supported_outlined),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ] else ...[
                      Container(
                        height: 160,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            colors: [
                              theme.colorScheme.primary.withValues(alpha: 0.85),
                              theme.colorScheme.tertiary.withValues(alpha: 0.75),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.flag,
                            size: 64,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    Text(
                      hunt.landingHeadline,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      postCount == 0
                          ? 'Skattejagten er ikke klar endnu.'
                          : '$postCount post${postCount == 1 ? '' : 'er'} venter på dig',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: FilledButton(
                onPressed: postCount == 0 ? null : () => _start(context),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Start skattejagt'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
