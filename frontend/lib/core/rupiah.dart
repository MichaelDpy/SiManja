import 'package:intl/intl.dart';

/// R-MONEY: each stored value fits an exact JavaScript integer; totals use
/// BigInt so accumulation never wraps or rounds, including on Flutter Web.
abstract final class Rupiah {
  static const maxRecord = 9007199254740991;

  static BigInt exact(num value) {
    if (!value.isFinite ||
        value.abs() > maxRecord ||
        value != value.truncateToDouble()) {
      throw ArgumentError(
        'Nominal harus rupiah bulat dalam batas yang didukung.',
      );
    }
    return BigInt.from(value);
  }

  static String digits(Object value) {
    if (value is BigInt) return value.toString();
    if (value is num) return exact(value).toString();
    throw ArgumentError('Nominal bukan nilai rupiah.');
  }

  static String format(Object value, {String symbol = 'Rp '}) {
    final raw = digits(value);
    final negative = raw.startsWith('-');
    final magnitude = negative ? raw.substring(1) : raw;
    final grouped = magnitude.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (match) => '${match[1]}.',
    );
    return '${negative ? '-' : ''}$symbol$grouped';
  }

  /// Display averages in whole rupiah; ties round away from zero.
  static BigInt average(BigInt sum, int count) {
    if (count <= 0) throw ArgumentError.value(count, 'count');
    final divisor = BigInt.from(count);
    final rounded = (sum.abs() + divisor ~/ BigInt.two) ~/ divisor;
    return sum.isNegative ? -rounded : rounded;
  }
}

extension ExactRupiahFormat on NumberFormat {
  String rupiah(Object value) => Rupiah.format(value, symbol: currencySymbol);
}
