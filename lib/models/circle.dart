class CircleSummary {
  final String id;
  final String name;

  const CircleSummary({required this.id, required this.name});

  factory CircleSummary.fromJson(Map<String, dynamic> j) {
    return CircleSummary(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
    );
  }
}

class Circle {
  final String id;
  final String name;
  final String slug;
  final String? description;
  final String? iconUrl;
  final int memberCount;
  final bool isFeatured;
  final bool isJoined;

  const Circle({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.iconUrl,
    this.memberCount = 0,
    this.isFeatured = false,
    this.isJoined = false,
  });

  factory Circle.fromJson(Map<String, dynamic> j) {
    return Circle(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      slug: (j['slug'] ?? '').toString(),
      description: j['description']?.toString(),
      iconUrl: j['icon_url']?.toString() ?? j['iconUrl']?.toString(),
      memberCount: j['member_count'] is int
          ? j['member_count'] as int
          : int.tryParse('${j['member_count'] ?? 0}') ?? 0,
      isFeatured: j['is_featured'] == true || j['isFeatured'] == true,
      isJoined: j['is_joined'] == true || j['isJoined'] == true,
    );
  }

  Circle copyWith({bool? isJoined, int? memberCount}) {
    return Circle(
      id: id,
      name: name,
      slug: slug,
      description: description,
      iconUrl: iconUrl,
      memberCount: memberCount ?? this.memberCount,
      isFeatured: isFeatured,
      isJoined: isJoined ?? this.isJoined,
    );
  }
}
