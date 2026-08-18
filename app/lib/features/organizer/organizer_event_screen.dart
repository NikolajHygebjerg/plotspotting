import 'package:flutter/material.dart';

import '../../data/models/event_map_data.dart';
import '../map_editor/map_editor_screen.dart';
import '../map_editor/mapping_method.dart';
import 'organizer_guest_preview.dart';
import 'organizer_shell.dart';

/// Arrangør-shell: gæstvisning først, redigering via bundmenuen.
class OrganizerEventScreen extends StatefulWidget {
  const OrganizerEventScreen({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.initialData,
  });

  final String eventId;
  final String eventName;
  final EventMapData initialData;

  @override
  State<OrganizerEventScreen> createState() => _OrganizerEventScreenState();
}

class _OrganizerEventScreenState extends State<OrganizerEventScreen> {
  final _editorKey = GlobalKey<MapEditorScreenState>();

  late EventMapData _data;
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData;
  }

  bool get _isGuestView => _navIndex == 0;

  EditorSection? get _editorSection => editorSectionFromNavIndex(_navIndex);

  String get _appBarTitle => _data.event.name;

  void _syncGuestDataFromEditor() {
    final editorData = _editorKey.currentState?.mapData;
    if (editorData != null) {
      setState(() => _data = editorData);
    }
  }

  void _onDataChanged(EventMapData data) {
    setState(() => _data = data);
  }

  Future<void> _openAudioTourEditor() async {
    _syncGuestDataFromEditor();
    final editor = _editorKey.currentState;
    if (editor == null) return;
    await editor.openAudioTourEditor();
    _syncGuestDataFromEditor();
  }

  Future<void> _openTreasureHuntEditor() async {
    _syncGuestDataFromEditor();
    final editor = _editorKey.currentState;
    if (editor == null) return;
    await editor.openTreasureHuntEditor();
    _syncGuestDataFromEditor();
  }

  void _onNavSelected(int index) {
    if (index == 0) {
      _syncGuestDataFromEditor();
      setState(() => _navIndex = 0);
      return;
    }
    if (index == 4) {
      _openAudioTourEditor();
      return;
    }
    if (index == 5) {
      _openTreasureHuntEditor();
      return;
    }
    setState(() => _navIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OrganizerShellAppBar(title: _appBarTitle),
      body: IndexedStack(
        index: _isGuestView ? 0 : 1,
        children: [
          OrganizerGuestPreview(data: _data),
          MapEditorScreen(
            key: _editorKey,
            eventId: widget.eventId,
            eventName: widget.eventName,
            initialData: _data,
            embedded: true,
            section: _editorSection ?? EditorSection.routes,
            onSectionChanged: (section) {
              setState(() => _navIndex = organizerNavIndexForSection(section));
            },
            onDataChanged: _onDataChanged,
          ),
        ],
      ),
      bottomNavigationBar: OrganizerBottomNav(
        selectedIndex: _navIndex,
        onDestinationSelected: _onNavSelected,
      ),
    );
  }
}
