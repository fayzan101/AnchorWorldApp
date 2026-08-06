/// Encode/decode multi-select profile style fields stored as a single varchar.
/// Options never contain `|`, so pipe-join is safe and backward-compatible with
/// older single-value rows.
class ProfileStyleCodec {
  ProfileStyleCodec._();

  static const separator = '|';

  static Set<String> decode(String? raw) {
    if (raw == null) return {};
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return {};
    // Legacy single values had no separator.
    if (!trimmed.contains(separator)) return {trimmed};
    return trimmed
        .split(separator)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  static String? encode(Iterable<String> values) {
    final cleaned = values.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (cleaned.isEmpty) return null;
    return cleaned.join(separator);
  }

  static String display(String? raw, {String empty = ''}) {
    final parts = decode(raw).toList();
    if (parts.isEmpty) return empty;
    return parts.join(' · ');
  }
}
