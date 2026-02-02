import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:latlong2/latlong.dart';

class DirectionsService {
  // OpenRouteService API
  static const String _baseUrl =
      'https://api.openrouteservice.org/v2/directions/driving-car/geojson';
  static const String _apiKey =
      'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6ImY1ZjZhOGVjMTVmYjQ3OTM4YjMwODk4NTA3OGZlOTRhIiwiaCI6Im11cm11cjY0In0='; // Free OpenRouteService API key

  Future<List<LatLng>> getRouteCoordinates(
      LatLng origin, LatLng destination) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Authorization': _apiKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'coordinates': [
            [origin.longitude, origin.latitude],
            [destination.longitude, destination.latitude]
          ],
          'instructions': false
        }),
      );

      debugPrint('ORS STATUS: ${response.statusCode}');
      debugPrint('ORS BODY: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final coordinates =
            data['features'][0]['geometry']['coordinates'] as List;

        return coordinates
            .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
            .toList();
      } else {
        throw Exception('ORS error ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting route: $e');
      return [origin, destination];
    }
  }

  // Get detailed route information including distance, time, and instructions
  Future<Map<String, dynamic>> getDetailedRoute(
      LatLng origin, LatLng destination) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': _apiKey,
        },
        body: json.encode({
          'coordinates': [
            [origin.longitude, origin.latitude],
            [destination.longitude, destination.latitude]
          ],
          'format': 'geojson',
          'instructions': true, // Request turn-by-turn instructions
          'units': 'm' // Use meters for distance
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final feature = data['features'][0];

        // Extract coordinates from GeoJSON
        final coordinates = feature['geometry']['coordinates'] as List;
        final routePoints = coordinates
            .map((coord) => LatLng(coord[1] as double, coord[0] as double))
            .toList();

        // Extract route summary
        final properties = feature['properties'];
        final summary = properties['summary'];
        final segments = properties['segments'] as List;

        final totalDistance = summary['distance']?.toDouble(); // in meters
        final estimatedTime = summary['duration']?.toInt(); // in seconds

        // Get first instruction
        String firstInstruction = 'Head to destination';
        if (segments.isNotEmpty && segments[0]['steps'] != null) {
          final steps = segments[0]['steps'] as List;
          if (steps.isNotEmpty) {
            firstInstruction = steps[0]['instruction'] ?? 'Head to destination';
          }
        }

        return {
          'routePoints': routePoints,
          'totalDistance': totalDistance,
          'estimatedTime': estimatedTime,
          'firstInstruction': firstInstruction,
          'rawData': feature, // Include raw data for advanced usage
        };
      } else {
        debugPrint(
            'Failed to fetch detailed route: ${response.statusCode}, ${response.body}');
        // Return fallback data
        return {
          'routePoints': [origin, destination],
          'totalDistance': _calculateStraightLineDistance(origin, destination),
          'estimatedTime': null,
          'firstInstruction': 'Route not available',
          'rawData': null,
        };
      }
    } catch (e) {
      debugPrint('Error fetching detailed route: $e');
      return {
        'routePoints': [origin, destination],
        'totalDistance': _calculateStraightLineDistance(origin, destination),
        'estimatedTime': null,
        'firstInstruction': 'Error getting route',
        'rawData': null,
      };
    }
  }

  // Get turn-by-turn instructions
  Future<List<Map<String, dynamic>>> getTurnByTurnInstructions(
      LatLng origin, LatLng destination) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': _apiKey,
        },
        body: json.encode({
          'coordinates': [
            [origin.longitude, origin.latitude],
            [destination.longitude, destination.latitude]
          ],
          'format': 'geojson',
          'instructions': true,
          'units': 'm'
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final feature = data['features'][0];
        final properties = feature['properties'];
        final segments = properties['segments'] as List;

        final List<Map<String, dynamic>> instructions = [];

        if (segments.isNotEmpty && segments[0]['steps'] != null) {
          final steps = segments[0]['steps'] as List;

          for (var step in steps) {
            // Get the location for this step
            final wayPoints = step['way_points'] as List;
            final startIndex = wayPoints[0] as int;

            // Get coordinates from the geometry
            final coordinates = feature['geometry']['coordinates'] as List;
            final coord = coordinates[startIndex];

            instructions.add({
              'instruction': step['instruction'] ?? '',
              'distance': step['distance']?.toDouble() ?? 0.0,
              'duration': step['duration']?.toDouble() ?? 0.0,
              'location': LatLng(coord[1] as double, coord[0] as double),
              'type': step['type'] ?? 0,
              'name': step['name'] ?? '',
            });
          }
        }

        return instructions;
      } else {
        debugPrint(
            'Failed to fetch instructions: ${response.statusCode}, ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('Error getting turn-by-turn instructions: $e');
      return [];
    }
  }

  // Calculate if the user has deviated from the route
  bool hasDeviatedFromRoute(LatLng currentPosition, List<LatLng> routePoints,
      double thresholdMeters) {
    if (routePoints.isEmpty) return false;

    final distance = Distance();
    double minDistance = double.infinity;

    for (var point in routePoints) {
      final dist = distance.as(LengthUnit.Meter, currentPosition, point);
      if (dist < minDistance) {
        minDistance = dist;
      }
    }

    return minDistance > thresholdMeters;
  }

  // Get the next instruction based on current position
  Future<String?> getNextInstruction(
      LatLng currentPosition, LatLng destination) async {
    try {
      final instructions =
          await getTurnByTurnInstructions(currentPosition, destination);

      if (instructions.isNotEmpty) {
        // Find the closest upcoming instruction
        final distance = Distance();
        double minDistance = double.infinity;
        String? nextInstruction;

        for (var instruction in instructions) {
          final dist = distance.as(
              LengthUnit.Meter, currentPosition, instruction['location']);
          if (dist < minDistance && dist > 5) {
            // Only consider instructions at least 5m ahead
            minDistance = dist;
            nextInstruction = instruction['instruction'];
          }
        }

        return nextInstruction;
      }

      return null;
    } catch (e) {
      debugPrint('Error getting next instruction: $e');
      return null;
    }
  }

  // Calculate distance to destination
  double getDistanceToDestination(LatLng currentPosition, LatLng destination) {
    final distance = Distance();
    return distance.as(LengthUnit.Meter, currentPosition, destination);
  }

  // Private helper: Calculate straight line distance
  double _calculateStraightLineDistance(LatLng origin, LatLng destination) {
    final distance = Distance();
    return distance.as(LengthUnit.Meter, origin, destination);
  }

  // Format distance for display
  String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    } else {
      final km = meters / 1000;
      return '${km.toStringAsFixed(1)} km';
    }
  }

  // Format duration for display
  String formatDuration(int seconds) {
    if (seconds < 60) {
      return '$seconds sec';
    } else if (seconds < 3600) {
      final minutes = (seconds / 60).round();
      return '$minutes min';
    } else {
      final hours = (seconds / 3600).floor();
      final minutes = ((seconds % 3600) / 60).round();
      return '$hours hr $minutes min';
    }
  }
}
