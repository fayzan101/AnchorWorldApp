class Profile {
  final String id;
  final String name;
  final int age;
  final String bio;
  final String imageUrl;
  final String? dateOfBirth;
  final String gender;
  final String location;
  final String? city;
  final String? country;
  final bool locationOptIn;
  final List<String> interests;
  final String? conversationStyle;
  final String? humorType;
  final int pointsBalance;
  final int postCount;
  final List<Map<String, dynamic>> circles;
  final String? connectionStatus;
  final bool profileCompleted;
  final String? onboardingCompletedAt;
  final String? introVideoUrl;
  final String? email;
  final List<Map<String, dynamic>> hobbies;

  Profile({
    required this.id,
    required this.name,
    required this.age,
    required this.bio,
    required this.imageUrl,
    this.dateOfBirth,
    this.gender = '',
    this.location = '',
    this.city,
    this.country,
    this.locationOptIn = false,
    this.interests = const [],
    this.conversationStyle,
    this.humorType,
    this.pointsBalance = 0,
    this.postCount = 0,
    this.circles = const [],
    this.connectionStatus,
    this.profileCompleted = false,
    this.onboardingCompletedAt,
    this.introVideoUrl,
    this.email,
    this.hobbies = const [],
  });

  factory Profile.fromJson(Map<String, dynamic> j) {
    final city = (j['city'] ?? '').toString().trim();
    final country = (j['country'] ?? '').toString().trim();
    final legacyLocation = (j['location'] ?? '').toString().trim();
    final location = [
      if (city.isNotEmpty) city,
      if (country.isNotEmpty) country,
    ].join(', ');

    return Profile(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? j['full_name'] ?? '').toString(),
      age: j['age'] is int ? j['age'] as int : int.tryParse('${j['age']}') ?? 0,
      bio: (j['bio'] ?? '').toString(),
      imageUrl: (j['imageUrl'] ?? j['profile_picture'] ?? '').toString(),
      dateOfBirth: (j['date_of_birth'] ?? j['dob'] ?? '')?.toString(),
      gender: (j['gender'] ?? '').toString(),
      location: location.isNotEmpty ? location : legacyLocation,
      city: city.isNotEmpty ? city : null,
      country: country.isNotEmpty ? country : null,
      locationOptIn: j['location_opt_in'] == true || j['locationOptIn'] == true,
      interests: _parseInterests(j['interests'] ?? j['hobbies']),
      conversationStyle: j['conversation_style']?.toString() ?? j['conversationStyle']?.toString(),
      humorType: j['humor_type']?.toString() ?? j['humorType']?.toString(),
      pointsBalance: j['points_balance'] is int
          ? j['points_balance'] as int
          : int.tryParse('${j['points_balance'] ?? 0}') ?? 0,
      postCount: j['post_count'] is int
          ? j['post_count'] as int
          : int.tryParse('${j['post_count'] ?? 0}') ?? 0,
      circles: _parseMapList(j['circles']),
      connectionStatus: j['connection_status']?.toString() ?? j['connectionStatus']?.toString(),
      profileCompleted: j['profile_completed'] == true || j['profileCompleted'] == true,
      onboardingCompletedAt:
          j['onboarding_completed_at']?.toString() ?? j['onboardingCompletedAt']?.toString(),
      introVideoUrl: j['intro_video_url']?.toString() ?? j['introVideoUrl']?.toString(),
      email: (() {
        final e = (j['email'] ?? '').toString().trim();
        return e.isEmpty ? null : e;
      })(),
      hobbies: _parseMapList(j['hobbies']),
    );
  }

  static List<String> _parseInterests(dynamic raw) {
    if (raw == null) return <String>[];
    if (raw is List) {
      final out = <String>[];
      for (final e in raw) {
        if (e == null) continue;
        if (e is String) {
          final s = e.trim();
          if (s.isNotEmpty) out.add(s);
          continue;
        }
        if (e is Map) {
          final candidates = ['name', 'title', 'interest', 'label', 'value'];
          String? found;
          for (final k in candidates) {
            if (e.containsKey(k) && e[k] != null) {
              found = e[k].toString().trim();
              if (found.isNotEmpty) break;
            }
          }
          if (found != null && found.isNotEmpty) out.add(found);
          continue;
        }
        final s = e.toString().trim();
        if (s.isNotEmpty) out.add(s);
      }
      return out;
    }
    if (raw is String) {
      return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    return <String>[];
  }

  static List<Map<String, dynamic>> _parseMapList(dynamic raw) {
    if (raw == null) return <Map<String, dynamic>>[];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'age': age,
        'bio': bio,
        'imageUrl': imageUrl,
        'gender': gender,
        'location': location,
        'city': city,
        'country': country,
        'location_opt_in': locationOptIn,
        'interests': interests,
        'conversation_style': conversationStyle,
        'humor_type': humorType,
        'points_balance': pointsBalance,
        'post_count': postCount,
        'circles': circles,
        'connection_status': connectionStatus,
        'profile_completed': profileCompleted,
        'onboarding_completed_at': onboardingCompletedAt,
        'email': email,
        'hobbies': hobbies,
        'date_of_birth': dateOfBirth ?? '',
      };
}
