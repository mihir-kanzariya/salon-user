import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/i18n/locale_provider.dart';
import '../../../../core/utils/storage_service.dart';

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isDetecting = false;
  List<_CityOption> _searchResults = [];

  static const List<_CityOption> _popularCities = [
    _CityOption(name: 'Ahmedabad', lat: 23.0225, lng: 72.5714),
    _CityOption(name: 'Mumbai', lat: 19.0760, lng: 72.8777),
    _CityOption(name: 'Delhi', lat: 28.7041, lng: 77.1025),
    _CityOption(name: 'Bangalore', lat: 12.9716, lng: 77.5946),
    _CityOption(name: 'Pune', lat: 18.5204, lng: 73.8567),
    _CityOption(name: 'Surat', lat: 21.1702, lng: 72.8311),
  ];

  Future<void> _useCurrentLocation() async {
    setState(() => _isDetecting = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _isDetecting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied')),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );

      String cityName = 'Current Location';
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          cityName = placemarks.first.locality ??
              placemarks.first.subAdministrativeArea ??
              'Current Location';
        }
      } catch (_) {}

      await _selectLocation(position.latitude, position.longitude, cityName);
    } catch (e) {
      debugPrint('[Location] Error: $e');
      if (mounted) {
        setState(() => _isDetecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not detect location')),
        );
      }
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _searchCity(query.trim());
    });
  }

  Future<void> _searchCity(String query) async {
    try {
      final locations = await locationFromAddress(query);
      if (locations.isNotEmpty && mounted) {
        String cityName = query;
        try {
          final placemarks = await placemarkFromCoordinates(
            locations.first.latitude,
            locations.first.longitude,
          );
          if (placemarks.isNotEmpty) {
            cityName = placemarks.first.locality ??
                placemarks.first.subAdministrativeArea ??
                query;
          }
        } catch (_) {}

        setState(() {
          _searchResults = [
            _CityOption(
              name: cityName,
              lat: locations.first.latitude,
              lng: locations.first.longitude,
            ),
          ];
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _searchResults = []);
      }
    }
  }

  Future<void> _selectLocation(double lat, double lng, String cityName) async {
    await StorageService().saveLocation(lat, lng, cityName);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),

              // Header
              Text(
                locale.tr('set_location'),
                style: AppTextStyles.h1,
              ),
              const SizedBox(height: 8),
              Text(
                locale.tr('location_subtitle'),
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),

              const SizedBox(height: 32),

              // Use Current Location button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isDetecting ? null : _useCurrentLocation,
                  icon: _isDetecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : const Text(
                          '\u{1F4CD}',
                          style: TextStyle(fontSize: 18),
                        ),
                  label: Text(
                    _isDetecting
                        ? locale.tr('detecting_location')
                        : locale.tr('use_current_location'),
                    style: AppTextStyles.button,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Divider
              Row(
                children: [
                  const Expanded(child: Divider(color: AppColors.border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'or',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider(color: AppColors.border)),
                ],
              ),

              const SizedBox(height: 24),

              // Search field
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: AppTextStyles.bodyLarge,
                decoration: InputDecoration(
                  hintText: locale.tr('search_city'),
                  hintStyle: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textMuted,
                  ),
                  prefixIcon:
                      const Icon(Icons.search, color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),

              // Search results
              if (_searchResults.isNotEmpty) ...[
                const SizedBox(height: 8),
                ..._searchResults.map(
                  (city) => ListTile(
                    leading: const Icon(Icons.location_on_outlined,
                        color: AppColors.primary),
                    title: Text(city.name, style: AppTextStyles.bodyLarge),
                    onTap: () =>
                        _selectLocation(city.lat, city.lng, city.name),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Popular cities
              Text(
                locale.tr('popular_cities'),
                style: AppTextStyles.h3,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _popularCities
                    .map(
                      (city) => GestureDetector(
                        onTap: () => _selectLocation(
                            city.lat, city.lng, city.name),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(20),
                            border:
                                Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            city.name,
                            style: AppTextStyles.labelLarge.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CityOption {
  final String name;
  final double lat;
  final double lng;

  const _CityOption({
    required this.name,
    required this.lat,
    required this.lng,
  });
}
