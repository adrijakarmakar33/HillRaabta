import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../core/storage/chat_store.dart';

const _distanceCalc = Distance();

class OfflineMapScreen extends StatefulWidget {
  const OfflineMapScreen({super.key});

  @override
  State<OfflineMapScreen> createState() => _OfflineMapScreenState();
}

class _OfflineMapScreenState extends State<OfflineMapScreen> {
  final MapController _mapController = MapController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _mapSectionKey = GlobalKey();
  final TextEditingController _manualCurrentCtrl = TextEditingController();
  final TextEditingController _manualDestCtrl = TextEditingController();
  final TextEditingController _destNameCtrl = TextEditingController();

  StreamSubscription<Position>? _positionSub;
  Position? _current;
  LatLng? _manualCurrent;
  LatLng? _destination;
  String? _onlineDestinationName;
  String _tilesDir = '';
  final List<_SavedPlace> _places = [];
  _SavedPlace? _selectedPlace;
  String _status = 'Starting GPS...';
  bool _manualMode = false;
  bool _pickOnMapMode = false;
  bool _searchingOnline = false;
  bool _mapReady = false;
  LatLng? _pendingCameraTarget;
  double _pendingCameraZoom = 11;
  bool _pendingFitBounds = false;
  LatLngBounds? _pendingBounds;

  @override
  void initState() {
    super.initState();
    _startTracking();
    _loadOfflineConfig();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _scrollController.dispose();
    _manualCurrentCtrl.dispose();
    _manualDestCtrl.dispose();
    _destNameCtrl.dispose();
    super.dispose();
  }

  bool get _useOfflineTiles {
    if (_tilesDir.trim().isEmpty) return false;
    return Directory(_tilesDir).existsSync();
  }

  void _onMapReady() {
    _mapReady = true;
    _applyPendingCamera();
  }

  void _applyPendingCamera() {
    if (!_mapReady) return;
    if (_pendingFitBounds && _pendingBounds != null) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: _pendingBounds!,
          padding: const EdgeInsets.all(64),
        ),
      );
      _pendingFitBounds = false;
      _pendingBounds = null;
      return;
    }
    if (_pendingCameraTarget != null) {
      _mapController.move(_pendingCameraTarget!, _pendingCameraZoom);
      _pendingCameraTarget = null;
    }
  }

  void _fitRouteView() {
    final dest = _destination;
    if (dest == null) return;

    final cur = _curPoint;
    if (cur != null) {
      _pendingFitBounds = true;
      _pendingBounds = LatLngBounds(cur, dest);
      _pendingCameraTarget = null;
    } else {
      _pendingFitBounds = false;
      _pendingBounds = null;
      _pendingCameraTarget = dest;
      _pendingCameraZoom = 11;
    }
    _applyPendingCamera();
  }

  void _scrollToMap() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _mapSectionKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _loadOfflineConfig() async {
    final dir = await ChatStore.instance.getSetting('offline_tiles_dir');
    final rows = await ChatStore.instance.listSavedPlaces();
    final places = rows
        .map((r) => _SavedPlace(
              id: r['id'] as int,
              name: (r['name'] as String?) ?? 'Place',
              lat: (r['lat'] as num).toDouble(),
              lng: (r['lng'] as num).toDouble(),
            ))
        .toList();
    if (!mounted) return;
    setState(() {
      _tilesDir = dir ?? '';
      _places
        ..clear()
        ..addAll(places);
      if (_selectedPlace != null) {
        final stillExists = _places.any((p) => p.id == _selectedPlace!.id);
        if (!stillExists) {
          _selectedPlace = null;
          _destination = null;
          _onlineDestinationName = null;
        }
      }
    });
  }

  Future<void> _startTracking() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      setState(() => _status = 'Turn on location in Settings');
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => _status = 'Location permission denied');
      return;
    }

    try {
      final initial = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _current = initial;
          _status = 'GPS active';
        });
        if (_destination != null) _fitRouteView();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'Getting GPS fix...');
      }
    }

    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((p) {
      final isFirstFix = _current == null;
      setState(() {
        _current = p;
        _status = 'GPS active';
      });
      if (isFirstFix && _destination != null) {
        _fitRouteView();
      }
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String get _destinationLabel {
    if (_selectedPlace != null) return _selectedPlace!.name;
    if (_onlineDestinationName != null) return _onlineDestinationName!;
    if (_destination != null) return 'Picked on map';
    return '';
  }

  Future<void> _pickTilesFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select offline map folder',
    );
    if (dir == null || dir.trim().isEmpty) return;
    await ChatStore.instance.setSetting('offline_tiles_dir', dir.trim());
    if (!mounted) return;
    setState(() => _tilesDir = dir.trim());
    _showSnack('Offline map pack selected');
  }

  Future<void> _saveCurrentAsPlace() async {
    final cur = _current;
    if (cur == null) {
      _showSnack('Wait for GPS location first');
      return;
    }
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save place'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Place name',
            hintText: 'e.g. Camp, Hotel, View Point',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;

    await ChatStore.instance.addSavedPlace(
      name: name,
      lat: cur.latitude,
      lng: cur.longitude,
    );
    await _loadOfflineConfig();
    _showSnack('Saved: $name');
  }

  Future<void> _applyDestination(
    LatLng dest, {
    required String name,
    _SavedPlace? place,
    bool persist = true,
  }) async {
    _SavedPlace? selected = place;
    if (persist) {
      final id = await ChatStore.instance.upsertSavedPlace(
        name: name,
        lat: dest.latitude,
        lng: dest.longitude,
      );
      await _loadOfflineConfig();
      for (final p in _places) {
        if (p.id == id) {
          selected = p;
          break;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _destination = dest;
      _selectedPlace = selected;
      _onlineDestinationName = null;
    });
    _fitRouteView();
    _scrollToMap();
  }

  void _selectPlace(_SavedPlace place) {
    unawaited(_applyDestination(
      LatLng(place.lat, place.lng),
      name: place.name,
      place: place,
      persist: false,
    ));
  }

  List<_SavedPlace> get _filteredPlaces {
    final q = _destNameCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _places;
    return _places.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  LatLng? get _gpsPoint {
    final gps = _current;
    if (gps == null) return null;
    return LatLng(gps.latitude, gps.longitude);
  }

  LatLng? get _curPoint => _manualMode ? _manualCurrent : _gpsPoint;

  Future<void> _handleSearch() async {
    final q = _destNameCtrl.text.trim();
    if (q.isEmpty) {
      _showSnack('Type a place name or lat,lng');
      return;
    }

    final coords = _parseLatLng(q);
    if (coords != null) {
      await _applyDestination(coords, name: q);
      _showSnack('Route saved for offline use');
      return;
    }

    final exact = _places
        .where((p) => p.name.toLowerCase() == q.toLowerCase())
        .toList();
    if (exact.length == 1) {
      _selectPlace(exact.first);
      return;
    }

    if (_filteredPlaces.length == 1) {
      _selectPlace(_filteredPlaces.first);
      return;
    }

    if (_filteredPlaces.length > 1) {
      _showSnack('Tap a saved place from the list');
      return;
    }

    await _searchOnline();
  }

  Future<_GeocodeHit?> _geocodePlace(String query) async {
    try {
      final results = await locationFromAddress(query);
      if (results.isNotEmpty) {
        final loc = results.first;
        return _GeocodeHit(
          point: LatLng(loc.latitude, loc.longitude),
          label: query,
        );
      }
    } catch (_) {}

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '1',
      });
      final res = await http.get(
        uri,
        headers: const {'User-Agent': 'HillRaabta/1.0 (offline travel app)'},
      );
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        if (list.isNotEmpty) {
          final item = list.first as Map<String, dynamic>;
          final display = (item['display_name'] as String?) ?? query;
          final shortName = display.split(',').first.trim();
          return _GeocodeHit(
            point: LatLng(
              double.parse(item['lat'] as String),
              double.parse(item['lon'] as String),
            ),
            label: shortName.isEmpty ? query : shortName,
          );
        }
      }
    } catch (_) {}

    return null;
  }

  Future<void> _searchOnline() async {
    final q = _destNameCtrl.text.trim();
    if (q.isEmpty) {
      _showSnack('Type a place name first');
      return;
    }

    setState(() => _searchingOnline = true);
    try {
      final hit = await _geocodePlace(q);
      if (!mounted) return;
      if (hit == null) {
        _showSnack('No results for "$q". Try another spelling or lat,lng.');
        return;
      }

      await _applyDestination(hit.point, name: hit.label);
      _showSnack('${hit.label} saved — route works offline');
    } finally {
      if (mounted) setState(() => _searchingOnline = false);
    }
  }

  Future<void> _savePickedDestination(LatLng point) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save destination'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Destination name',
            hintText: 'e.g. Camp, View Point',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;

    await ChatStore.instance.addSavedPlace(
      name: name,
      lat: point.latitude,
      lng: point.longitude,
    );
    await _loadOfflineConfig();
    if (!mounted) return;
    final match = _places.cast<_SavedPlace?>().firstWhere(
              (p) => p?.name == name,
              orElse: () => null,
            ) ??
        _places.first;
    _selectPlace(match);
    _showSnack('Saved destination: $name');
  }

  Future<void> _onMapLongPress(LatLng point) async {
    if (!_pickOnMapMode) return;
    setState(() {
      _destination = point;
      _selectedPlace = null;
      _onlineDestinationName = null;
      _manualMode = false;
    });
    await _savePickedDestination(point);
  }

  LatLng? _parseLatLng(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    final parts = cleaned.split(RegExp(r'[\s,]+')).where((p) => p.isNotEmpty);
    final list = parts.toList(growable: false);
    if (list.length < 2) return null;
    final lat = double.tryParse(list[0]);
    final lng = double.tryParse(list[1]);
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return LatLng(lat, lng);
  }

  Future<void> _applyManualLocations() async {
    final cur = _parseLatLng(_manualCurrentCtrl.text);
    final dest = _parseLatLng(_manualDestCtrl.text);
    if (cur == null || dest == null) {
      _showSnack('Enter locations as lat,lng (example: 27.7172, 85.3240)');
      return;
    }

    setState(() => _manualCurrent = cur);
    final destLabel = _manualDestCtrl.text.trim();
    final name = _parseLatLng(destLabel) == null && destLabel.isNotEmpty
        ? destLabel
        : '${dest.latitude.toStringAsFixed(4)}, ${dest.longitude.toStringAsFixed(4)}';
    await _applyDestination(dest, name: name);
    _showSnack('Route saved for offline use');
  }

  String _distanceLabel(double? distanceM, bool hasDestination) {
    if (!hasDestination) {
      return 'Pick a destination below';
    }
    if (distanceM == null) {
      return 'Waiting for GPS...';
    }
    return _prettyDistance(distanceM);
  }

  @override
  Widget build(BuildContext context) {
    final gps = _current;
    final curPoint = _curPoint;
    final dest = _destination;
    final hasDestination = dest != null;
    final tilesRoot = _tilesDir.replaceAll('\\', '/');
    final filtered = _filteredPlaces;
    final query = _destNameCtrl.text.trim();

    double? distanceM;
    if (curPoint != null && dest != null) {
      distanceM = Geolocator.distanceBetween(
        curPoint.latitude,
        curPoint.longitude,
        dest.latitude,
        dest.longitude,
      );
    }

    final markers = <Marker>[
      if (curPoint != null)
        Marker(
          point: curPoint,
          width: 44,
          height: 44,
          child: const Icon(Icons.my_location, color: Colors.blue, size: 28),
        ),
      if (dest != null)
        Marker(
          point: dest,
          width: 44,
          height: 44,
          child: const Icon(Icons.location_on, color: Colors.red, size: 32),
        ),
    ];
    final hasRoute = curPoint != null && dest != null;
    final line = hasRoute
        ? [
            Polyline(
              points: [curPoint, dest],
              strokeWidth: 8,
              color: Colors.white,
            ),
            Polyline(
              points: [curPoint, dest],
              strokeWidth: 5,
              color: const Color(0xFF1D9E75),
            ),
          ]
        : <Polyline>[];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D9E75),
        title: const Text(
          'Map & Route',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          _summaryCard(
            distanceM: distanceM,
            hasDestination: hasDestination,
            destinationName: _destinationLabel,
            gps: gps,
            curPoint: curPoint,
            dest: dest,
          ),
          const SizedBox(height: 12),
          _card(
            key: _mapSectionKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Route map',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (hasDestination && curPoint != null)
                      TextButton.icon(
                        onPressed: _fitRouteView,
                        icon: const Icon(Icons.center_focus_strong, size: 18),
                        label: const Text('Fit route'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF1D9E75),
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                  ],
                ),
                if (hasDestination) ...[
                  const SizedBox(height: 4),
                  Text(
                    curPoint != null
                        ? 'You → $_destinationLabel'
                        : 'Waiting for GPS to draw route to $_destinationLabel',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  height: 280,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter:
                                dest ?? curPoint ?? const LatLng(22.5726, 88.3639),
                            initialZoom: dest != null ? 11 : 13,
                            onMapReady: _onMapReady,
                            onLongPress: (tapPosition, point) =>
                                _onMapLongPress(point),
                          ),
                          children: [
                            if (_useOfflineTiles)
                              TileLayer(
                                urlTemplate: '$tilesRoot/{z}/{x}/{y}.png',
                                tileProvider: FileTileProvider(),
                              )
                            else
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.example.hill_raabta',
                              ),
                            PolylineLayer(polylines: line),
                            MarkerLayer(markers: markers),
                          ],
                        ),
                        if (!_useOfflineTiles)
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 8,
                            child: Material(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(8),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.wifi,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Using online map tiles. For offline trips, set a map pack in More options.',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (hasDestination && curPoint == null)
                          Positioned(
                            top: 8,
                            left: 8,
                            right: 8,
                            child: Material(
                              color: Colors.orange.shade800,
                              borderRadius: BorderRadius.circular(8),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                child: Text(
                                  'Turn on GPS to show route from your location',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (_pickOnMapMode)
                          Positioned(
                            top: 8,
                            left: 8,
                            right: 8,
                            child: Material(
                              color: const Color(0xFF1D9E75),
                              borderRadius: BorderRadius.circular(8),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                child: Text(
                                  'Long-press on the map to set destination',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (hasDestination) ...[
                  const SizedBox(height: 10),
                  _routeGuide(curPoint: curPoint, dest: dest, distanceM: distanceM),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Where to go?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Any place name or lat,lng. Search once online — route & distance work offline later.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _destNameCtrl,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Search',
                    hintText: 'Any city, camp, or lat,lng',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    suffixIcon: _searchingOnline
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: 'Search online',
                            onPressed: _handleSearch,
                            icon: const Icon(Icons.travel_explore),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _handleSearch(),
                ),
                const SizedBox(height: 10),
                if (_places.isEmpty && query.isEmpty)
                  _emptyPlacesHint()
                else if (filtered.isNotEmpty)
                  ...filtered.map(_placeTile)
                else if (query.isNotEmpty)
                  _noLocalMatchHint(query),
                if (hasDestination) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.flag,
                        size: 18,
                        color: Color(0xFF1D9E75),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Selected: $_destinationLabel',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saveCurrentAsPlace,
                        icon: const Icon(Icons.bookmark_add, size: 18),
                        label: const Text('Save here'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            setState(() => _pickOnMapMode = !_pickOnMapMode),
                        icon: Icon(
                          _pickOnMapMode
                              ? Icons.touch_app
                              : Icons.add_location_alt_outlined,
                          size: 18,
                        ),
                        label: Text(
                          _pickOnMapMode ? 'Map pick ON' : 'Pick on map',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text(
                'More options',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                _useOfflineTiles
                    ? 'Offline map pack set'
                    : 'Online map (needs internet), manual GPS',
                style: const TextStyle(fontSize: 12),
              ),
              children: [
                const Divider(height: 1),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_open),
                  title: const Text('Offline map pack (optional)'),
                  subtitle: Text(
                    _useOfflineTiles
                        ? _tilesDir
                        : _tilesDir.isNotEmpty
                            ? 'Saved folder not found — using online map. Select a valid folder.'
                            : 'Download map tiles before your trip, then select the folder here',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickTilesFolder,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _manualMode,
                  onChanged: (v) => setState(() => _manualMode = v),
                  title: const Text('Manual GPS'),
                  subtitle: const Text('Enter lat,lng if GPS is weak'),
                ),
                if (_manualMode) ...[
                  TextField(
                    controller: _manualCurrentCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Your location',
                      hintText: 'lat,lng',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _manualDestCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Destination',
                      hintText: 'lat,lng',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _applyManualLocations,
                      icon: const Icon(Icons.route),
                      label: const Text('Show route'),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: _startTracking,
                  icon: const Icon(Icons.gps_fixed),
                  label: const Text('Refresh GPS'),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeGuide({
    required LatLng? curPoint,
    required LatLng? dest,
    required double? distanceM,
  }) {
    final bearing =
        (curPoint != null && dest != null) ? _distanceCalc.bearing(curPoint, dest) : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1D9E75).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.navigation, size: 18, color: Color(0xFF1D9E75)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  bearing == null
                      ? 'Route will draw from your location once GPS is ready'
                      : 'From you → destination: head ${_bearingLabel(bearing)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Row(
            children: [
              Icon(Icons.circle, size: 10, color: Colors.blue),
              SizedBox(width: 6),
              Text('You', style: TextStyle(fontSize: 12)),
              SizedBox(width: 14),
              Icon(Icons.circle, size: 10, color: Colors.red),
              SizedBox(width: 6),
              Text('Destination', style: TextStyle(fontSize: 12)),
              SizedBox(width: 14),
              Icon(Icons.show_chart, size: 14, color: Color(0xFF1D9E75)),
              SizedBox(width: 4),
              Text('Route line', style: TextStyle(fontSize: 12)),
            ],
          ),
          if (distanceM != null) ...[
            const SizedBox(height: 6),
            Text(
              'Straight-line distance: ${_prettyDistance(distanceM)} (works without internet)',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryCard({
    required double? distanceM,
    required bool hasDestination,
    required String destinationName,
    required Position? gps,
    required LatLng? curPoint,
    required LatLng? dest,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D9E75), Color(0xFF168A66)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasDestination && distanceM != null
                ? _distanceLabel(distanceM, true)
                : _distanceLabel(distanceM, hasDestination),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasDestination
                ? 'Destination: $destinationName'
                : 'No destination selected',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (curPoint != null && dest != null && distanceM != null) ...[
            const SizedBox(height: 6),
            Text(
              'Direction: ${_bearingLabel(_distanceCalc.bearing(curPoint, dest))}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                gps == null ? Icons.gps_not_fixed : Icons.gps_fixed,
                color: Colors.white.withValues(alpha: 0.9),
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  gps == null
                      ? _status
                      : 'You: ${gps.latitude.toStringAsFixed(4)}, ${gps.longitude.toStringAsFixed(4)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyPlacesHint() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1D9E75).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'First time?',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 4),
          Text(
            '1. Search any place while online (city, camp, hotel)\n'
            '2. Route + distance are saved on your phone\n'
            '3. Later offline: pick from list and follow the green line',
            style: TextStyle(fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _noLocalMatchHint(String query) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No saved place matches "$query".',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _searchingOnline ? null : _handleSearch,
              icon: const Icon(Icons.travel_explore),
              label: Text('Search online for "$query"'),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Needs internet once. After that, route & distance work offline.',
            style: TextStyle(fontSize: 11, color: Colors.black45),
          ),
        ],
      ),
    );
  }

  Widget _placeTile(_SavedPlace place) {
    final selected = _selectedPlace?.id == place.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? const Color(0xFF1D9E75).withValues(alpha: 0.12)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _manualMode ? null : () => _selectPlace(place),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.place_outlined,
                  color: selected
                      ? const Color(0xFF1D9E75)
                      : Colors.grey.shade600,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.name,
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${place.lat.toStringAsFixed(4)}, ${place.lng.toStringAsFixed(4)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF1D9E75),
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card({Key? key, required Widget child}) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: child,
    );
  }

  String _prettyDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }

  String _bearingLabel(double bearing) {
    const dirs = ['North', 'North-East', 'East', 'South-East', 'South', 'South-West', 'West', 'North-West'];
    final idx = (((bearing + 22.5) % 360) / 45).floor();
    return dirs[idx];
  }
}

class _GeocodeHit {
  final LatLng point;
  final String label;

  const _GeocodeHit({required this.point, required this.label});
}

class _SavedPlace {
  final int id;
  final String name;
  final double lat;
  final double lng;

  const _SavedPlace({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
  });
}
