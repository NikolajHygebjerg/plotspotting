import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../data/models/poi_media.dart';

class PoiMediaViewer extends StatelessWidget {
  const PoiMediaViewer({super.key, required this.media});

  final List<PoiMedia> media;

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) return const SizedBox.shrink();

    final images = media.where((item) => item.kind == PoiMediaKind.image).toList();
    final videos = media.where((item) => item.kind == PoiMediaKind.video).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (images.isNotEmpty) ...[
          Text('Billeder', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final image = images[index];
                return GestureDetector(
                  onTap: () => _openImage(context, images, index),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      image.url,
                      width: 200,
                      height: 140,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _errorTile(Icons.broken_image_outlined),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (videos.isNotEmpty) ...[
          if (images.isNotEmpty) const SizedBox(height: 16),
          Text('Video', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...videos.map((video) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PoiVideoPlayer(url: video.url),
              )),
        ],
      ],
    );
  }

  void _openImage(BuildContext context, List<PoiMedia> images, int initialIndex) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog.fullscreen(
          child: Stack(
            children: [
              PageView.builder(
                controller: PageController(initialPage: initialIndex),
                itemCount: images.length,
                itemBuilder: (context, index) {
                  return InteractiveViewer(
                    child: Center(
                      child: Image.network(
                        images[index].url,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => _errorTile(Icons.broken_image_outlined),
                      ),
                    ),
                  );
                },
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _errorTile(IconData icon) {
    return ColoredBox(
      color: Colors.grey.shade200,
      child: Center(child: Icon(icon, size: 40, color: Colors.grey.shade600)),
    );
  }
}

class _PoiVideoPlayer extends StatefulWidget {
  const _PoiVideoPlayer({required this.url});

  final String url;

  @override
  State<_PoiVideoPlayer> createState() => _PoiVideoPlayerState();
}

class _PoiVideoPlayerState extends State<_PoiVideoPlayer> {
  VideoPlayerController? _controller;
  var _initialized = false;
  var _failed = false;
  var _loading = false;

  Future<void> _startPlayback() async {
    if (_loading || _initialized || _failed) return;

    setState(() => _loading = true);

    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _initialized = true;
        _loading = false;
      });
      await controller.play();
    } on Object {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.grey.shade200,
          child: const Center(child: Text('Kunne ikke afspille video')),
        ),
      );
    }

    if (!_initialized) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ColoredBox(
            color: Colors.grey.shade200,
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : IconButton.filled(
                      iconSize: 48,
                      onPressed: _startPlayback,
                      icon: const Icon(Icons.play_arrow),
                    ),
            ),
          ),
        ),
      );
    }

    final controller = _controller!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(controller),
            if (!controller.value.isPlaying)
              IconButton.filled(
                iconSize: 48,
                onPressed: () => setState(() => controller.play()),
                icon: const Icon(Icons.play_arrow),
              ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: Theme.of(context).colorScheme.primary,
                  bufferedColor: Colors.white54,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
