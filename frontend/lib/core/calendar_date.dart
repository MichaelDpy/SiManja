/// R-DATE: transaction dates are calendar components, not instants.
/// UTC midnight is a carrier for those components, never a timezone conversion.
abstract final class CalendarDate {
  static DateTime canonical(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static bool same(DateTime a, DateTime b) => canonical(a) == canonical(b);
}
