/// Rows per request. The Supabase API returns at most this many rows per
/// request (the project's "Max rows" setting), whatever `.limit()` asks for.
const apiPageSize = 1000;

/// Reads every row of a query, one page at a time. [page] gets the first and
/// last row index (inclusive) to read, as `.range(from, to)` takes them.
/// The query must have a stable order so pages do not overlap or skip rows.
Future<List<T>> fetchAllPages<T>(
  Future<List<T>> Function(int from, int to) page, {
  int pageSize = apiPageSize,
}) async {
  final all = <T>[];
  while (true) {
    final rows = await page(all.length, all.length + pageSize - 1);
    all.addAll(rows);
    if (rows.length < pageSize) return all;
  }
}
