/// Resolves a cover image for a circle (API icon_url or topic fallback).
class CircleCover {
  CircleCover._();

  static const Map<String, String> _bySlug = {
    'fitness-health':
        'https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?auto=format&fit=crop&w=900&q=80',
    'food-cooking':
        'https://images.unsplash.com/photo-1556910103-1c02745aae4d?auto=format&fit=crop&w=900&q=80',
    'books-reading':
        'https://images.unsplash.com/photo-1512820790803-83ca734da794?auto=format&fit=crop&w=900&q=80',
    'travel':
        'https://images.unsplash.com/photo-1488646953014-85cb44e25828?auto=format&fit=crop&w=900&q=80',
    'faith-values':
        'https://images.unsplash.com/photo-1507692049790-de58290a4334?auto=format&fit=crop&w=900&q=80',
    'music-arts':
        'https://images.unsplash.com/photo-1511379938547-c1f69419868d?auto=format&fit=crop&w=900&q=80',
    'career-growth':
        'https://images.unsplash.com/photo-1521737711867-e3b97375f902?auto=format&fit=crop&w=900&q=80',
  };

  static const String _fallback =
      'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?auto=format&fit=crop&w=900&q=80';

  static String resolve({String? iconUrl, String? slug, String? name}) {
    final fromApi = iconUrl?.trim();
    if (fromApi != null && fromApi.isNotEmpty) return fromApi;

    final key = (slug ?? '').trim().toLowerCase();
    if (key.isNotEmpty && _bySlug.containsKey(key)) return _bySlug[key]!;

    final n = (name ?? '').toLowerCase();
    if (n.contains('fit') || n.contains('health')) return _bySlug['fitness-health']!;
    if (n.contains('food') || n.contains('cook')) return _bySlug['food-cooking']!;
    if (n.contains('book') || n.contains('read')) return _bySlug['books-reading']!;
    if (n.contains('travel')) return _bySlug['travel']!;
    if (n.contains('faith') || n.contains('value')) return _bySlug['faith-values']!;
    if (n.contains('music') || n.contains('art')) return _bySlug['music-arts']!;
    if (n.contains('career') || n.contains('growth')) return _bySlug['career-growth']!;

    return _fallback;
  }
}
