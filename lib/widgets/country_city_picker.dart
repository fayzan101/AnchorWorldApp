import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';

import '../services/location_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Country-first then city picker backed by `/locations/*`.
class CountryCityPicker extends StatefulWidget {
  final String? initialCountry;
  final String? initialCity;
  final ValueChanged<String?> onCountryChanged;
  final ValueChanged<String?> onCityChanged;

  const CountryCityPicker({
    super.key,
    this.initialCountry,
    this.initialCity,
    required this.onCountryChanged,
    required this.onCityChanged,
  });

  @override
  State<CountryCityPicker> createState() => _CountryCityPickerState();
}

class _CountryCityPickerState extends State<CountryCityPicker> {
  final _service = LocationService();
  final _countrySearchCtrl = TextEditingController();
  final _citySearchCtrl = TextEditingController();

  List<({String code, String name})> _countries = [];
  List<String> _cities = [];
  String? _country;
  String? _city;
  bool _loadingCountries = true;
  bool _loadingCities = false;

  @override
  void initState() {
    super.initState();
    _country = widget.initialCountry;
    _city = widget.initialCity;
    _loadCountries();
  }

  @override
  void dispose() {
    _countrySearchCtrl.dispose();
    _citySearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCountries() async {
    try {
      final list = await _service.getCountries();
      if (!mounted) return;
      setState(() {
        _countries = list;
        _loadingCountries = false;
      });
      if (_country != null && _country!.isNotEmpty) {
        await _loadCities(_country!);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCountries = false);
    }
  }

  Future<void> _loadCities(String country) async {
    setState(() => _loadingCities = true);
    try {
      final cities = await _service.getCities(country);
      if (!mounted) return;
      setState(() {
        _cities = cities;
        _loadingCities = false;
        if (_city != null && !cities.contains(_city)) {
          _city = null;
          widget.onCityChanged(null);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCities = false);
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    required IconData icon,
    required bool loading,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: AppColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      prefixIcon: Container(
        margin: const EdgeInsets.only(left: 12, right: 8),
        child: Icon(icon, color: AppColors.primary, size: 22),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      suffixIcon: loading
          ? const SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppColors.primary,
                  ),
                ),
              ),
            )
          : const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.body),
      suffixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      labelStyle: AppTextStyles.ui(size: 13, weight: FontWeight.w700, color: AppColors.primaryDeep),
      hintStyle: AppTextStyles.ui(size: 14, color: AppColors.body.withOpacity(0.55)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.mutedBorder, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: AppColors.mutedBorder.withOpacity(0.7)),
      ),
    );
  }

  Widget _shell({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final countryValue = _countries.any((c) => c.name == _country) ? _country : null;
    final cityValue = _cities.contains(_city) ? _city : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _shell(
          child: DropdownButtonFormField2<String>(
            value: countryValue,
            isExpanded: true,
            decoration: _fieldDecoration(
              label: 'Country',
              hint: 'Select country first',
              icon: Icons.public_rounded,
              loading: _loadingCountries,
            ),
            iconStyleData: const IconStyleData(icon: SizedBox.shrink()),
            hint: Text('Select country', style: AppTextStyles.ui(size: 15, color: AppColors.body.withOpacity(0.55))),
            style: AppTextStyles.ui(size: 15, weight: FontWeight.w600),
            dropdownStyleData: DropdownStyleData(
              maxHeight: 340,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ink.withOpacity(0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
            ),
            dropdownSearchData: DropdownSearchData(
              searchController: _countrySearchCtrl,
              searchInnerWidgetHeight: 52,
              searchInnerWidget: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: TextField(
                  controller: _countrySearchCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search countries…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.primary),
                    filled: true,
                    fillColor: AppColors.chipIdle,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              searchMatchFn: (item, searchValue) {
                final v = (item.value ?? '').toLowerCase();
                return v.contains(searchValue.toLowerCase());
              },
            ),
            onMenuStateChange: (isOpen) {
              if (!isOpen) _countrySearchCtrl.clear();
            },
            items: _countries
                .map(
                  (c) => DropdownMenuItem(
                    value: c.name,
                    child: Text(c.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: _loadingCountries
                ? null
                : (v) async {
                    setState(() {
                      _country = v;
                      _city = null;
                    });
                    widget.onCountryChanged(v);
                    widget.onCityChanged(null);
                    if (v != null) await _loadCities(v);
                  },
          ),
        ),
        const SizedBox(height: 16),
        _shell(
          child: DropdownButtonFormField2<String>(
            value: cityValue,
            isExpanded: true,
            decoration: _fieldDecoration(
              label: 'City',
              hint: _country == null ? 'Select a country first' : 'Select city',
              icon: Icons.location_city_rounded,
              loading: _loadingCities,
            ),
            iconStyleData: const IconStyleData(icon: SizedBox.shrink()),
            hint: Text(
              _country == null ? 'Select a country first' : 'Select city',
              style: AppTextStyles.ui(size: 15, color: AppColors.body.withOpacity(0.55)),
            ),
            style: AppTextStyles.ui(size: 15, weight: FontWeight.w600),
            dropdownStyleData: DropdownStyleData(
              maxHeight: 340,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ink.withOpacity(0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
            ),
            dropdownSearchData: _country == null || _cities.isEmpty
                ? null
                : DropdownSearchData(
                    searchController: _citySearchCtrl,
                    searchInnerWidgetHeight: 52,
                    searchInnerWidget: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: TextField(
                        controller: _citySearchCtrl,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Search cities…',
                          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.primary),
                          filled: true,
                          fillColor: AppColors.chipIdle,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    searchMatchFn: (item, searchValue) {
                      final v = (item.value ?? '').toLowerCase();
                      return v.contains(searchValue.toLowerCase());
                    },
                  ),
            onMenuStateChange: (isOpen) {
              if (!isOpen) _citySearchCtrl.clear();
            },
            items: _cities
                .map(
                  (city) => DropdownMenuItem(
                    value: city,
                    child: Text(city, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (_country == null || _loadingCities)
                ? null
                : (v) {
                    setState(() => _city = v);
                    widget.onCityChanged(v);
                  },
          ),
        ),
      ],
    );
  }
}
