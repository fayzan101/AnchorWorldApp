import 'circle_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/circle.dart';
import '../network/api_client.dart' show ApiException;
import '../services/circle_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/layout_insets.dart';
import '../utils/circle_cover.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/empty_state.dart';
import 'feed_screen.dart';

class CirclesScreen extends StatefulWidget {
  /// When true, used as a home tab (no local AppBar — shell provides chrome + bottom nav).
  final bool embedded;

  const CirclesScreen({super.key, this.embedded = false});

  static void clearCache() {
    _CirclesScreenState._allCache = null;
    _CirclesScreenState._featuredCache = null;
    _CirclesScreenState._cacheAt = null;
  }

  @override
  State<CirclesScreen> createState() => _CirclesScreenState();
}

class _CirclesScreenState extends State<CirclesScreen> {
  final _service = CircleService();
  List<Circle> _all = [];
  List<Circle> _featured = [];
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

  static List<Circle>? _allCache;
  static List<Circle>? _featuredCache;
  static DateTime? _cacheAt;
  static const _ttl = Duration(minutes: 5);

  bool get _cacheFresh =>
      _cacheAt != null && DateTime.now().difference(_cacheAt!) < _ttl;

  @override
  void initState() {
    super.initState();
    if (_allCache != null && _featuredCache != null) {
      _all = List<Circle>.from(_allCache!);
      _featured = List<Circle>.from(_featuredCache!);
      _loading = false;
      _load(silent: _cacheFresh);
    } else {
      _load();
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = _all.isEmpty;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _service.getCircles(),
        _service.getFeatured(),
      ]);
      if (!mounted) return;
      setState(() {
        _all = results[0];
        _featured = results[1];
        _loading = false;
        _error = null;
      });
      _allCache = List<Circle>.from(results[0]);
      _featuredCache = List<Circle>.from(results[1]);
      _cacheAt = DateTime.now();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_all.isEmpty) {
          _error = e is ApiException ? (e.message ?? 'Failed to load circles') : e.toString();
        }
      });
    }
  }

  Future<void> _toggleJoin(Circle circle) async {
    if (_busy.contains(circle.id)) return;
    setState(() => _busy.add(circle.id));
    HapticFeedback.selectionClick();

    try {
      if (circle.isJoined) {
        await _service.leave(circle.id);
        _patchCircle(circle.id, isJoined: false, memberDelta: -1);
        FeedScreen.clearCache();
        _allCache = List<Circle>.from(_all);
        _featuredCache = List<Circle>.from(_featured);
        _cacheAt = DateTime.now();
        customSnackBar('Success', 'Left ${circle.name}', type: SnackType.success);
      } else {
        final result = await _service.join(circle.id);
        final awarded = result['points_awarded'];
        _patchCircle(circle.id, isJoined: true, memberDelta: 1);
        FeedScreen.clearCache();
        _allCache = List<Circle>.from(_all);
        _featuredCache = List<Circle>.from(_featured);
        _cacheAt = DateTime.now();
        if (awarded is int && awarded > 0) {
          customSnackBar(
            'Success',
            '+$awarded Anchor Points — joined ${circle.name}!',
            type: SnackType.success,
          );
        } else {
          customSnackBar('Success', 'Joined ${circle.name}', type: SnackType.success);
        }
      }
    } catch (e) {
      customSnackBar(
        'Error',
        e is ApiException ? (e.message ?? 'Could not update membership') : e.toString(),
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _busy.remove(circle.id));
    }
  }

  void _patchCircle(String id, {required bool isJoined, required int memberDelta}) {
    setState(() {
      _all = _all
          .map((c) => c.id == id
              ? c.copyWith(
                  isJoined: isJoined,
                  memberCount: (c.memberCount + memberDelta).clamp(0, 999999),
                )
              : c)
          .toList();
      _featured = _featured
          .map((c) => c.id == id
              ? c.copyWith(
                  isJoined: isJoined,
                  memberCount: (c.memberCount + memberDelta).clamp(0, 999999),
                )
              : c)
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final showLocalAppBar = !widget.embedded && (ModalRoute.of(context)?.canPop ?? false);

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator(color: AppColors.primary));
    } else if (_error != null && _all.isEmpty) {
      body = EmptyState(
        title: "Couldn't load circles",
        subtitle: _error!,
        primaryLabel: 'Try again',
        onPrimary: _load,
        icon: Icons.groups_outlined,
      );
    } else if (_all.isEmpty) {
      body = EmptyState(
        title: 'No circles yet',
        subtitle: 'Topic communities will show up here once seeded.',
        primaryLabel: 'Refresh',
        onPrimary: _load,
        icon: Icons.groups_outlined,
      );
    } else {
      body = RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, widget.embedded ? 18 : 8, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!widget.embedded && !showLocalAppBar) ...[
                      Text('Circles', style: AppTextStyles.screenTitle),
                      const SizedBox(height: 4),
                    ],
                    Text('Find your people in topic communities', style: AppTextStyles.body),
                  ],
                ),
              ),
            ),
            if (_featured.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                  child: Text('Featured', style: AppTextStyles.sectionTitle),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 150,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _featured.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) => GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CircleDetailScreen(
                              circleId: _featured[i].id,
                              initial: _featured[i],
                            ),
                          ),
                        );
                      },
                      child: _FeaturedCircleCard(
                        circle: _featured[i],
                        busy: _busy.contains(_featured[i].id),
                        onToggle: () => _toggleJoin(_featured[i]),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Text('All circles', style: AppTextStyles.sectionTitle),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                widget.embedded ? LayoutInsets.navClearance(context) : 24,
              ),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.92,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final circle = _all[i];
                    return _CircleTile(
                      circle: circle,
                      busy: _busy.contains(circle.id),
                      onOpen: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CircleDetailScreen(
                              circleId: circle.id,
                              initial: circle,
                            ),
                          ),
                        );
                      },
                      onToggle: () => _toggleJoin(circle),
                    );
                  },
                  childCount: _all.length,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (widget.embedded) {
      return ColoredBox(color: AppColors.surface, child: body);
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: showLocalAppBar
            ? AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                systemOverlayStyle: SystemUiOverlayStyle.light,
                flexibleSpace: Container(
                  decoration: const BoxDecoration(gradient: AppColors.brandGradient),
                ),
                iconTheme: const IconThemeData(color: Colors.white),
                title: Text(
                  'Circles',
                  style: AppTextStyles.ui(size: 18, weight: FontWeight.w800, color: AppColors.white),
                ),
                centerTitle: true,
              )
            : null,
        body: body,
      ),
    );
  }

}

class _FeaturedCircleCard extends StatelessWidget {
  final Circle circle;
  final bool busy;
  final VoidCallback onToggle;

  const _FeaturedCircleCard({
    required this.circle,
    required this.busy,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 176,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('Featured', style: AppTextStyles.ui(size: 10, color: AppColors.white, weight: FontWeight.w700)),
              ),
              const Spacer(),
              Icon(Icons.groups_rounded, color: AppColors.white.withOpacity(0.9), size: 20),
            ],
          ),
          const Spacer(),
          Text(
            circle.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.ui(size: 15, weight: FontWeight.w800, color: AppColors.white),
          ),
          const SizedBox(height: 4),
          Text(
            '${circle.memberCount} members',
            style: AppTextStyles.ui(size: 11, color: AppColors.white.withOpacity(0.85)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: busy ? null : onToggle,
              style: TextButton.styleFrom(
                backgroundColor: circle.isJoined
                    ? AppColors.white.withOpacity(0.18)
                    : AppColors.white,
                foregroundColor: circle.isJoined ? AppColors.white : AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: circle.isJoined
                      ? BorderSide(color: AppColors.white.withOpacity(0.7), width: 1.5)
                      : BorderSide.none,
                ),
              ),
              child: busy
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: circle.isJoined ? AppColors.white : AppColors.primary,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          circle.isJoined ? Icons.check_rounded : Icons.add_rounded,
                          size: 16,
                          color: circle.isJoined ? AppColors.white : AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          circle.isJoined ? 'Joined' : 'Join',
                          style: AppTextStyles.ui(
                            size: 13,
                            weight: FontWeight.w800,
                            color: circle.isJoined ? AppColors.white : AppColors.primary,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleTile extends StatelessWidget {
  final Circle circle;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onToggle;

  const _CircleTile({
    required this.circle,
    required this.busy,
    required this.onOpen,
    required this.onToggle,
  });

  String _shortCount(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final cover = CircleCover.resolve(
      iconUrl: circle.iconUrl,
      slug: circle.slug,
      name: circle.name,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: onOpen,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  cover,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: AppColors.chipIdle),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.08),
                        Colors.black.withOpacity(0.45),
                        Colors.black.withOpacity(0.8),
                      ],
                      stops: const [0.0, 0.42, 1.0],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 44, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Spacer(),
                      Text(
                        circle.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.ui(size: 14, weight: FontWeight.w800, color: AppColors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_shortCount(circle.memberCount)} members',
                        style: AppTextStyles.ui(
                          size: 12,
                          color: AppColors.white.withOpacity(0.85),
                          weight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: busy ? null : onToggle,
                borderRadius: BorderRadius.circular(22),
                child: Ink(
                  decoration: BoxDecoration(
                    color: circle.isJoined ? const Color(0xE61A1214) : AppColors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: circle.isJoined ? AppColors.white.withOpacity(0.65) : AppColors.white,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  child: busy
                      ? SizedBox(
                          width: 54,
                          height: 16,
                          child: Center(
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: circle.isJoined ? AppColors.white : AppColors.primary,
                              ),
                            ),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              circle.isJoined ? Icons.check_rounded : Icons.add_rounded,
                              size: 16,
                              color: circle.isJoined ? AppColors.white : AppColors.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              circle.isJoined ? 'Joined' : 'Join',
                              style: AppTextStyles.ui(
                                size: 12,
                                weight: FontWeight.w800,
                                color: circle.isJoined ? AppColors.white : AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
