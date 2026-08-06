import 'dart:io';

import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../network/api_client.dart';

class PostService {
  final ApiClient _client = apiClient;

  Future<PaginatedPosts> getFeed({
    String filter = 'circles',
    int page = 1,
    int limit = 20,
    String? circleId,
  }) async {
    final resp = await _client.get(
      ApiConfig.postsFeed,
      queryParameters: {
        'filter': filter,
        'page': page,
        'limit': limit,
        if (circleId != null && circleId.isNotEmpty) 'circle_id': circleId,
      },
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return PaginatedPosts.fromJson(_unwrapMap(resp));
  }

  Future<Post> getPost(String id) async {
    final resp = await _client.get(
      '${ApiConfig.posts}/$id',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return Post.fromJson(_unwrapMap(resp));
  }

  Future<PaginatedPosts> getUserPosts(String userId, {int page = 1, int limit = 20}) async {
    final resp = await _client.get(
      '${ApiConfig.users}/$userId/posts',
      queryParameters: {'page': page, 'limit': limit},
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return PaginatedPosts.fromJson(_unwrapMap(resp));
  }

  /// Multipart create. Returns map with `post` and optional `points_awarded`.
  Future<Map<String, dynamic>> createPost({
    required String content,
    String? circleId,
    File? media,
  }) async {
    final map = <String, dynamic>{
      'content': content,
      if (circleId != null && circleId.isNotEmpty) 'circle_id': circleId,
    };
    if (media != null) {
      final name = media.path.split(RegExp(r'[\\/]')).last;
      map['media'] = await MultipartFile.fromFile(media.path, filename: name);
    }
    final form = FormData.fromMap(map);
    // Let Dio set multipart Content-Type with boundary — do not force it.
    final resp = await _client.post(
      ApiConfig.posts,
      data: form,
      options: Options(headers: {'Accept': 'application/json'}),
    );
    return _unwrapFlexible(resp);
  }

  Future<void> deletePost(String id) async {
    final resp = await _client.delete(
      '${ApiConfig.posts}/$id',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException(_messageFrom(resp), status);
    }
  }

  Future<Post> updatePost({
    required String id,
    required String content,
    String? circleId,
    bool clearCircle = false,
    File? media,
  }) async {
    final map = <String, dynamic>{
      'content': content,
      if (circleId != null && circleId.isNotEmpty) 'circle_id': circleId,
      if (clearCircle) 'circle_id': '',
    };
    if (media != null) {
      final name = media.path.split(RegExp(r'[\\/]')).last;
      map['media'] = await MultipartFile.fromFile(media.path, filename: name);
    }
    final form = FormData.fromMap(map);
    final resp = await _client.patch(
      '${ApiConfig.posts}/$id',
      data: form,
      options: Options(headers: {'Accept': 'application/json'}),
    );
    return Post.fromJson(_unwrapMap(resp));
  }

  Future<Post> sharePost(
    String postId, {
    required String circleId,
    String? comment,
  }) async {
    final resp = await _client.post(
      '${ApiConfig.posts}/$postId/share',
      data: {
        'circle_id': circleId,
        if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
      },
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return Post.fromJson(_unwrapMap(resp));
  }

  Future<Map<String, dynamic>> likePost(String id) async {
    final resp = await _client.post(
      '${ApiConfig.posts}/$id/like',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return _unwrapMap(resp);
  }

  Future<Map<String, dynamic>> unlikePost(String id) async {
    final resp = await _client.delete(
      '${ApiConfig.posts}/$id/like',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return _unwrapMap(resp);
  }

  Future<PaginatedComments> getComments(String postId, {int page = 1, int limit = 30}) async {
    final resp = await _client.get(
      '${ApiConfig.posts}/$postId/comments',
      queryParameters: {'page': page, 'limit': limit},
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return PaginatedComments.fromJson(_unwrapMap(resp));
  }

  Future<PostComment> addComment(String postId, String content, {String? parentId}) async {
    final resp = await _client.post(
      '${ApiConfig.posts}/$postId/comments',
      data: {
        'content': content,
        if (parentId != null && parentId.isNotEmpty) 'parent_id': parentId,
      },
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final data = _unwrapFlexible(resp);
    if (data['id'] != null) return PostComment.fromJson(data);
    if (data['comment'] is Map) {
      return PostComment.fromJson(Map<String, dynamic>.from(data['comment'] as Map));
    }
    throw ApiException('Invalid comment response');
  }

  Future<Map<String, dynamic>> likeComment(String commentId) async {
    final resp = await _client.post(
      '/comments/$commentId/like',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return _unwrapMap(resp);
  }

  Future<Map<String, dynamic>> unlikeComment(String commentId) async {
    final resp = await _client.delete(
      '/comments/$commentId/like',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return _unwrapMap(resp);
  }

  Future<void> deleteComment(String commentId) async {
    final resp = await _client.delete(
      '/comments/$commentId',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException(_messageFrom(resp), status);
    }
  }

  Future<void> reportComment(String commentId, {String? reason}) async {
    final resp = await _client.post(
      '/comments/$commentId/report',
      data: {
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException(_messageFrom(resp), status);
    }
  }

  Future<void> reportPost(String postId, {String? reason}) async {
    final resp = await _client.post(
      '${ApiConfig.posts}/$postId/report',
      data: {
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException(_messageFrom(resp), status);
    }
  }

  Map<String, dynamic> _unwrapMap(Response resp) {
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException(_messageFrom(resp), status);
    }
    final data = resp.data;
    if (data is Map<String, dynamic>) {
      if (data[ApiConfig.dataKey] is Map<String, dynamic>) {
        return Map<String, dynamic>.from(data[ApiConfig.dataKey] as Map);
      }
      return Map<String, dynamic>.from(data);
    }
    throw ApiException('Invalid response from server', status);
  }

  Map<String, dynamic> _unwrapFlexible(Response resp) {
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException(_messageFrom(resp), status);
    }
    final data = resp.data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      if (map[ApiConfig.dataKey] is Map) {
        return Map<String, dynamic>.from(map[ApiConfig.dataKey] as Map);
      }
      return map;
    }
    throw ApiException('Invalid response from server', status);
  }

  String _messageFrom(Response resp) {
    final body = resp.data;
    if (body is Map) {
      if (body[ApiConfig.messageKey] is String) return body[ApiConfig.messageKey] as String;
      final err = body[ApiConfig.errorKey];
      if (err is String) return err;
    }
    return resp.statusMessage ?? 'Request failed';
  }
}
