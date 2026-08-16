import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../data/models/treasure_hunt.dart';

/// Synlige, trykbare skattejagt-poster oven på kortet.
class TreasureHuntPostOverlay extends StatefulWidget {
  const TreasureHuntPostOverlay({
    super.key,
    required this.controller,
    required this.posts,
    required this.onPostTapped,
    this.selectedPostId,
  });

  final MapLibreMapController controller;
  final List<TreasureHuntPost> posts;
  final void Function(TreasureHuntPost post) onPostTapped;
  final String? selectedPostId;

  @override
  State<TreasureHuntPostOverlay> createState() =>
      TreasureHuntPostOverlayState();
}

class TreasureHuntPostOverlayState extends State<TreasureHuntPostOverlay> {
  Map<String, Offset> _positions = const {};
  var _updateToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => updatePositions());
  }

  @override
  void didUpdateWidget(covariant TreasureHuntPostOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.posts != widget.posts) {
      updatePositions();
      return;
    }
    if (oldWidget.selectedPostId != widget.selectedPostId) {
      setState(() {});
    }
  }

  Future<void> updatePositions() async {
    if (!mounted || widget.posts.isEmpty) return;

    final token = ++_updateToken;
    try {
      final points = await widget.controller.toScreenLocationBatch(
        widget.posts.map((post) => LatLng(post.lat, post.lng)),
      );
      if (!mounted || token != _updateToken) return;
      setState(() {
        _positions = {
          for (var index = 0; index < widget.posts.length; index++)
            widget.posts[index].id: Offset(
              points[index].x.toDouble(),
              points[index].y.toDouble(),
            ),
        };
      });
    } on Object {
      // Kortet kan være midt i reload.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        for (var index = 0; index < widget.posts.length; index++)
          if (_positions.containsKey(widget.posts[index].id))
            _PostOverlayMarker(
              position: _positions[widget.posts[index].id]!,
              post: widget.posts[index],
              index: index + 1,
              isSelected: widget.posts[index].id == widget.selectedPostId,
              onTap: () => widget.onPostTapped(widget.posts[index]),
            ),
      ],
    );
  }
}

class _PostOverlayMarker extends StatelessWidget {
  const _PostOverlayMarker({
    required this.position,
    required this.post,
    required this.index,
    required this.isSelected,
    required this.onTap,
  });

  final Offset position;
  final TreasureHuntPost post;
  final int index;
  final bool isSelected;
  final VoidCallback onTap;

  static const _pinSize = 28.0;
  static const _minTapSize = 44.0;

  @override
  Widget build(BuildContext context) {
    const pinColor = Color(0xFFF9A825);
    final selectedColor = isSelected ? const Color(0xFFE65100) : pinColor;

    final left = position.dx - _minTapSize / 2;
    final top = position.dy - _pinSize / 2;

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.translucent,
        child: SizedBox(
          width: _minTapSize,
          height: _minTapSize,
          child: Center(
            child: Material(
              elevation: 3,
              shadowColor: Colors.black38,
              shape: const CircleBorder(),
              child: Ink(
                width: _pinSize,
                height: _pinSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selectedColor,
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
