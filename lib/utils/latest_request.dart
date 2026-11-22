/// Tells a screen whether a finished load is still the latest one, so an
/// older, slower answer (an earlier search or period) does not replace the
/// newer one.
///
///     final request = _latest.start();
///     final rows = await fetch();
///     if (!mounted || !_latest.isLatest(request)) return;
class LatestRequest {
  int _current = 0;

  /// Starts a new request and returns its number.
  int start() => ++_current;

  bool isLatest(int request) => request == _current;
}
