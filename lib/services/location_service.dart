import 'package:dio/dio.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../config/api_config.dart';
import '../network/api_client.dart';

class LocationResult {
  final String city;
  final String? country;

  const LocationResult({required this.city, this.country});
}

class LocationService {
  final ApiClient _client = apiClient;

  Future<bool> ensurePermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  Future<LocationResult?> resolveCurrentCity() async {
    final ok = await ensurePermission();
    if (!ok) return null;

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 20),
      ),
    );

    final places = await placemarkFromCoordinates(pos.latitude, pos.longitude);
    if (places.isEmpty) return null;
    final p = places.first;
    final city = (p.locality?.isNotEmpty == true
            ? p.locality
            : p.subAdministrativeArea?.isNotEmpty == true
                ? p.subAdministrativeArea
                : p.administrativeArea) ??
        '';
    if (city.trim().isEmpty) return null;
    return LocationResult(
      city: city.trim(),
      country: p.country?.trim().isNotEmpty == true ? p.country!.trim() : null,
    );
  }

  Future<Map<String, dynamic>> updateProfileLocation({
    required String city,
    String? country,
    required bool locationOptIn,
  }) async {
    final resp = await _client.put(
      ApiConfig.profileLocation,
      data: {
        'city': city.trim(),
        if (country != null && country.trim().isNotEmpty) 'country': country.trim(),
        'location_opt_in': locationOptIn,
      },
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException(_messageFrom(resp), status);
    }
    final data = resp.data;
    if (data is Map && data[ApiConfig.dataKey] is Map) {
      return Map<String, dynamic>.from(data[ApiConfig.dataKey] as Map);
    }
    if (data is Map<String, dynamic>) return data;
    return {};
  }

  Future<List<({String code, String name})>> getCountries() async {
    final resp = await _client.get(
      ApiConfig.locationsCountries,
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final map = _unwrap(resp);
    final raw = map['countries'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => (
              code: (e['code'] ?? '').toString(),
              name: (e['name'] ?? '').toString(),
            ))
        .where((e) => e.name.isNotEmpty)
        .toList();
  }

  Future<List<String>> getCities(String country) async {
    final resp = await _client.get(
      ApiConfig.locationsCities,
      queryParameters: {'country': country},
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final map = _unwrap(resp);
    final raw = map['cities'];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }

  Map<String, dynamic> _unwrap(Response resp) {
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException(_messageFrom(resp), status);
    }
    final data = resp.data;
    if (data is Map && data[ApiConfig.dataKey] is Map) {
      return Map<String, dynamic>.from(data[ApiConfig.dataKey] as Map);
    }
    if (data is Map<String, dynamic>) return data;
    throw ApiException('Invalid response from server', status);
  }

  String _messageFrom(Response resp) {
    final body = resp.data;
    if (body is Map) {
      if (body[ApiConfig.messageKey] is String) return body[ApiConfig.messageKey] as String;
      final err = body[ApiConfig.errorKey];
      if (err is String) return err;
    }
    return resp.statusMessage ?? 'Request failed';
  }
}
