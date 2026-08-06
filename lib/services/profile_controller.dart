import 'package:flutter/foundation.dart';

import '../models/profile.dart';
import 'auth_service.dart';
class ProfileController extends ChangeNotifier {
  static final ProfileController _instance = ProfileController._internal();
  factory ProfileController() => _instance;
  ProfileController._internal();

  Profile? _profile;
  bool _loading = false;
  String? _error;

  Profile? get profile => _profile;
  bool get loading => _loading;
  String? get error => _error;
  Future<void> loadProfile({bool force = false}) async {
    if (!force && _profile != null) return; // use cache
    _loading = true;
    notifyListeners();
    try {
      final map = await AuthService().getProfile(forceRefresh: force);
      _profile = Profile.fromJson(map);
      _error = null;
    } catch (e) {
      _error = e is Exception ? e.toString() : '$e';
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
  Future<void> refresh() => loadProfile(force: true);
  Future<void> refreshQuiet() async {
    try {
      final map = await AuthService().getProfile(forceRefresh: true);
      _profile = Profile.fromJson(map);
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = e is Exception ? e.toString() : '$e';
      notifyListeners();
      rethrow;
    }
  }
  Future<void> updateProfile(Map<String, dynamic> body) async {
    _loading = true;
    notifyListeners();
    try {
      final updated = await AuthService().updateProfile(body);
      _profile = Profile.fromJson(updated);
      _error = null;
    } catch (e) {
      _error = e is Exception ? e.toString() : '$e';
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
  void clearCache() {
    _profile = null;
    _loading = false;
    _error = null;
    notifyListeners();
  }
  void setProfileFromMap(Map<String, dynamic> map) {
    try {
      _profile = Profile.fromJson(map);
      _error = null;
      notifyListeners();
    } catch (_) {}
  }
}
final profileController = ProfileController();
