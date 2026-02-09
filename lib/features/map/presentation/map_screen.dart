import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pfe1/features/business/presentation/user_business_profile_screen.dart';
import 'package:pfe1/shared/theme/theme_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/theme/app_colors.dart';
import '../data/map_provider.dart';
import '../../business/domain/business_model.dart';
import '../../business/data/business_list_provider.dart';
import '../data/places_search_service.dart';

class MapScreen extends ConsumerStatefulWidget {
  final int? initialBusinessId;
  final double? initialLatitude;
  final double? initialLongitude;

  const MapScreen({
    Key? key,
    this.initialBusinessId,
    this.initialLatitude,
    this.initialLongitude,
  }) : super(key: key);

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  bool _locationPermissionChecked = false;
  String? _profileImageUrl;
  final _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  BusinessModel? _selectedBusiness;

  // Location tracking for navigation
  Stream<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await _checkLocationPermission();
      await _fetchUserProfile();
      ref.read(mapProvider.notifier).initializeMap();
      await ref.read(businessListProvider.notifier).fetchAllBusinesses();

      // Handle initial business location
      if (widget.initialBusinessId != null &&
          widget.initialLatitude != null &&
          widget.initialLongitude != null) {
        _handleInitialBusiness();
      }
    });

    _searchController.addListener(_onSearchChanged);
  }

  void _handleInitialBusiness() async {
    // Wait for businesses to load
    await Future.delayed(const Duration(milliseconds: 500));

    final businessesState = ref.read(businessListProvider);
    businessesState.whenData((businesses) {
      final business = businesses.firstWhere(
        (b) => b.id == widget.initialBusinessId,
        orElse: () => businesses.first,
      );

      if (business.latitude != null && business.longitude != null) {
        final location = LatLng(business.latitude!, business.longitude!);
        _mapController.move(location, 15.0);
        setState(() => _selectedBusiness = business);
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  DateTime _lastSearchTime = DateTime.now();
  void _onSearchChanged() {
    final now = DateTime.now();
    if (now.difference(_lastSearchTime) > const Duration(milliseconds: 300)) {
      _lastSearchTime = now;
      if (_searchController.text.isNotEmpty) {
        _searchBusiness(_searchController.text);
        ref
            .read(placesSearchProvider.notifier)
            .searchPlaces(_searchController.text);
      } else {
        ref.read(businessSearchProvider.notifier).searchBusinesses('');
        ref.read(placesSearchProvider.notifier).clear();
      }
    }
  }

  void _onPlaceSelected(PlaceResult place) {
    _mapController.move(place.location, 15.0);

    // Mark the location on the map
    ref.read(mapProvider.notifier).onMapTap(place.location);

    // Clear search
    _searchController.clear();
    ref.read(businessSearchProvider.notifier).searchBusinesses('');
    ref.read(placesSearchProvider.notifier).clear();
  }

  Future<void> _fetchUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null && user.email != null) {
        final response = await _supabase
            .from('user')
            .select('profile_image_url')
            .eq('email', user.email!)
            .single();

        if (response != null && response['profile_image_url'] != null) {
          setState(() {
            _profileImageUrl = response['profile_image_url'];
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
    }
  }

  Future<void> _searchPlace(String query) async {
    if (query.isEmpty) return;
    setState(() => _isSearching = true);

    try {
      await _searchBusiness(query);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error searching for "$query"'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _searchBusiness(String query) async {
    if (query.isEmpty) return;
    setState(() => _isSearching = true);

    try {
      await ref.read(businessSearchProvider.notifier).searchBusinesses(query);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error searching for "$query"'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSearching = false);
    }
  }

  void _onBusinessSelected(BusinessModel business) {
    setState(() => _selectedBusiness = business);

    if (business.latitude != null && business.longitude != null) {
      final businessLocation = LatLng(business.latitude!, business.longitude!);
      _mapController.move(businessLocation, 15.0);
    }

    _searchController.clear();
    ref.read(businessSearchProvider.notifier).searchBusinesses('');
  }

  Future<void> _checkLocationPermission() async {
    if (_locationPermissionChecked) return;

    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Location services are disabled. Please enable them.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permissions are denied'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permissions are permanently denied'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    _locationPermissionChecked = true;
  }

  Future<void> _startNavigation(LatLng destination) async {
    final mapState = ref.read(mapProvider);

    if (mapState.currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Current location not available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await ref.read(mapProvider.notifier).startNavigation(destination);
    _fitMapToRoute();
    _startLocationTracking();
  }

  void _fitMapToRoute() {
    final mapState = ref.read(mapProvider);
    if (mapState.routePoints.isEmpty) return;

    double minLat = mapState.routePoints.first.latitude;
    double maxLat = mapState.routePoints.first.latitude;
    double minLng = mapState.routePoints.first.longitude;
    double maxLng = mapState.routePoints.first.longitude;

    for (var point in mapState.routePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    final bounds = LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  void _startLocationTracking() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    );

    _positionStream?.listen((Position position) {
      final mapState = ref.read(mapProvider);
      final currentPos = LatLng(position.latitude, position.longitude);

      ref.read(mapProvider.notifier).updateLocation(currentPos);

      if (mapState.isNavigating) {
        _mapController.move(currentPos, 17.0);

        if (mapState.destination != null) {
          final distance = const Distance().as(
            LengthUnit.Meter,
            currentPos,
            mapState.destination!,
          );

          if (distance < 20) {
            _stopNavigation();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('You have arrived at your destination!'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          }
        }

        _checkRouteDeviation(currentPos);
      }
    });
  }

  void _checkRouteDeviation(LatLng currentPos) {
    final mapState = ref.read(mapProvider);
    if (mapState.routePoints.isEmpty || mapState.destination == null) return;

    double minDistance = double.infinity;
    for (var point in mapState.routePoints) {
      final distance = const Distance().as(LengthUnit.Meter, currentPos, point);
      if (distance < minDistance) {
        minDistance = distance;
      }
    }

    if (minDistance > 50) {
      ref.read(mapProvider.notifier).updateNavigationRoute(
            currentPos,
            mapState.destination!,
          );
    }
  }

  void _stopNavigation() {
    ref.read(mapProvider.notifier).stopNavigation();
  }

  void _navigateToBusinessProfile(BusinessModel business) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserBusinessProfileScreen(
          businessId: business.id,
        ),
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    } else {
      final km = meters / 1000;
      return '${km.toStringAsFixed(1)} km';
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapState = ref.watch(mapProvider);
    final businessesState = ref.watch(businessListProvider);
    final businessSearchState = ref.watch(businessSearchProvider);
    final placeResults = ref.watch(placesSearchProvider);
    final isDarkMode = ref.watch(themeProvider);

    final businesses = businessesState.maybeWhen(
      data: (data) => data,
      orElse: () => <BusinessModel>[],
    );

    final searchResults = businessSearchState.maybeWhen(
      data: (data) => data,
      orElse: () => <BusinessModel>[],
    );

    return Scaffold(
      appBar: mapState.isNavigating
          ? null
          : AppBar(
              title: const Text(
                'Explore Map',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              backgroundColor:
                  isDarkMode ? Colors.grey[900] : AppColors.primaryColor,
              elevation: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.my_location, color: Colors.white),
                  onPressed: () async {
                    await _checkLocationPermission();
                    ref.read(mapProvider.notifier).refreshLocation();
                    if (mapState.currentLocation != null) {
                      _mapController.move(
                        mapState.currentLocation!.position,
                        15.0,
                      );
                    }
                  },
                ),
              ],
            ),
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: mapState.currentLocation?.position ??
                  const LatLng(36.8065, 10.1815),
              initialZoom: 15.0,
              onTap: (_, point) {
                if (!mapState.isNavigating) {
                  ref.read(mapProvider.notifier).onMapTap(point);
                  _showDirectionsPopup(point);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.pfe1',
              ),
              if (mapState.routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: mapState.routePoints,
                      strokeWidth: 6.0,
                      color: AppColors.primaryColor,
                      borderColor: Colors.white,
                      borderStrokeWidth: 2.0,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (mapState.currentLocation != null)
                    Marker(
                      point: mapState.currentLocation!.position,
                      width: 80,
                      height: 80,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 5,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: _profileImageUrl != null
                                  ? Image.network(
                                      _profileImageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) => Icon(
                                        mapState.isNavigating
                                            ? Icons.navigation
                                            : Icons.location_on,
                                        color: Colors.blue,
                                        size: 24,
                                      ),
                                    )
                                  : Icon(
                                      mapState.isNavigating
                                          ? Icons.navigation
                                          : Icons.location_on,
                                      color: Colors.blue,
                                      size: 24,
                                    ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (!mapState.isNavigating)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Text(
                                'My Location',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (mapState.isNavigating && mapState.destination != null)
                    Marker(
                      point: mapState.destination!,
                      width: 80,
                      height: 80,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_on, color: Colors.red, size: 40),
                          Text(
                            'Destination',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              color: Colors.red,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!mapState.isNavigating &&
                      mapState.selectedLocation != null)
                    Marker(
                      point: mapState.selectedLocation!.position,
                      width: 80,
                      height: 80,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 5,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.place,
                              color: Colors.redAccent,
                              size: 40,
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                            child: const Text(
                              'Selected',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!mapState.isNavigating)
                    ...businesses
                        .where((b) => b.latitude != null && b.longitude != null)
                        .map((business) => Marker(
                              point: LatLng(
                                  business.latitude!, business.longitude!),
                              width: 80,
                              height: 80,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () =>
                                        _navigateToBusinessProfile(business),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.2),
                                            blurRadius: 5,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                      child: ClipOval(
                                        child: business.imageUrl != null
                                            ? Image.network(
                                                business.imageUrl!,
                                                width: 40,
                                                height: 40,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error,
                                                        stackTrace) =>
                                                    const Icon(
                                                  Icons.business,
                                                  color: AppColors.primaryColor,
                                                  size: 32,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.business,
                                                color: AppColors.primaryColor,
                                                size: 32,
                                              ),
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () =>
                                        _navigateToBusinessProfile(business),
                                    child: Container(
                                      margin: const EdgeInsets.only(top: 2),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.9),
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.1),
                                            blurRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        business.businessName.length > 15
                                            ? '${business.businessName.substring(0, 15)}...'
                                            : business.businessName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                          color: AppColors.primaryColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                ],
              ),
            ],
          ),

          // Navigation panel
          if (mapState.isNavigating)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.grey[900] : AppColors.primaryColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (mapState.totalDistance != null)
                                  Text(
                                    _formatDistance(mapState.totalDistance!),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                if (mapState.estimatedTime != null)
                                  Text(
                                    '${(mapState.estimatedTime! / 60).round()} min',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 16,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 28,
                            ),
                            onPressed: _stopNavigation,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.navigation,
                              color: Colors.white,
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                mapState.currentInstruction.isNotEmpty
                                    ? mapState.currentInstruction
                                    : 'Follow the route',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
// Search bar
          if (!mapState.isNavigating)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          spreadRadius: 1,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search for places, businesses...',
                        prefixIcon: const Icon(Icons.search,
                            color: AppColors.primaryColor),
                        suffixIcon: _isSearching
                            ? Container(
                                width: 24,
                                height: 24,
                                padding: const EdgeInsets.all(6),
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      AppColors.primaryColor),
                                ),
                              )
                            : IconButton(
                                icon:
                                    const Icon(Icons.clear, color: Colors.grey),
                                onPressed: () {
                                  _searchController.clear();
                                  ref
                                      .read(businessSearchProvider.notifier)
                                      .searchBusinesses('');
                                  ref
                                      .read(placesSearchProvider.notifier)
                                      .clear();
                                },
                              ),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 15),
                      ),
                      onSubmitted: _searchPlace,
                    ),
                  ),
                  if (searchResults.isNotEmpty || placeResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      constraints: const BoxConstraints(maxHeight: 300),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            spreadRadius: 1,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          // Places section
                          if (placeResults.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                'Places',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                            ...placeResults.map((place) => ListTile(
                                  leading: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Icon(
                                      Icons.place,
                                      color: Colors.green,
                                    ),
                                  ),
                                  title: Text(
                                    place.displayName.split(',').first,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    place.displayName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  onTap: () => _onPlaceSelected(place),
                                )),
                            if (searchResults.isNotEmpty)
                              Divider(color: Colors.grey[300], height: 1),
                          ],

                          // Businesses section
                          if (searchResults.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                'Businesses',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                            ...searchResults.map((business) => ListTile(
                                  leading: business.imageUrl != null
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          child: Image.network(
                                            business.imageUrl!,
                                            width: 40,
                                            height: 40,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade300,
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: const Icon(Icons.business,
                                                  color: Colors.grey),
                                            ),
                                          ),
                                        )
                                      : Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade300,
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: const Icon(Icons.business,
                                              color: Colors.grey),
                                        ),
                                  title: Text(
                                    business.businessName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(business.email ?? 'No email'),
                                  onTap: () => _onBusinessSelected(business),
                                )),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          // Business details
          if (!mapState.isNavigating && _selectedBusiness != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.grey[800] : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () =>
                              _navigateToBusinessProfile(_selectedBusiness!),
                          child: _selectedBusiness!.imageUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    _selectedBusiness!.imageUrl!,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade300,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.business,
                                          color: Colors.grey, size: 30),
                                    ),
                                  ),
                                )
                              : Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade300,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.business,
                                      color: Colors.grey, size: 30),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () => _navigateToBusinessProfile(
                                    _selectedBusiness!),
                                child: Text(
                                  _selectedBusiness!.businessName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: isDarkMode
                                        ? Colors.white
                                        : AppColors.primaryColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _selectedBusiness!.email ?? 'No email',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDarkMode
                                      ? Colors.grey[300]
                                      : Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () {
                            setState(() => _selectedBusiness = null);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        if (_selectedBusiness!.latitude != null &&
                            _selectedBusiness!.longitude != null) {
                          final destination = LatLng(
                            _selectedBusiness!.latitude!,
                            _selectedBusiness!.longitude!,
                          );
                          _startNavigation(destination);
                          setState(() => _selectedBusiness = null);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Cannot navigate to this business'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        minimumSize: const Size(double.infinity, 0),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.navigation),
                          SizedBox(width: 8),
                          Text(
                            'Start Navigation',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showDirectionsPopup(LatLng point) {
    final mapState = ref.read(mapProvider);
    if (mapState.currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your current location is not available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final isDarkMode = ref.read(themeProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.grey[800] : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.place,
                        color: AppColors.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Selected Location',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isDarkMode ? Colors.white : Colors.black,
                          ),
                        ),
                        Text(
                          '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode
                                ? Colors.grey[300]
                                : Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _startNavigation(point);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                minimumSize: const Size(double.infinity, 0),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.navigation),
                  SizedBox(width: 8),
                  Text(
                    'Start Navigation',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
