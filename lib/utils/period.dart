/// The period choices on the Bills, Stock-ins and Returns screens.
enum ReportPeriod {
  today('Today'),
  week('7 days'),
  month('30 days'),
  all('All');

  const ReportPeriod(this.label);
  final String label;

  /// The choices on screens that have no "Today".
  static const withoutToday = [week, month, all];

  /// Start of the period (local midnight), or null for all time.
  DateTime? get from => fromDate(DateTime.now());

  /// [from] as seen at [now].
  DateTime? fromDate(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      ReportPeriod.today => today,
      ReportPeriod.week => DateTime(today.year, today.month, today.day - 6),
      ReportPeriod.month => DateTime(today.year, today.month, today.day - 29),
      ReportPeriod.all => null,
    };
  }
}
