class PostAuthor {
  final String id;
  final String fullName;
  final String? profilePicture;
  final String? city;
  final List<String> interests;
  final String? conversationStyle;

  const PostAuthor({
    required this.id,
    required this.fullName,
    this.profilePicture,
    this.city,
    this.interests = const [],
    this.conversationStyle,
  });

  factory PostAuthor.fromJson(Map<String, dynamic> j) {
    final interestsRaw = j['interests'];
    final interests = <String>[];
    if (interestsRaw is List) {
      for (final e in interestsRaw) {
        if (e == null) continue;
        if (e is String && e.trim().isNotEmpty) {
          interests.add(e.trim());
        } else if (e is Map && e['name'] != null) {
          interests.add(e['name'].toString());
        }
      }
    }

    return PostAuthor(
      id: (j['id'] ?? '').toString(),
      fullName: (j['full_name'] ?? j['name'] ?? 'Member').toString(),
      profilePicture: j['profile_picture']?.toString() ?? j['profilePicture']?.toString(),
      city: j['city']?.toString(),
      interests: interests,
      conversationStyle: j['conversation_style']?.toString(),
    );
  }
}

/// Nested original post shown inside a shared post (Facebook-style).
class SourcePostPreview {
  final String id;
  final PostAuthor user;
  final String content;
  final String? mediaUrl;
  final String mediaType;
  final String? circleName;
  final DateTime? createdAt;

  const SourcePostPreview({
    required this.id,
    required this.user,
    required this.content,
    this.mediaUrl,
    this.mediaType = 'none',
    this.circleName,
    this.createdAt,
  });

  factory SourcePostPreview.fromJson(Map<String, dynamic> j) {
    final userRaw = j['user'];
    final user = userRaw is Map
        ? PostAuthor.fromJson(Map<String, dynamic>.from(userRaw))
        : PostAuthor(
            id: '',
            fullName: (j['full_name'] ?? j['name'] ?? 'Member').toString(),
            profilePicture: j['profile_picture']?.toString(),
          );

    DateTime? created;
    final rawCreated = j['created_at'] ?? j['createdAt'];
    if (rawCreated is String) {
      created = DateTime.tryParse(rawCreated)?.toLocal();
    }

    return SourcePostPreview(
      id: (j['id'] ?? '').toString(),
      user: user,
      content: (j['content'] ?? '').toString(),
      mediaUrl: j['media_url']?.toString() ?? j['mediaUrl']?.toString(),
      mediaType: (j['media_type'] ?? j['mediaType'] ?? 'none').toString(),
      circleName: j['circle_name']?.toString() ?? j['circleName']?.toString(),
      createdAt: created,
    );
  }
}

class Post {
  final String id;
  final PostAuthor user;
  final String content;
  final String? mediaUrl;
  final String mediaType; // none | image | video
  final String? circleId;
  final String? circleName;
  final String? city;
  final String? country;
  final int likeCount;
  final int commentCount;
  final bool isLikedByMe;
  final DateTime createdAt;
  final String? sourcePostId;
  final String? sourceAuthorName;
  final SourcePostPreview? sourcePost;

  const Post({
    required this.id,
    required this.user,
    required this.content,
    this.mediaUrl,
    this.mediaType = 'none',
    this.circleId,
    this.circleName,
    this.city,
    this.country,
    this.likeCount = 0,
    this.commentCount = 0,
    this.isLikedByMe = false,
    required this.createdAt,
    this.sourcePostId,
    this.sourceAuthorName,
    this.sourcePost,
  });

  factory Post.fromJson(Map<String, dynamic> j) {
    final userRaw = j['user'];
    final user = userRaw is Map
        ? PostAuthor.fromJson(Map<String, dynamic>.from(userRaw))
        : const PostAuthor(id: '', fullName: 'Member');

    DateTime created;
    final rawCreated = j['created_at'] ?? j['createdAt'];
    if (rawCreated is String) {
      created = DateTime.tryParse(rawCreated)?.toLocal() ?? DateTime.now();
    } else {
      created = DateTime.now();
    }

    final sourceId = (j['source_post_id'] ?? j['sourcePostId'] ?? '').toString().trim();
    final sourceAuthor = j['source_author'];
    String? sourceAuthorName;
    if (sourceAuthor is Map) {
      sourceAuthorName = (sourceAuthor['full_name'] ?? sourceAuthor['name'] ?? '').toString().trim();
      if (sourceAuthorName.isEmpty) sourceAuthorName = null;
    } else {
      final raw = (j['source_author_name'] ?? j['sourceAuthorName'] ?? '').toString().trim();
      sourceAuthorName = raw.isEmpty ? null : raw;
    }

    SourcePostPreview? sourcePost;
    final sourceRaw = j['source_post'] ?? j['sourcePost'];
    if (sourceRaw is Map) {
      sourcePost = SourcePostPreview.fromJson(Map<String, dynamic>.from(sourceRaw));
      sourceAuthorName ??= sourcePost.user.fullName.trim().isEmpty ? null : sourcePost.user.fullName;
    }

    return Post(
      id: (j['id'] ?? '').toString(),
      user: user,
      content: (j['content'] ?? '').toString(),
      mediaUrl: j['media_url']?.toString() ?? j['mediaUrl']?.toString(),
      mediaType: (j['media_type'] ?? j['mediaType'] ?? 'none').toString(),
      circleId: j['circle_id']?.toString() ?? j['circleId']?.toString(),
      circleName: j['circle_name']?.toString() ?? j['circleName']?.toString(),
      city: j['city']?.toString(),
      country: j['country']?.toString(),
      likeCount: j['like_count'] is int
          ? j['like_count'] as int
          : int.tryParse('${j['like_count'] ?? 0}') ?? 0,
      commentCount: j['comment_count'] is int
          ? j['comment_count'] as int
          : int.tryParse('${j['comment_count'] ?? 0}') ?? 0,
      isLikedByMe: j['is_liked_by_me'] == true || j['isLikedByMe'] == true,
      createdAt: created,
      sourcePostId: sourceId.isEmpty ? null : sourceId,
      sourceAuthorName: sourceAuthorName,
      sourcePost: sourcePost,
    );
  }

  Post copyWith({
    String? content,
    String? mediaUrl,
    String? mediaType,
    String? circleId,
    String? circleName,
    int? likeCount,
    int? commentCount,
    bool? isLikedByMe,
    String? sourcePostId,
    String? sourceAuthorName,
    SourcePostPreview? sourcePost,
  }) {
    return Post(
      id: id,
      user: user,
      content: content ?? this.content,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType ?? this.mediaType,
      circleId: circleId ?? this.circleId,
      circleName: circleName ?? this.circleName,
      city: city,
      country: country,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      createdAt: createdAt,
      sourcePostId: sourcePostId ?? this.sourcePostId,
      sourceAuthorName: sourceAuthorName ?? this.sourceAuthorName,
      sourcePost: sourcePost ?? this.sourcePost,
    );
  }
}

class PaginatedPosts {
  final List<Post> items;
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  const PaginatedPosts({
    required this.items,
    this.page = 1,
    this.limit = 20,
    this.total = 0,
    this.totalPages = 1,
  });

  factory PaginatedPosts.fromJson(Map<String, dynamic> j) {
    final itemsRaw = j['items'];
    final items = <Post>[];
    if (itemsRaw is List) {
      for (final e in itemsRaw) {
        if (e is Map) items.add(Post.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    final pagination = j['pagination'] is Map
        ? Map<String, dynamic>.from(j['pagination'] as Map)
        : <String, dynamic>{};

    return PaginatedPosts(
      items: items,
      page: pagination['page'] is int ? pagination['page'] as int : int.tryParse('${pagination['page'] ?? 1}') ?? 1,
      limit: pagination['limit'] is int ? pagination['limit'] as int : int.tryParse('${pagination['limit'] ?? 20}') ?? 20,
      total: pagination['total'] is int ? pagination['total'] as int : int.tryParse('${pagination['total'] ?? 0}') ?? 0,
      totalPages: pagination['total_pages'] is int
          ? pagination['total_pages'] as int
          : int.tryParse('${pagination['total_pages'] ?? 1}') ?? 1,
    );
  }

  bool get hasMore => page < totalPages;
}
