import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/routing/poi_connection.dart';
import '../../../data/models/map_edge.dart';
import '../../../data/models/map_poi.dart';
import '../../../data/models/map_vertex.dart';
import '../poi_path_connection.dart';

class PoiConnectionsPanel extends StatelessWidget {
  const PoiConnectionsPanel({
    super.key,
    required this.pois,
    required this.vertices,
    required this.edges,
    required this.selectedPoiId,
    required this.onConnectAll,
    required this.onPoiSelected,
    required this.onConnectPoi,
    required this.onMoveConnection,
    required this.onRemoveConnection,
  });

  final List<MapPoi> pois;
  final List<MapVertex> vertices;
  final List<MapEdge> edges;
  final String? selectedPoiId;
  final VoidCallback onConnectAll;
  final ValueChanged<MapPoi> onPoiSelected;
  final ValueChanged<MapPoi> onConnectPoi;
  final ValueChanged<MapPoi> onMoveConnection;
  final ValueChanged<MapPoi> onRemoveConnection;

  int get _connectedCount => pois.where((poi) {
        return poiHasActiveConnection(
          poi: poi,
          vertices: vertices,
          edges: edges,
        );
      }).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxDistance = AppConstants.poiPathAccessMaxMeters.toInt();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Alle steder',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: onConnectAll,
                  icon: const Icon(Icons.route_outlined),
                  label: const Text('Kobl alle'),
                ),
              ],
            ),
            Text(
              '$_connectedCount af ${pois.length} steder koblet til sti '
              '(max $maxDistance m)',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: pois.isEmpty
                  ? Center(
                      child: Text(
                        'Der er ingen steder endnu',
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  : ListView.separated(
                      itemCount: pois.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final poi = pois[index];
                        final hasConnection = poiHasActiveConnection(
                          poi: poi,
                          vertices: vertices,
                          edges: edges,
                        );
                        final isBroken = poiConnectionIsBroken(
                          poi: poi,
                          vertices: vertices,
                          edges: edges,
                        );
                        final selected = poi.id == selectedPoiId;
                        final status = isBroken
                            ? 'Kobling mangler'
                            : hasConnection
                                ? 'Koblet'
                                : 'Ikke koblet';

                        return Material(
                          color: selected
                              ? theme.colorScheme.primaryContainer
                                  .withValues(alpha: 0.35)
                              : null,
                          child: ListTile(
                            dense: true,
                            title: Text(
                              poi.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(status),
                            trailing: isBroken || !hasConnection
                                ? TextButton(
                                    onPressed: () => onConnectPoi(poi),
                                    child: const Text('Kobl'),
                                  )
                                : PopupMenuButton<String>(
                                    onSelected: (value) {
                                      switch (value) {
                                        case 'move':
                                          onMoveConnection(poi);
                                        case 'remove':
                                          onRemoveConnection(poi);
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'move',
                                        child: Text('Flyt kobling'),
                                      ),
                                      PopupMenuItem(
                                        value: 'remove',
                                        child: Text('Fjern kobling'),
                                      ),
                                    ],
                                  ),
                            onTap: () => onPoiSelected(poi),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
