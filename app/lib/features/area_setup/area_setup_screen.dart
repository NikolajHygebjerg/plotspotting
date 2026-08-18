import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/constants.dart';
import '../../core/geo/geocoding_service.dart';
import '../../core/utils/debounce.dart';
import '../../data/models/map_bounds.dart';
import '../../data/repositories/event_repository.dart';
import '../../widgets/event_map_widget.dart';
import '../../data/models/event_map_data.dart';
import '../map_setup/map_setup_flow.dart';
import '../map_setup/map_setup_step_header.dart';
import 'widgets/area_crop_overlay.dart';

/// Vælg det geografiske område kortet skal dække.
class AreaSetupScreen extends StatefulWidget {
  const AreaSetupScreen({
    super.key,
    required this.eventId,
    required this.eventName,
    this.initialCenter,
    this.initialBounds,
    this.onboarding = false,
  });

  final String eventId;
  final String eventName;
  final ll.LatLng? initialCenter;
  final MapBounds? initialBounds;
  /// Når true, fortsætter flowet til korttype-valg i stedet for at poppe tilbage.
  final bool onboarding;

  @override
  State<AreaSetupScreen> createState() => _AreaSetupScreenState();
}

class _AreaSetupScreenState extends State<AreaSetupScreen> {
  final _repository = EventRepository();
  final _geocoding = GeocodingService();
  final _mapKey = GlobalKey();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _searchDebouncer = Debouncer(const Duration(milliseconds: 350));

  MapLibreMapController? _controller;
  bool _saving = false;
  bool _searching = false;
  String? _searchError;
  List<GeocodingResult> _searchResults = const [];
  double _cropFraction = 0.55;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitInitialView());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _searchDebouncer.dispose();
    super.dispose();
  }

  Future<void> _fitInitialView() async {
    final bounds = widget.initialBounds;
    final controller = _controller;
    if (bounds == null || !bounds.isValid || controller == null) return;

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          bounds.toLatLngBounds(),
          left: 48,
          top: 48,
          right: 48,
          bottom: 48,
        ),
      );
    } on Object {
      // Map may not be ready yet.
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    if (query.trim().length < 3) {
      setState(() {
        _searchResults = const [];
        _searchError = null;
        _searching = false;
      });
      return;
    }

    setState(() {
      _searching = true;
      _searchError = null;
    });

    _searchDebouncer.run(() async {
      try {
        final results = await _geocoding.search(query);
        if (!mounted || _searchController.text != query) return;
        setState(() {
          _searchResults = results;
          _searching = false;
        });
      } catch (error) {
        if (!mounted || _searchController.text != query) return;
        setState(() {
          _searchResults = const [];
          _searching = false;
          _searchError = '$error';
        });
      }
    });
  }

  Future<void> _selectSearchResult(GeocodingResult result) async {
    final controller = _controller;
    if (controller == null) return;

    setState(() {
      _searchResults = const [];
      _searchError = null;
      _searchController.text = result.displayName.split(',').first;
    });
    _searchFocus.unfocus();

    final bounds = result.bounds;
    if (bounds != null) {
      try {
        await controller.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(bounds.south, bounds.west),
              northeast: LatLng(bounds.north, bounds.east),
            ),
            left: 56,
            top: 120,
            right: 56,
            bottom: 120,
          ),
        );
        return;
      } on Object {
        // Fall through to point zoom.
      }
    }

    final zoom = bounds?.estimateZoom() ?? AppConstants.defaultZoom;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(result.lat, result.lng), zoom),
    );
  }

  Future<MapBounds?> _cropFrameToBounds() async {
    final controller = _controller;
    final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (controller == null || box == null) return null;

    final size = box.size;
    final side = size.shortestSide * _cropFraction;
    final center = size.center(Offset.zero);
    final rect = Rect.fromCenter(center: center, width: side, height: side);

    final topLeft = await controller.toLatLng(math.Point(rect.left, rect.top));
    final bottomRight = await controller.toLatLng(math.Point(rect.right, rect.bottom));

    return MapBounds(
      south: bottomRight.latitude,
      west: topLeft.longitude,
      north: topLeft.latitude,
      east: bottomRight.longitude,
    );
  }

  Future<void> _captureVisibleArea() async {
    if (_controller == null) return;

    setState(() => _saving = true);
    try {
      final contentBounds = await _cropFrameToBounds();
      if (contentBounds == null || !contentBounds.isValid) {
        throw Exception('Kunne ikke beregne kortudsnit — prøv igen');
      }

      final viewBounds = contentBounds.scaledAroundCenter(
        AppConstants.areaViewBoundsExpansionFactor,
      );

      await _repository.saveArea(
        eventId: widget.eventId,
        bounds: contentBounds,
        viewBounds: viewBounds,
        centerLat: contentBounds.centerLat,
        centerLng: contentBounds.centerLng,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kortudsnit gemt — gæster kan zoome og panorerer i et større område',
          ),
        ),
      );

      if (widget.onboarding) {
        MapSetupFlow.continueAfterAreaSaved(
          context,
          eventId: widget.eventId,
          eventName: widget.eventName,
          bounds: contentBounds,
        );
      } else {
        Navigator.pop(context, contentBounds);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke gemme område: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.onboarding ? 'Vælg kortområde' : 'Skift kortområde'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onboarding) const MapSetupStepHeader(currentStep: 0),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Søg på en adresse, træk kortet så området ligger i rammen, '
                  'og justér størrelsen med skyderen.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Material(
                  elevation: 2,
                  borderRadius: BorderRadius.circular(28),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    decoration: InputDecoration(
                      hintText: 'Søg adresse…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _searchController,
                        builder: (context, value, _) {
                          if (_searching) {
                            return const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          }
                          if (value.text.isEmpty) return null;
                          return IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchResults = const [];
                                _searchError = null;
                              });
                            },
                          );
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) {
                      if (_searchResults.isNotEmpty) {
                        _selectSearchResult(_searchResults.first);
                      }
                    },
                  ),
                ),
                if (_searchError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _searchError!,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
                if (_searchResults.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Material(
                    elevation: 3,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final result = _searchResults[index];
                          return ListTile(
                            leading: const Icon(Icons.place_outlined),
                            title: Text(
                              result.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _selectSearchResult(result),
                          );
                        },
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                AreaCropSizeControl(
                  cropFraction: _cropFraction,
                  onChanged: (value) => setState(() => _cropFraction = value),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              key: _mapKey,
              children: [
                EventMapWidget(
                  data: EventMapData(
                    event: EventMeta(
                      id: widget.eventId,
                      name: widget.eventName,
                      bounds: widget.initialBounds,
                    ),
                  ),
                  initialCenter: widget.initialCenter ??
                      const ll.LatLng(
                        AppConstants.frilandCenterLat,
                        AppConstants.frilandCenterLng,
                      ),
                  myLocationEnabled: true,
                  onMapCreated: (controller) {
                    _controller = controller;
                    _fitInitialView();
                  },
                ),
                AreaCropOverlay(cropFraction: _cropFraction),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _saving ? null : _captureVisibleArea,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.crop_free),
                label: Text(
                  widget.onboarding ? 'Gem kortudsnit og fortsæt' : 'Gem kortudsnit',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
