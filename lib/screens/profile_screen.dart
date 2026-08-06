import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../services/profile_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/app_caches.dart';
import '../utils/custom_snackbar.dart';
import '../utils/profile_style_codec.dart';
import '../network/api_client.dart' show ApiException;
import '../widgets/country_city_picker.dart';
import '../widgets/interest_tags_chips.dart';
import '../widgets/primary_button.dart';

/// Edit own community profile (photo, bio, topics, participation, location).
class ProfileScreen extends StatefulWidget {
  final String? userId;

  const ProfileScreen({Key? key, this.userId}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _participationStyles = [
    'Share posts and tips',
    'Jump into discussions',
    'Organize group activities',
    'Mostly read and learn',
    'Welcome and help newcomers',
  ];

  static const _communityTones = [
    'Practical and informative',
    'Encouraging and upbeat',
    'Curious and explorative',
    'Straight-talking',
    'Creative and playful',
  ];

  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _profileController = ProfileController();

  List<InterestOption> _topics = [];
  Set<String> _selectedTopicIds = {};
  String? _gender;
  Set<String> _participation = {};
  Set<String> _tone = {};
  String? _country;
  String? _city;
  String? _email;
  bool _locationOptIn = false;
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;
  File? _photoFile;
  String? _photoUrl;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _bioCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  String _uploadsUrl(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final r = raw.trim();
    if (r.startsWith('http')) return r;
    if (r.contains('/uploads/')) {
      final m = RegExp(r'/uploads/(.+)').firstMatch(r);
      final filename = (m != null && m.groupCount >= 1) ? m.group(1)! : r.split('/').last;
      return '${ApiConfig.profilePicture.replaceAll(RegExp(r'/$'), '')}/$filename';
    }
    return '${ApiConfig.profilePicture.replaceAll(RegExp(r'/$'), '')}/${r.split('/').last}';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final hobbiesRaw = await AuthService().getHobbies();
      final topics = <InterestOption>[];
      if (hobbiesRaw is List) {
        for (final item in hobbiesRaw) {
          if (item is Map) {
            final id = (item['id'] ?? '').toString();
            final name = (item['name'] ?? '').toString();
            if (id.isNotEmpty && name.isNotEmpty) {
              topics.add(InterestOption(id: id, label: name));
            }
          }
        }
      }

      Map<String, dynamic> data = AuthService().getCachedProfile() ?? {};
      try {
        // Always refresh when opening edit so form isn't stuck on a stale session cache.
        final resp = await AuthService().getProfile(forceRefresh: true);
        if (resp[ApiConfig.dataKey] is Map) {
          data = Map<String, dynamic>.from(resp[ApiConfig.dataKey] as Map);
        } else if (resp.isNotEmpty) {
          data = Map<String, dynamic>.from(resp);
        }
      } catch (_) {}

      _apply(data, topics: topics);
      if (!mounted) return;
      setState(() {
        _topics = topics;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      customSnackBar('Error', e.toString().replaceAll('ApiException: ', ''), type: SnackType.error);
    }
  }

  void _apply(Map<String, dynamic> data, {List<InterestOption>? topics}) {
    _userId = (data['id'] ?? '').toString();
    final fullName = (data['full_name'] ?? data['name'] ?? '').toString().trim();
    final parts = fullName.split(RegExp(r'\s+'));
    _firstNameCtrl.text = parts.isNotEmpty ? parts.first : '';
    _lastNameCtrl.text = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    _bioCtrl.text = (data['bio'] ?? '').toString();
    _email = (data['email'] ?? '').toString().trim();
    _emailCtrl.text = _email ?? '';

    final g = (data['gender'] ?? '').toString().toLowerCase();
    if (g == 'male' || g == 'm') {
      _gender = 'male';
    } else if (g == 'female' || g == 'f') {
      _gender = 'female';
    } else if (g == 'other') {
      _gender = 'other';
    } else {
      _gender = null;
    }

    _participation = ProfileStyleCodec.decode(
      data['conversation_style']?.toString() ?? data['conversationStyle']?.toString(),
    );
    _tone = ProfileStyleCodec.decode(
      data['humor_type']?.toString() ?? data['humorType']?.toString(),
    );
    _country = (data['country'] ?? '').toString().trim().isEmpty ? null : data['country'].toString().trim();
    _city = (data['city'] ?? '').toString().trim().isEmpty ? null : data['city'].toString().trim();
    _locationOptIn = data['location_opt_in'] == true || data['locationOptIn'] == true;

    final catalog = topics ?? _topics;
    final byName = <String, String>{
      for (final t in catalog) t.label.trim().toLowerCase(): t.id,
    };
    final selected = <String>{};
    final hobbies = data['hobbies'];
    if (hobbies is List) {
      for (final h in hobbies) {
        if (h is Map) {
          final id = (h['id'] ?? '').toString();
          if (id.isNotEmpty) selected.add(id);
          final name = (h['name'] ?? '').toString().trim().toLowerCase();
          if (name.isNotEmpty && byName.containsKey(name)) selected.add(byName[name]!);
        } else if (h is String) {
          final raw = h.trim();
          if (catalog.any((t) => t.id == raw)) {
            selected.add(raw);
          } else {
            final id = byName[raw.toLowerCase()];
            if (id != null) selected.add(id);
          }
        }
      }
    }
    // Own profile also returns interest names (no IDs) — map them.
    final interests = data['interests'];
    if (interests is List) {
      for (final item in interests) {
        final name = item.toString().trim().toLowerCase();
        final id = byName[name];
        if (id != null) selected.add(id);
      }
    }
    _selectedTopicIds = selected;

    final pic = (data['profile_picture'] ?? data['imageUrl'] ?? data['avatar'] ?? '').toString();
    if (pic.isNotEmpty) {
      _photoUrl = _uploadsUrl(pic);
      _photoFile = null;
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1920,
    );
    if (picked == null) return;
    final file = File(picked.path);
    final length = await file.length();
    if (length > 5 * 1024 * 1024) {
      customSnackBar(
        'Image too large',
        'Max size is 5 MB. Please choose a smaller photo.',
        type: SnackType.error,
      );
      return;
    }
    setState(() {
      _photoFile = file;
      _uploading = true;
    });
    try {
      final resp = await AuthService().uploadProfilePicture(_photoFile!);
      Map<String, dynamic> profileData = {};
      if (resp[ApiConfig.dataKey] is Map) {
        profileData = Map<String, dynamic>.from(resp[ApiConfig.dataKey] as Map);
      }
      final pic = (profileData['profile_picture'] ?? profileData['imageUrl'] ?? '').toString();
      if (!mounted) return;
      setState(() {
        if (pic.isNotEmpty) {
          _photoUrl = _uploadsUrl(pic);
          _photoFile = null;
        }
        _uploading = false;
      });
      try {
        AppCaches.invalidateAfterProfileUpdate();
        await _profileController.refreshQuiet();
      } catch (_) {}
      customSnackBar('Success', 'Photo updated', type: SnackType.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      final raw = e is ApiException
          ? (e.message ?? e.toString())
          : e.toString().replaceAll('ApiException: ', '');
      final lower = raw.toLowerCase();
      final isTooLarge = (e is ApiException && e.statusCode == 413) ||
          lower.contains('too large') ||
          lower.contains('file too large') ||
          lower.contains('limit_file_size') ||
          lower.contains('payload');
      customSnackBar(
        isTooLarge ? 'Image too large' : 'Error',
        isTooLarge ? 'Max size is 5 MB. Please choose a smaller photo.' : raw,
        type: SnackType.error,
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTopicIds.length < 2) {
      customSnackBar('Almost there', 'Pick at least 2 topics', type: SnackType.info);
      return;
    }
    if (_participation.isEmpty || _tone.isEmpty) {
      customSnackBar('Almost there', 'Choose participation style and community tone', type: SnackType.info);
      return;
    }

    final fullName = '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'.trim();
    final body = <String, dynamic>{
      'full_name': fullName,
      'bio': _bioCtrl.text.trim(),
      'hobbies': _selectedTopicIds.toList(),
      'conversation_style': ProfileStyleCodec.encode(_participation),
      'humor_type': ProfileStyleCodec.encode(_tone),
      'location_opt_in': _locationOptIn,
    };
    if (_gender != null) body['gender'] = _gender;
    if (_city != null && _city!.isNotEmpty) body['city'] = _city;
    if (_country != null && _country!.isNotEmpty) body['country'] = _country;

    setState(() => _saving = true);
    try {
      final updated = await AuthService().updateProfile(body);
      Map<String, dynamic> profileData = {};
      if (updated[ApiConfig.dataKey] is Map) {
        profileData = Map<String, dynamic>.from(updated[ApiConfig.dataKey] as Map);
      } else {
        profileData = Map<String, dynamic>.from(updated);
      }
      if (!mounted) return;
      setState(() {
        _apply(profileData, topics: _topics);
        _saving = false;
      });
      try {
        AppCaches.invalidateAfterProfileUpdate();
        await _profileController.refreshQuiet();
      } catch (_) {}
      customSnackBar('Success', 'Profile updated', type: SnackType.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      customSnackBar('Error', e.toString().replaceAll('ApiException: ', ''), type: SnackType.error);
    }
  }

  InputDecoration _fieldDecoration({required String label, String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, color: AppColors.primary, size: 20) : null,
      filled: true,
      fillColor: AppColors.card,
      labelStyle: AppTextStyles.ui(size: 13, weight: FontWeight.w600, color: AppColors.body),
      floatingLabelStyle: AppTextStyles.ui(size: 13, weight: FontWeight.w700, color: AppColors.primary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.mutedBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.mutedBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
    );
  }

  Widget _sectionTile({
    required String title,
    required String subtitle,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: AppColors.primary.withOpacity(0.06),
        highlightColor: Colors.transparent,
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.mutedBorder.withOpacity(0.7))),
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
          childrenPadding: const EdgeInsets.only(bottom: 12),
          iconColor: AppColors.body,
          collapsedIconColor: AppColors.body,
          title: Text(title, style: AppTextStyles.ui(size: 15, weight: FontWeight.w700)),
          subtitle: Text(subtitle, style: AppTextStyles.ui(size: 12, color: AppColors.body)),
          children: children,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppColors.brandGradient)),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        title: Text('Edit profile', style: AppTextStyles.ui(size: 18, weight: FontWeight.w800, color: AppColors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                children: [
                  Center(child: _PhotoPicker(
                    photoFile: _photoFile,
                    photoUrl: _photoUrl,
                    uploading: _uploading,
                    onTap: _pickPhoto,
                  )),
                  const SizedBox(height: 10),
                  Text(
                    'Tap to change photo · Max 5 MB · JPG or PNG',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption,
                  ),
                  const SizedBox(height: 24),
                  Text('About you', style: AppTextStyles.sectionTitle),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _firstNameCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: _fieldDecoration(label: 'First name', icon: Icons.person_outline),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _lastNameCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: _fieldDecoration(label: 'Last name'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _gender,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.body),
                    dropdownColor: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    decoration: _fieldDecoration(label: 'Gender', icon: Icons.wc_outlined),
                    items: const [
                      DropdownMenuItem(value: 'male', child: Text('Male')),
                      DropdownMenuItem(value: 'female', child: Text('Female')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) => setState(() => _gender = v),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _bioCtrl,
                    maxLines: 4,
                    maxLength: 1000,
                    decoration: _fieldDecoration(
                      label: 'Bio',
                      hint: 'Share what you care about in this community…',
                      icon: Icons.edit_note_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionTile(
                    title: 'Topics',
                    subtitle: _selectedTopicIds.isEmpty
                        ? 'Pick at least 2 topics you want to talk about'
                        : '${_selectedTopicIds.length} selected · tap to edit',
                    initiallyExpanded: true,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _topics.map((t) {
                            final selected = _selectedTopicIds.contains(t.id);
                            return FilterChip(
                              label: Text(t.label),
                              selected: selected,
                              onSelected: (v) {
                                setState(() {
                                  if (v) {
                                    _selectedTopicIds.add(t.id);
                                  } else {
                                    _selectedTopicIds.remove(t.id);
                                  }
                                });
                              },
                              selectedColor: AppColors.primary.withOpacity(0.12),
                              checkmarkColor: AppColors.primary,
                              labelStyle: AppTextStyles.ui(
                                size: 13,
                                weight: FontWeight.w600,
                                color: selected ? AppColors.primaryDeep : AppColors.ink,
                              ),
                              side: BorderSide(
                                color: selected ? AppColors.primary.withOpacity(0.5) : AppColors.mutedBorder,
                              ),
                              backgroundColor: AppColors.surface,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                  _sectionTile(
                    title: 'How you participate',
                    subtitle: _participation.isEmpty
                        ? 'Choose one or more ways you take part'
                        : '${_participation.length} selected · tap to edit',
                    children: [
                      ..._participationStyles.map((style) => _OptionTile(
                            label: style,
                            selected: _participation.contains(style),
                            onTap: () => setState(() {
                              if (_participation.contains(style)) {
                                _participation = {..._participation}..remove(style);
                              } else {
                                _participation = {..._participation, style};
                              }
                            }),
                          )),
                    ],
                  ),
                  _sectionTile(
                    title: 'Community tone you enjoy',
                    subtitle: _tone.isEmpty
                        ? 'Pick one or more tones that fit you'
                        : '${_tone.length} selected · tap to edit',
                    children: [
                      ..._communityTones.map((tone) => _OptionTile(
                            label: tone,
                            selected: _tone.contains(tone),
                            onTap: () => setState(() {
                              if (_tone.contains(tone)) {
                                _tone = {..._tone}..remove(tone);
                              } else {
                                _tone = {..._tone, tone};
                              }
                            }),
                          )),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Location', style: AppTextStyles.sectionTitle),
                  const SizedBox(height: 10),
                  CountryCityPicker(
                    key: ValueKey('loc_${_country}_$_city'),
                    initialCountry: _country,
                    initialCity: _city,
                    onCountryChanged: (c) => setState(() {
                      _country = c;
                      _city = null;
                    }),
                    onCityChanged: (c) => setState(() => _city = c),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Show my city in the community', style: AppTextStyles.ui(weight: FontWeight.w600)),
                    subtitle: Text('Helps others find local circle activity', style: AppTextStyles.caption),
                    value: _locationOptIn,
                    onChanged: (v) => setState(() => _locationOptIn = v),
                  ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: 'Save profile',
                    loading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  final File? photoFile;
  final String? photoUrl;
  final bool uploading;
  final VoidCallback onTap;

  const _PhotoPicker({
    required this.photoFile,
    required this.photoUrl,
    required this.uploading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    ImageProvider? image;
    if (photoFile != null) {
      image = FileImage(photoFile!);
    } else if (photoUrl != null && photoUrl!.isNotEmpty) {
      image = NetworkImage(photoUrl!);
    }

    return GestureDetector(
      onTap: uploading ? null : onTap,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            width: 118,
            height: 118,
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.brandGradient),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.chipIdle,
                image: image != null ? DecorationImage(image: image, fit: BoxFit.cover) : null,
              ),
              child: image == null
                  ? const Icon(Icons.person_outline, size: 48, color: AppColors.primary)
                  : null,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.brandGradient,
              border: Border.all(color: AppColors.white, width: 2),
            ),
            child: uploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.camera_alt_outlined, size: 16, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected ? AppColors.primary.withOpacity(0.06) : Colors.transparent,
            border: Border.all(
              color: selected ? AppColors.primary.withOpacity(0.45) : AppColors.mutedBorder,
            ),
          ),
          child: Row(
            children: [
              Expanded(child: Text(label, style: AppTextStyles.ui(size: 14, weight: FontWeight.w600))),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 20,
                color: selected ? AppColors.primary : AppColors.body,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
