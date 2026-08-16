import 'package:flutter/material.dart';

import '../audio_tour_guidance_controller.dart';

class VisitorAudioTourBar extends StatelessWidget {
  const VisitorAudioTourBar({
    super.key,
    required this.controller,
  });

  final AudioTourGuidanceController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final phase = controller.phase;
        final wander = controller.wanderEnRoute;

        return Material(
          elevation: 4,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFF6A1B9A).withValues(alpha: 0.12),
                      child: Icon(
                        phase == AudioTourPhase.playingWander ||
                                phase == AudioTourPhase.walkingToNext
                            ? Icons.directions_walk
                            : Icons.headphones,
                        color: const Color(0xFF6A1B9A),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            controller.statusTitle,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          if (controller.statusSubtitle.isNotEmpty)
                            Text(
                              controller.statusSubtitle,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (controller.distanceMeters > 0 &&
                    (phase == AudioTourPhase.navigateToStop ||
                        phase == AudioTourPhase.walkingToNext)) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Ca. ${controller.distanceMeters.round()} m',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (phase == AudioTourPhase.readyAtStop) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: controller.canPlayStop ? controller.playCurrentStop : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Afspil'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      backgroundColor: const Color(0xFF6A1B9A),
                    ),
                  ),
                ],
                if (phase == AudioTourPhase.walkingToNext && wander != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: controller.playWander,
                    icon: Icon(
                      controller.phase == AudioTourPhase.playingWander &&
                              controller.isPlaying
                          ? Icons.pause
                          : Icons.music_note,
                    ),
                    label: Text(
                      wander.title?.isNotEmpty == true
                          ? 'Afspil ${wander.title}'
                          : 'Afspil vandrelyd',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Du kan lytte mens du går — ellers tryk når du er klar',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (phase == AudioTourPhase.playingStop ||
                    phase == AudioTourPhase.playingWander) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        onPressed: controller.togglePlayback,
                        icon: Icon(
                          controller.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                          size: 36,
                          color: const Color(0xFF6A1B9A),
                        ),
                      ),
                      Expanded(
                        child: controller.duration != null
                            ? Slider(
                                value: (controller.position.inMilliseconds /
                                        controller.duration!.inMilliseconds)
                                    .clamp(0.0, 1.0),
                                onChanged: (value) {
                                  controller.seek(
                                    Duration(
                                      milliseconds: (controller.duration!.inMilliseconds * value)
                                          .round(),
                                    ),
                                  );
                                },
                              )
                            : const LinearProgressIndicator(),
                      ),
                    ],
                  ),
                ],
                if (phase == AudioTourPhase.completed) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Du har gennemført alle stop på lydvandringen.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (controller.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    controller.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
