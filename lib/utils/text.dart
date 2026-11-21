/// Trimmed text, or null when it is empty.
String? blankToNull(String? s) =>
    s == null || s.trim().isEmpty ? null : s.trim();

/// Search text safe to put in a PostgREST `or(...)` filter: characters that
/// have a meaning in the filter syntax become spaces.
String cleanSearch(String search) =>
    search.replaceAll(RegExp(r'[,()%*]'), ' ').trim();
