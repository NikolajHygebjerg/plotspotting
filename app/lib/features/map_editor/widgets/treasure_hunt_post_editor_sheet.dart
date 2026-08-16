import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/treasure_hunt.dart';
import '../../../data/repositories/event_repository.dart';
import 'poi_media_editor.dart';

enum TreasureHuntPostEditorAction {
  cancel,
  save,
  delete,
  movePin,
}

class TreasureHuntPostEditorResult {
  const TreasureHuntPostEditorResult({
    required this.action,
    this.post,
  });

  final TreasureHuntPostEditorAction action;
  final TreasureHuntPost? post;
}

class TreasureHuntPostEditorSheet extends StatefulWidget {
  const TreasureHuntPostEditorSheet({
    super.key,
    required this.eventId,
    required this.repository,
    required this.existing,
    required this.lat,
    required this.lng,
    required this.isNew,
    required this.otherPosts,
    required this.sortOrder,
  });

  final String eventId;
  final EventRepository repository;
  final TreasureHuntPost? existing;
  final double lat;
  final double lng;
  final bool isNew;
  final List<TreasureHuntPost> otherPosts;
  final int sortOrder;

  static Future<TreasureHuntPostEditorResult?> show(
    BuildContext context, {
    required String eventId,
    required EventRepository repository,
    required TreasureHuntPost? existing,
    required double lat,
    required double lng,
    required bool isNew,
    required List<TreasureHuntPost> otherPosts,
    required int sortOrder,
  }) {
    return showModalBottomSheet<TreasureHuntPostEditorResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: TreasureHuntPostEditorSheet(
            eventId: eventId,
            repository: repository,
            existing: existing,
            lat: lat,
            lng: lng,
            isNew: isNew,
            otherPosts: otherPosts,
            sortOrder: sortOrder,
          ),
        );
      },
    );
  }

  @override
  State<TreasureHuntPostEditorSheet> createState() =>
      _TreasureHuntPostEditorSheetState();
}

class _TreasureHuntPostEditorSheetState
    extends State<TreasureHuntPostEditorSheet> {
  static const _uuid = Uuid();

  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final PoiMediaEditorController _mediaController;
  late final String _postId;
  String? _nextPostId;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _postId = existing?.id ?? _uuid.v4();
    _titleController = TextEditingController(text: existing?.title ?? '');
    _bodyController = TextEditingController(text: existing?.bodyText ?? '');
    _mediaController = PoiMediaEditorController(existing?.media ?? const []);
    _nextPostId = existing?.nextPostId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  TreasureHuntPost _buildPost() {
    final title = _titleController.text.trim();
    return TreasureHuntPost(
      id: _postId,
      lat: widget.lat,
      lng: widget.lng,
      title: title.isEmpty ? 'Post' : title,
      bodyText: _bodyController.text.trim().isEmpty
          ? null
          : _bodyController.text.trim(),
      media: _mediaController.media,
      nextPostId: _nextPostId,
      sortOrder: widget.sortOrder,
    );
  }

  void _pop(TreasureHuntPostEditorAction action, {TreasureHuntPost? post}) {
    Navigator.pop(
      context,
      TreasureHuntPostEditorResult(action: action, post: post),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Material(
          color: theme.colorScheme.surface,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.isNew ? 'Ny post' : 'Rediger post',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Luk',
                      onPressed: () => _pop(TreasureHuntPostEditorAction.cancel),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Postnavn',
                        hintText: 'Fx «Post 1 — bronzen»',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _bodyController,
                      decoration: const InputDecoration(
                        labelText: 'Brødtekst',
                        hintText: 'Besked som vises når posten åbnes',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      minLines: 4,
                      maxLines: 8,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 20),
                    Text('Medier', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      'Upload billeder, video og lydfiler til posten',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    PoiMediaEditor(
                      eventId: widget.eventId,
                      poiId: _postId,
                      repository: widget.repository,
                      controller: _mediaController,
                    ),
                    const SizedBox(height: 20),
                    Text('Næste post', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      'Vælg hvilken post deltagerne guides hen til bagefter. Du kan vælge senere.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      initialValue: _nextPostId,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Næste post',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Vælg senere'),
                        ),
                        for (final post in widget.otherPosts)
                          DropdownMenuItem<String?>(
                            value: post.id,
                            child: Text(post.displayTitle),
                          ),
                      ],
                      onChanged: (value) => setState(() => _nextPostId = value),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!widget.isNew) ...[
                        OutlinedButton.icon(
                          onPressed: () =>
                              _pop(TreasureHuntPostEditorAction.movePin),
                          icon: const Icon(Icons.open_with),
                          label: const Text('Flyt post på kortet'),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        children: [
                          if (!widget.isNew)
                            TextButton(
                              onPressed: () => _pop(
                                TreasureHuntPostEditorAction.delete,
                              ),
                              child: Text(
                                'Slet',
                                style: TextStyle(color: theme.colorScheme.error),
                              ),
                            ),
                          const Spacer(),
                          TextButton(
                            onPressed: () =>
                                _pop(TreasureHuntPostEditorAction.cancel),
                            child: const Text('Annuller'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () => _pop(
                              TreasureHuntPostEditorAction.save,
                              post: _buildPost(),
                            ),
                            child: const Text('Gem post'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
