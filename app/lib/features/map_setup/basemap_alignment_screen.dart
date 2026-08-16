import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/constants.dart';
import '../../data/models/map_bounds.dart';
import '../../data/repositories/event_repository.dart';
import 'map_setup_flow.dart';

/// Manuel justering: semi-transparent tegning over OSM-kortet.
class BasemapAlignmentScreen extends StatefulWidget {
  const BasemapAlignmentScreen({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.initialBounds,
    this.initialViewBounds,
    required this.imageBytes,
    required this.fileExtension,
    this.fromEditor = false,
  });

  final String eventId;
  final String eventName;
  final MapBounds initialBounds;
  final MapBounds? initialViewBounds;
  final Uint8List imageBytes;
  final String fileExtension;
  final bool fromEditor;

  @override
  State<BasemapAlignmentScreen> createState() => _BasemapAlignmentScreenState();
}

class _BasemapAlignmentScreenState extends State<BasemapAlignmentScreen> {
  final _repository = EventRepository();
  final _mapKey = GlobalKey();

  MapLibreMapController? _controller;
  late MapBounds _imageBounds;
  MapBounds? _gestureStartBounds;
  Offset _gesturePan = Offset.zero;

  Rect? _screenRect;
  double _opacity = 0.55;
  bool _saving = false;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _imageBounds = widget.initialBounds;
    _initBoundsFromImageAspect();
  }

  Future<void> _initBoundsFromImageAspect() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      frame.image.dispose();
      if (w <= 0 || h <= 0 || !mounted) return;
      setState(() {
        _imageBounds = MapBounds.fitImageAspect(
          widget.initialBounds,
          w / h,
        );
      });
      await _updateOverlayGeometry();
    } on Object {
      // Behold initialBounds hvis billedet ikke kan afkodes.
    }
  }

  Future<void> _updateOverlayGeometry() async {
    final controller = _controller;
    if (controller == null || !_mapReady) return;

    final tl = await controller.toScreenLocation(
      LatLng(_imageBounds.north, _imageBounds.west),
    );
    final tr = await controller.toScreenLocation(
      LatLng(_imageBounds.north, _imageBounds.east),
    );
    final bl = await controller.toScreenLocation(
      LatLng(_imageBounds.south, _imageBounds.west),
    );
    final br = await controller.toScreenLocation(
      LatLng(_imageBounds.south, _imageBounds.east),
    );

    if (!mounted) return;
    setState(() {
      _screenRect = Rect.fromLTRB(
        math.min(tl.x, math.min(tr.x, math.min(bl.x, br.x))).toDouble(),
        math.min(tl.y, math.min(tr.y, math.min(bl.y, br.y))).toDouble(),
        math.max(tl.x, math.max(tr.x, math.max(bl.x, br.x))).toDouble(),
        math.max(tl.y, math.max(tr.y, math.max(bl.y, br.y))).toDouble(),
      );
    });
  }

  Future<({double lat, double lng})> _screenDeltaToGeo(Offset delta) async {
    final controller = _controller;
    final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (controller == null || box == null) return (lat: 0.0, lng: 0.0);

    final center = box.size.center(Offset.zero);
    final a = await controller.toLatLng(math.Point(center.dx, center.dy));
    final b = await controller.toLatLng(
      math.Point(center.dx + delta.dx, center.dy + delta.dy),
    );
    return (lat: b.latitude - a.latitude, lng: b.longitude - a.longitude);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartBounds = _imageBounds;
    _gesturePan = Offset.zero;
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails details) async {
    final start = _gestureStartBounds;
    if (start == null) return;

    _gesturePan += details.focalPointDelta;
    final pan = await _screenDeltaToGeo(_gesturePan);

    var bounds = start.scaledAroundCenter(1 / details.scale);
    bounds = bounds.translated(pan.lat, pan.lng);

    setState(() => _imageBounds = bounds);
    await _updateOverlayGeometry();
  }

  void _nudgeScale(double factor) {
    setState(() {
      _imageBounds = _imageBounds.scaledAroundCenter(factor);
    });
    _updateOverlayGeometry();
  }

  void _resetPlacement() {
    setState(() => _imageBounds = widget.initialBounds);
    _initBoundsFromImageAspect();
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      final expandedView = _imageBounds.scaledAroundCenter(
        AppConstants.areaViewBoundsExpansionFactor,
      );
      final viewBounds = (widget.initialViewBounds ?? expandedView)
          .encompassing(expandedView);

      await _repository.saveArea(
        eventId: widget.eventId,
        bounds: _imageBounds,
        viewBounds: viewBounds,
        centerLat: _imageBounds.centerLat,
        centerLng: _imageBounds.centerLng,
      );
      await _repository.uploadBasemap(
        eventId: widget.eventId,
        bytes: widget.imageBytes,
        fileExtension: widget.fileExtension,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Illustreret kort gemt og matchet')),
      );
      if (widget.fromEditor) {
        Navigator.pop(context, true);
      } else {
        MapSetupFlow.openEditor(
          context,
          eventId: widget.eventId,
          eventName: widget.eventName,
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke gemme: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  CameraPosition _initialCamera() {
    final b = widget.initialBounds;
    return CameraPosition(
      target: LatLng(b.centerLat, b.centerLng),
      zoom: AppConstants.defaultZoom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rect = _screenRect;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Match tegning med kort'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _resetPlacement,
            child: const Text('Nulstil'),
          ),
          FilledButton(
            onPressed: _saving || rect == null ? null : _confirm,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Gem'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              key: _mapKey,
              children: [
                MapLibreMap(
                  styleString: AppConstants.mapStyleUrl,
                  initialCameraPosition: _initialCamera(),
                  compassEnabled: false,
                  onMapCreated: (controller) {
                    _controller = controller;
                  },
                  onStyleLoadedCallback: () async {
                    _mapReady = true;
                    await _updateOverlayGeometry();
                  },
                  onCameraMove: (_) => _updateOverlayGeometry(),
                  onCameraIdle: () => _updateOverlayGeometry(),
                ),
                if (rect != null && rect.width > 4 && rect.height > 4)
                  Positioned.fromRect(
                    rect: rect,
                    child: GestureDetector(
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      child: Opacity(
                        opacity: _opacity,
                        child: Image.memory(
                          widget.imageBytes,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
                if (rect != null)
                  Positioned.fromRect(
                    rect: rect,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Material(
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Træk tegningen og knib for at zoome. '
                      'OSM-kortet vises kun her under placering — gæster ser bagefter kun tegningen.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.opacity, size: 20),
                        Expanded(
                          child: Slider(
                            value: _opacity,
                            min: 0.2,
                            max: 0.85,
                            label: '${(_opacity * 100).round()}%',
                            onChanged: (v) => setState(() => _opacity = v),
                          ),
                        ),
                        Text('${(_opacity * 100).round()}%'),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Gør tegningen mindre',
                          onPressed: () => _nudgeScale(1.05),
                          icon: const Icon(Icons.remove),
                        ),
                        const SizedBox(width: 8),
                        Text('Skaler', style: theme.textTheme.labelLarge),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Gør tegningen større',
                          onPressed: () => _nudgeScale(0.95),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vælg billede og åbn justeringsskærmen.
Future<bool> pickAndAlignBasemap(
  BuildContext context, {
  required String eventId,
  required String eventName,
  required MapBounds bounds,
  MapBounds? viewBounds,
  bool fromEditor = false,
}) async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (file == null || !context.mounted) return false;

  final bytes = await file.readAsBytes();
  final ext = file.path.split('.').last.toLowerCase();
  if (!context.mounted) return false;

  final saved = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (context) => BasemapAlignmentScreen(
        eventId: eventId,
        eventName: eventName,
        initialBounds: bounds,
        initialViewBounds: viewBounds,
        imageBytes: bytes,
        fileExtension: ext == 'jpg' || ext == 'jpeg' ? 'jpg' : ext,
        fromEditor: fromEditor,
      ),
    ),
  );
  return saved ?? false;
}
