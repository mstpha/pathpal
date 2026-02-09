import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class PlaceResult {
  final String displayName;
  final LatLng location;
  final String type;

  PlaceResult({
    required this.displayName,
    required this.location,
    required this.type,
  });

  factory PlaceResult.fromJson(Map<String, dynamic> json) {
    return PlaceResult(
      displayName: json['display_name'] ?? '',
      location: LatLng(
        double.parse(json['lat']),
        double.parse(json['lon']),
      ),
      type: json['type'] ?? 'place',
    );
  }
}

class PlacesSearchService {
  static const String _baseUrl = 'https://nominatim.openstreetmap.org';

  Future<List<PlaceResult>> searchPlaces(String query) async {
    if (query.isEmpty) return [];

    try {
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/search?q=$query&format=json&limit=5&addressdetails=1',
        ),
        headers: {
          'User-Agent': 'PathPal/1.0', // Required by Nominatim
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => PlaceResult.fromJson(json)).toList();
      } else {
        throw Exception('Failed to search places: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error searching places: $e');
    }
  }
}
