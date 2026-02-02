import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../domain/location_model.dart';
import 'map_service.dart';
import 'directions_service.dart';

// Provider for the MapService
final mapServiceProvider = Provider<MapService>((ref) {
  return MapService();
});

// Provider for the DirectionsService
final directionsServiceProvider = Provider<DirectionsService>((ref) {
  return DirectionsService();
});

// State class for the map
class MapState {
  final LocationModel? currentLocation;
  final LocationModel? selectedLocation;
  final List<LatLng> routePoints;
  final bool isLoading;
  final String? error;

  // Navigation-specific state
  final bool isNavigating;
  final double? totalDistance;
  final int? estimatedTime;
  final String currentInstruction;
  final LatLng? destination;

  MapState({
    this.currentLocation,
    this.selectedLocation,
    this.routePoints = const [],
    this.isLoading = false,
    this.error,
    this.isNavigating = false,
    this.totalDistance,
    this.estimatedTime,
    this.currentInstruction = '',
    this.destination,
  });

  MapState copyWith({
    LocationModel? currentLocation,
    LocationModel? selectedLocation,
    List<LatLng>? routePoints,
    bool? isLoading,
    String? error,
    bool? isNavigating,
    double? totalDistance,
    int? estimatedTime,
    String? currentInstruction,
    LatLng? destination,
    bool clearDestination = false,
  }) {
    return MapState(
      currentLocation: currentLocation ?? this.currentLocation,
      selectedLocation: selectedLocation ?? this.selectedLocation,
      routePoints: routePoints ?? this.routePoints,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      isNavigating: isNavigating ?? this.isNavigating,
      totalDistance: totalDistance ?? this.totalDistance,
      estimatedTime: estimatedTime ?? this.estimatedTime,
      currentInstruction: currentInstruction ?? this.currentInstruction,
      destination: clearDestination ? null : (destination ?? this.destination),
    );
  }
}

// Notifier for the map state
class MapNotifier extends StateNotifier<MapState> {
  final MapService _mapService;
  final DirectionsService _directionsService;

  MapNotifier(this._mapService, this._directionsService) : super(MapState());

  // Initialize the map with current location
  Future<void> initializeMap() async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      final currentLocation = await _mapService.getCurrentLocation();

      if (currentLocation == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'Could not get current location',
        );
        return;
      }

      state = state.copyWith(
        currentLocation: currentLocation,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Error initializing map: $e',
      );
    }
  }

  // Handle tap on map
  Future<void> onMapTap(LatLng tappedPoint) async {
    if (state.currentLocation == null) return;

    // Don't handle taps during navigation
    if (state.isNavigating) return;

    state = state.copyWith(isLoading: true, error: null);
    try {
      final distance = _mapService.calculateDistance(
        state.currentLocation!.position,
        tappedPoint,
      );
      final selectedLocation = LocationModel(
        position: tappedPoint,
        name: 'Selected Location',
        distance: distance,
      );
      // Get route between current location and tapped point
      final routePoints = await _directionsService.getRouteCoordinates(
        state.currentLocation!.position,
        tappedPoint,
      );
      state = state.copyWith(
        selectedLocation: selectedLocation,
        routePoints: routePoints,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        error: 'Error getting route: $e',
        isLoading: false,
      );
    }
  }

  // Refresh current location
  Future<void> refreshLocation() async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      final currentLocation = await _mapService.getCurrentLocation();

      if (currentLocation == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'Could not get current location',
        );
        return;
      }

      // If there's a selected location, recalculate distance and route
      LocationModel? updatedSelectedLocation;
      List<LatLng>? updatedRoutePoints;

      if (state.selectedLocation != null) {
        final distance = _mapService.calculateDistance(
          currentLocation.position,
          state.selectedLocation!.position,
        );

        updatedSelectedLocation = state.selectedLocation!.copyWith(
          distance: distance,
        );

        // Update route
        updatedRoutePoints = await _directionsService.getRouteCoordinates(
          currentLocation.position,
          state.selectedLocation!.position,
        );
      }

      state = state.copyWith(
        currentLocation: currentLocation,
        selectedLocation: updatedSelectedLocation,
        routePoints: updatedRoutePoints,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Error refreshing location: $e',
      );
    }
  }

  // Update location during navigation (called by position stream)
  void updateLocation(LatLng position) {
    if (state.currentLocation == null) return;

    final updatedLocation = LocationModel(
      position: position,
      name: state.currentLocation!.name,
      distance: state.currentLocation!.distance,
    );

    state = state.copyWith(currentLocation: updatedLocation);
  }

  // Start navigation to a destination
  Future<void> startNavigation(LatLng destination) async {
    if (state.currentLocation == null) return;

    try {
      state = state.copyWith(isLoading: true, error: null);

      // Fetch route with detailed information
      final routeData = await _directionsService.getDetailedRoute(
        state.currentLocation!.position,
        destination,
      );

      state = state.copyWith(
        isNavigating: true,
        destination: destination,
        routePoints: routeData['routePoints'] as List<LatLng>,
        totalDistance: routeData['totalDistance'] as double?,
        estimatedTime: routeData['estimatedTime'] as int?,
        currentInstruction:
            routeData['firstInstruction'] as String? ?? 'Head to destination',
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Error starting navigation: $e',
      );
    }
  }

  // Update route during navigation (for recalculation)
  Future<void> updateNavigationRoute(
      LatLng currentPosition, LatLng destination) async {
    try {
      final routeData = await _directionsService.getDetailedRoute(
        currentPosition,
        destination,
      );

      state = state.copyWith(
        routePoints: routeData['routePoints'] as List<LatLng>,
        totalDistance: routeData['totalDistance'] as double?,
        estimatedTime: routeData['estimatedTime'] as int?,
        currentInstruction:
            routeData['firstInstruction'] as String? ?? 'Head to destination',
      );
    } catch (e) {
      state = state.copyWith(
        error: 'Error updating route: $e',
      );
    }
  }

  // Stop navigation
  void stopNavigation() {
    state = state.copyWith(
      isNavigating: false,
      routePoints: [],
      totalDistance: null,
      estimatedTime: null,
      currentInstruction: '',
      clearDestination: true,
    );
  }

  // Clear selected location
  void clearSelectedLocation() {
    state = state.copyWith(
      selectedLocation: null,
      routePoints: [],
    );
  }
}

// Provider for the map state
final mapProvider = StateNotifierProvider<MapNotifier, MapState>((ref) {
  final mapService = ref.watch(mapServiceProvider);
  final directionsService = ref.watch(directionsServiceProvider);
  return MapNotifier(mapService, directionsService);
});
