import 'package:flutter/material.dart';

import '../../data/repositories/event_repository.dart';
import '../../data/models/event_map_data.dart';
import 'visitor_experience.dart';
import 'visitor_map_screen.dart';
import 'visitor_treasure_hunt_landing_screen.dart';
import 'visitor_treasure_hunt_screen.dart';

class OpenPublishedEventScreen extends StatefulWidget {
  const OpenPublishedEventScreen({
    super.key,
    required this.slug,
    this.initialSearch,
    this.treasureHuntSlug,
    this.embed = false,
  });

  final String slug;
  final String? initialSearch;
  final String? treasureHuntSlug;
  final bool embed;

  @override
  State<OpenPublishedEventScreen> createState() => _OpenPublishedEventScreenState();
}

class _OpenPublishedEventScreenState extends State<OpenPublishedEventScreen> {
  final _repository = EventRepository();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _repository.loadPublishedBySlug(widget.slug);
      if (!mounted) return;
      if (data == null) {
        throw Exception('Kortet "${widget.slug}" findes ikke eller er ikke publiceret');
      }

      final huntSlug = widget.treasureHuntSlug?.trim();
      if (huntSlug != null && huntSlug.isNotEmpty) {
        final hunt = data.treasureHuntCatalog.huntByStandaloneSlug(huntSlug);
        if (hunt == null || !hunt.isStandaloneReady) {
          throw Exception('Skattejagten "$huntSlug" findes ikke eller er ikke klar');
        }
        if (!mounted) return;
        if (widget.embed) {
          await Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => VisitorTreasureHuntScreen(
                mapData: data,
                hunt: hunt,
                embed: true,
              ),
            ),
          );
          return;
        }
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => VisitorTreasureHuntLandingScreen(
              mapData: data,
              hunt: hunt,
            ),
          ),
        );
        return;
      }

      final searchQuery = widget.initialSearch?.trim();
      if (searchQuery != null && searchQuery.isNotEmpty) {
        await _openMap(context, data, VisitorExperience.search, searchQuery);
        return;
      }

      if (widget.embed) {
        final experience = defaultExperience(data);
        await _openMap(context, data, experience);
        return;
      }

      final options = availableExperiences(data);
      if (options.isEmpty) {
        await _openMap(context, data, VisitorExperience.search);
        return;
      }

      await _openMap(
        context,
        data,
        options.contains(VisitorExperience.explore)
            ? VisitorExperience.explore
            : options.first,
      );
      return;
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Kunne ikke åbne kort'),
          content: Text('$error'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted && !widget.embed) Navigator.pop(context);
    }
  }

  Future<void> _openMap(
    BuildContext context,
    EventMapData data,
    VisitorExperience experience, [
    String? initialSearch,
  ]) async {
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => VisitorMapScreen(
          mapData: data,
          experience: experience,
          initialSearch: initialSearch,
          embed: widget.embed,
        ),
      ),
    );
  }

  String get slug => widget.slug;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embed ? null : AppBar(title: Text(widget.slug)),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}
