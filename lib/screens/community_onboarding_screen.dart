import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/circle.dart';
import '../network/api_client.dart' show ApiException;
import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import '../services/socket_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/custom_snackbar.dart';
import '../utils/profile_style_codec.dart';
import '../widgets/interest_tags_chips.dart';
import '../widgets/primary_button.dart';
import '../widgets/country_city_picker.dart';

class CommunityOnboardingScreen extends StatefulWidget {
  const CommunityOnboardingScreen({super.key});

  @override
  State<CommunityOnboardingScreen> createState() => _CommunityOnboardingScreenState();
}

class _CommunityOnboardingScreenState extends State<CommunityOnboardingScreen> {
  /// How members take part in topic communities (stored as conversation_style).
  static const _participationStyles = [
    'Share posts and tips',
    'Jump into discussions',
    'Organize group activities',
    'Mostly read and learn',
    'Welcome and help newcomers',
  ];

  /// Tone of content they enjoy in circles (stored as humor_type).
  static const _communityTones = [
    'Practical and informative',
    'Encouraging and upbeat',
    'Curious and explorative',
    'Straight-talking',
    'Creative and playful',
  ];

  final _onboarding = OnboardingService();
  final _cityController = TextEditingController();
  final _countryController = TextEditingController();
  final _pageController = PageController();

  int _step = 0;
  bool _loading = true;
  bool _submitting = false;
  bool _locationOptIn = false;

  List<InterestOption> _hobbies = [];
  Set<String> _selectedInterestIds = {};
  Set<String> _conversationStyles = {};
  Set<String> _humorTypes = {};
  List<Circle> _circles = [];
  Set<String> _selectedCircleIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cityController.dispose();
    _countryController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final hobbiesRaw = await AuthService().getHobbies();
      final hobbies = <InterestOption>[];
      final seenNames = <String>{};
      if (hobbiesRaw is List) {
        for (final item in hobbiesRaw) {
          if (item is Map) {
            final id = (item['id'] ?? '').toString();
            final name = (item['name'] ?? '').toString().trim();
            final key = name.toLowerCase();
            if (id.isNotEmpty && name.isNotEmpty && seenNames.add(key)) {
              hobbies.add(InterestOption(id: id, label: name));
            }
          }
        }
      }

      List<Circle> circles = [];
      try {
        circles = await _onboarding.getSuggestedCircles();
      } catch (_) {
        // Status may fail if server empty; still allow steps 1–3.
      }

      if (!mounted) return;
      setState(() {
        _hobbies = hobbies;
        _circles = circles;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      customSnackBar('Error', e is ApiException ? (e.message ?? 'Failed to load') : e.toString());
    }
  }

  void _goTo(int step) {
    setState(() => _step = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  bool _validateCurrent() {
    switch (_step) {
      case 0:
        if (_selectedInterestIds.length < 2) {
          customSnackBar('Almost there', 'Pick at least 2 topics for your feed', type: SnackType.info);
          return false;
        }
        return true;
      case 1:
        if (_conversationStyles.isEmpty) {
          customSnackBar('Required', 'Choose how you participate in circles', type: SnackType.info);
          return false;
        }
        if (_humorTypes.isEmpty) {
          customSnackBar('Required', 'Choose a community tone', type: SnackType.info);
          return false;
        }
        return true;
      case 2:
        if (_countryController.text.trim().isEmpty) {
          customSnackBar('Country needed', 'Select your country first', type: SnackType.info);
          return false;
        }
        if (_cityController.text.trim().isEmpty) {
          customSnackBar('City needed', 'Select your city to continue', type: SnackType.info);
          return false;
        }
        return true;
      case 3:
        if (_selectedCircleIds.isEmpty) {
          customSnackBar('Join a circle', 'Pick 1 circle to join', type: SnackType.info);
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  void _next() {
    if (!_validateCurrent()) return;
    if (_step < 4) {
      _goTo(_step + 1);
      if (_step + 1 == 4 && !_submitting) {
        // Landing on success step only after submit — use next as submit from step 3
      }
    }
  }

  Future<void> _submitAndFinish() async {
    if (!_validateCurrent()) return;
    setState(() => _submitting = true);
    try {
      final result = await _onboarding.completeCommunity(
        interestIds: _selectedInterestIds.toList(),
        city: _cityController.text.trim(),
        country: _countryController.text.trim().isEmpty ? null : _countryController.text.trim(),
        locationOptIn: _locationOptIn,
        conversationStyle: ProfileStyleCodec.encode(_conversationStyles),
        humorType: ProfileStyleCodec.encode(_humorTypes),
        suggestedCircleIds: _selectedCircleIds.toList(),
      );

      try {
        await AuthService().getProfile(forceRefresh: true);
      } catch (_) {}

      final awarded = result['points_awarded'];
      if (awarded is int && awarded > 0) {
        customSnackBar('Welcome!', '+$awarded Anchor Points — you\'re in!');
      } else {
        customSnackBar('Welcome!', 'Your community profile is ready');
      }

      if (!mounted) return;
      setState(() => _submitting = false);
      _goTo(4);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      customSnackBar('Error', e is ApiException ? (e.message ?? 'Onboarding failed') : e.toString());
    }
  }

  Future<void> _enterFeed() async {
    try {
      await SocketService().connect();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Anchor World', style: AppTextStyles.display(22, weight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          _stepTitle,
                          style: AppTextStyles.ui(size: 15, color: AppColors.body),
                        ),
                        const SizedBox(height: 16),
                        _ProgressPills(current: _step, total: 5),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildInterestsStep(),
                        _buildConnectStyleStep(),
                        _buildCityStep(),
                        _buildCirclesStep(),
                        _buildSuccessStep(),
                      ],
                    ),
                  ),
                  if (_step < 4)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      child: Row(
                        children: [
                          if (_step > 0) ...[
                            Expanded(
                              child: SecondaryButton(
                                label: 'Back',
                                onPressed: _submitting ? null : () => _goTo(_step - 1),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: PrimaryButton(
                              label: _step == 3 ? 'Finish' : 'Continue',
                              loading: _submitting,
                              onPressed: _submitting
                                  ? null
                                  : () {
                                      if (_step == 3) {
                                        _submitAndFinish();
                                      } else {
                                        _next();
                                      }
                                    },
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

  String get _stepTitle {
    switch (_step) {
      case 0:
        return 'Topics for your feed';
      case 1:
        return 'How you participate';
      case 2:
        return 'Your city for local posts';
      case 3:
        return 'Join a topic circle';
      default:
        return "You're in!";
    }
  }

  Widget _buildInterestsStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text('Topics you care about', style: AppTextStyles.screenTitle),
        const SizedBox(height: 8),
        Text(
          'Pick at least 2 topics. We use these to suggest circles and personalize your community feed.',
          style: AppTextStyles.body,
        ),
        const SizedBox(height: 12),
        Text(
          '${_selectedInterestIds.length} selected',
          style: AppTextStyles.ui(size: 13, color: AppColors.primary, weight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        if (_hobbies.isEmpty)
          Text('No topics loaded. Check your connection and try again.', style: AppTextStyles.body)
        else
          InterestTagsChips(
            options: _hobbies,
            selectedIds: _selectedInterestIds,
            onChanged: (ids) => setState(() => _selectedInterestIds = ids),
          ),
      ],
    );
  }

  Widget _buildConnectStyleStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text('Your community style', style: AppTextStyles.screenTitle),
        const SizedBox(height: 8),
        Text(
          'Required — helps place you in the right discussions and circle activity.',
          style: AppTextStyles.body,
        ),
        const SizedBox(height: 20),
        Text('How you participate', style: AppTextStyles.sectionTitle),
        const SizedBox(height: 6),
        Text('Select all that apply', style: AppTextStyles.caption),
        const SizedBox(height: 12),
        ..._participationStyles.map((style) => _ChoiceCard(
              label: style,
              selected: _conversationStyles.contains(style),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  if (_conversationStyles.contains(style)) {
                    _conversationStyles = {..._conversationStyles}..remove(style);
                  } else {
                    _conversationStyles = {..._conversationStyles, style};
                  }
                });
              },
            )),
        const SizedBox(height: 20),
        Text('Community tone you enjoy', style: AppTextStyles.sectionTitle),
        const SizedBox(height: 6),
        Text('Select all that apply', style: AppTextStyles.caption),
        const SizedBox(height: 12),
        ..._communityTones.map((tone) => _ChoiceCard(
              label: tone,
              selected: _humorTypes.contains(tone),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  if (_humorTypes.contains(tone)) {
                    _humorTypes = {..._humorTypes}..remove(tone);
                  } else {
                    _humorTypes = {..._humorTypes, tone};
                  }
                });
              },
            )),
      ],
    );
  }

  Widget _buildCityStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text('Your city', style: AppTextStyles.screenTitle),
        const SizedBox(height: 8),
        Text(
          'Choose country first, then city. Used for local posts when you opt in — never exact GPS.',
          style: AppTextStyles.body,
        ),
        const SizedBox(height: 20),
        CountryCityPicker(
          initialCountry: _countryController.text.isEmpty ? null : _countryController.text,
          initialCity: _cityController.text.isEmpty ? null : _cityController.text,
          onCountryChanged: (v) {
            _countryController.text = v ?? '';
            _cityController.clear();
            setState(() {});
          },
          onCityChanged: (v) {
            _cityController.text = v ?? '';
            setState(() {});
          },
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppColors.cardShadow,
          ),
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text('Show my city on posts', style: AppTextStyles.ui(weight: FontWeight.w600)),
            subtitle: Text('You can change this anytime in settings', style: AppTextStyles.caption),
            value: _locationOptIn,
            activeColor: AppColors.primary,
            onChanged: (v) => setState(() => _locationOptIn = v),
          ),
        ),
      ],
    );
  }

  Widget _buildCirclesStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text('Join your circle', style: AppTextStyles.screenTitle),
        const SizedBox(height: 8),
        Text(
          'Pick 1 topic community. Your feed starts here.',
          style: AppTextStyles.body,
        ),
        const SizedBox(height: 8),
        Text(
          _selectedCircleIds.isEmpty ? 'None selected' : '1 selected',
          style: AppTextStyles.ui(size: 13, color: AppColors.primary, weight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        if (_circles.isEmpty)
          Text(
            'No circles available yet. Try again later or contact support.',
            style: AppTextStyles.body,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 10,
            alignment: WrapAlignment.start,
            children: _circles.map((circle) {
              final selected = _selectedCircleIds.contains(circle.id);
              return _CircleBubble(
                circle: circle,
                selected: selected,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (selected) {
                      _selectedCircleIds.remove(circle.id);
                    } else {
                      // Limit: exactly one circle.
                      _selectedCircleIds
                        ..clear()
                        ..add(circle.id);
                    }
                  });
                },
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildSuccessStep() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
      child: Column(
        children: [
          const Spacer(),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.brandGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 48),
          ),
          const SizedBox(height: 28),
          Text("You're in!", style: AppTextStyles.display(34), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            'Join circles, share posts, earn Anchor Points, and unlock Premium discounts for video calls.',
            style: AppTextStyles.body,
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          PrimaryButton(
            label: 'Go to Feed',
            icon: Icons.home_outlined,
            onPressed: _enterFeed,
          ),
        ],
      ),
    );
  }
}

class _ProgressPills extends StatelessWidget {
  final int current;
  final int total;

  const _ProgressPills({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final active = i <= current;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
            height: 5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: active ? AppColors.primary : AppColors.mutedBorder,
            ),
          ),
        );
      }),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceCard({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? AppColors.primary.withOpacity(0.08) : AppColors.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.mutedBorder,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(child: Text(label, style: AppTextStyles.ui(weight: FontWeight.w600))),
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: selected ? AppColors.primary : AppColors.body,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleBubble extends StatelessWidget {
  final Circle circle;
  final bool selected;
  final VoidCallback onTap;

  const _CircleBubble({
    required this.circle,
    required this.selected,
    required this.onTap,
  });

  String _shortCount(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k';
    return '$n';
  }

  String get _initial {
    final name = circle.name.trim();
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
          decoration: BoxDecoration(
            gradient: selected ? AppColors.brandGradient : null,
            color: selected ? null : AppColors.card,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: selected ? Colors.transparent : AppColors.mutedBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: selected
                    ? AppColors.primary.withOpacity(0.25)
                    : AppColors.ink.withOpacity(0.04),
                blurRadius: selected ? 14 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.white.withOpacity(0.22) : AppColors.chipIdle,
                ),
                child: selected
                    ? const Icon(Icons.check_rounded, size: 18, color: AppColors.white)
                    : Text(
                        _initial,
                        style: AppTextStyles.ui(size: 14, weight: FontWeight.w800, color: AppColors.primary),
                      ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      circle.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.ui(
                        size: 13,
                        weight: FontWeight.w800,
                        color: selected ? AppColors.white : AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_shortCount(circle.memberCount)} members',
                      style: AppTextStyles.ui(
                        size: 11,
                        weight: FontWeight.w500,
                        color: selected ? AppColors.white.withOpacity(0.75) : const Color(0xFF8A8184),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

