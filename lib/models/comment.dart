import 'post.dart';

class PostComment {
  final String id;
  final String postId;
  final PostAuthor user;
  final String content;
  final String? parentId;
  final int likeCount;
  final bool isLikedByMe;
  final DateTime createdAt;

  const PostComment({
    required this.id,
    required this.postId,
    required this.user,
    required this.content,
    this.parentId,
    this.likeCount = 0,
    this.isLikedByMe = false,
    required this.createdAt,
  });

  PostComment copyWith({
    int? likeCount,
    bool? isLikedByMe,
    String? content,
  }) {
    return PostComment(
      id: id,
      postId: postId,
      user: user,
      content: content ?? this.content,
      parentId: parentId,
      likeCount: likeCount ?? this.likeCount,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      createdAt: createdAt,
    );
  }

  factory PostComment.fromJson(Map<String, dynamic> j) {
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

    final likeRaw = j['like_count'] ?? j['likeCount'] ?? 0;
    final likeCount = likeRaw is int ? likeRaw : int.tryParse('$likeRaw') ?? 0;

    return PostComment(
      id: (j['id'] ?? '').toString(),
      postId: (j['post_id'] ?? j['postId'] ?? '').toString(),
      user: user,
      content: (j['content'] ?? '').toString(),
      parentId: (j['parent_id'] ?? j['parentId'])?.toString(),
      likeCount: likeCount,
      isLikedByMe: j['is_liked_by_me'] == true || j['isLikedByMe'] == true,
      createdAt: created,
    );
  }
}

class PaginatedComments {
  final List<PostComment> items;
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  const PaginatedComments({
    required this.items,
    this.page = 1,
    this.limit = 20,
    this.total = 0,
    this.totalPages = 1,
  });

  factory PaginatedComments.fromJson(Map<String, dynamic> j) {
    final itemsRaw = j['items'];
    final items = <PostComment>[];
    if (itemsRaw is List) {
      for (final e in itemsRaw) {
        if (e is Map) items.add(PostComment.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    final pagination = j['pagination'] is Map
        ? Map<String, dynamic>.from(j['pagination'] as Map)
        : <String, dynamic>{};

    return PaginatedComments(
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
