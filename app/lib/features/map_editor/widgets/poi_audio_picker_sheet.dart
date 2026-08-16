import 'package:flutter/material.dart';

import '../../../data/models/map_poi.dart';
import '../../../data/models/poi_media.dart';

Future<PoiMedia?> pickPoiAudioClip(BuildContext context, MapPoi poi) async {
  final clips = poi.audioClips;
  if (clips.isEmpty) return null;
  if (clips.length == 1) return clips.first;

  return showModalBottomSheet<PoiMedia>(
    context: context,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Vælg lydfil',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: clips.length,
                itemBuilder: (context, index) {
                  final clip = clips[index];
                  return ListTile(
                    leading: const Icon(Icons.audiotrack),
                    title: Text(poi.audioLabel(clip)),
                    onTap: () => Navigator.pop(context, clip),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
