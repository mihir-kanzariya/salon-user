import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();
  
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  late SharedPreferences _prefs;
  
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }
  
  // Secure storage (tokens)
  Future<void> saveAccessToken(String token) async {
    await _secureStorage.write(key: AppConstants.accessTokenKey, value: token);
  }
  
  Future<String?> getAccessToken() async {
    return await _secureStorage.read(key: AppConstants.accessTokenKey);
  }
  
  Future<void> saveRefreshToken(String token) async {
    await _secureStorage.write(key: AppConstants.refreshTokenKey, value: token);
  }
  
  Future<String?> getRefreshToken() async {
    return await _secureStorage.read(key: AppConstants.refreshTokenKey);
  }
  
  Future<void> clearTokens() async {
    await _secureStorage.delete(key: AppConstants.accessTokenKey);
    await _secureStorage.delete(key: AppConstants.refreshTokenKey);
  }
  
  // SharedPreferences (user data, settings)
  Future<void> saveUser(Map<String, dynamic> user) async {
    await _prefs.setString(AppConstants.userKey, jsonEncode(user));
  }
  
  Map<String, dynamic>? getUser() {
    final data = _prefs.getString(AppConstants.userKey);
    if (data == null) return null;
    return jsonDecode(data) as Map<String, dynamic>;
  }
  
  Future<void> setAppMode(String mode) async {
    await _prefs.setString(AppConstants.appModeKey, mode);
  }
  
  String getAppMode() {
    return _prefs.getString(AppConstants.appModeKey) ?? 'consumer';
  }
  
  // Onboarding
  bool isOnboardingComplete() {
    return _prefs.getBool('onboarding_complete') ?? false;
  }

  Future<void> setOnboardingComplete() async {
    await _prefs.setBool('onboarding_complete', true);
  }

  // Location
  Future<void> saveLocation(double lat, double lng, String cityName) async {
    await _prefs.setDouble('user_lat', lat);
    await _prefs.setDouble('user_lng', lng);
    await _prefs.setString('user_city', cityName);
  }

  Map<String, dynamic>? getLocation() {
    final lat = _prefs.getDouble('user_lat');
    final lng = _prefs.getDouble('user_lng');
    final city = _prefs.getString('user_city');
    if (lat == null || lng == null) return null;
    return {'lat': lat, 'lng': lng, 'city': city ?? ''};
  }

  Future<void> clearAll() async {
    await _secureStorage.deleteAll();
    await _prefs.clear();
  }
}
