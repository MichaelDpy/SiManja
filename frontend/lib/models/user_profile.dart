class UserProfile {
  const UserProfile({
    required this.name,
    this.phone = '',
    this.address = '',
    this.city = '',
    this.job = '',
    this.monthlyIncome = 0,
    this.darkMode = true,
    this.notifEnabled = true,
  });

  static const maxRupiah = 9007199254740991;
  final String name, phone, address, city, job;
  final double monthlyIncome;
  final bool darkMode, notifEnabled;

  factory UserProfile.initial(String email) {
    final prefix = email.trim().split('@').first;
    return UserProfile(
      name: prefix.isEmpty
          ? 'Pengguna'
          : prefix.substring(0, prefix.length > 120 ? 120 : prefix.length),
    );
  }

  static String? validateName(String? input) {
    final value = input?.trim() ?? '';
    if (value.isEmpty) return 'Nama wajib diisi';
    return value.length > 120 ? 'Nama maksimal 120 karakter' : null;
  }

  static String? validatePhone(String? input) {
    final value = input?.trim() ?? '';
    if (value.isEmpty) return null;
    final digits = value.replaceAll(RegExp(r'[\s\-+()]'), '');
    if (value.length > 30 || !RegExp(r'^\d{9,15}$').hasMatch(digits)) {
      return 'Format nomor telepon tidak valid';
    }
    return null;
  }

  /// Rupiah bulat: menerima 5000000 atau 5.000.000, menolak desimal/format ambigu.
  static double? parseIncome(String input) {
    final value = input.trim();
    if (value.isEmpty) return 0;
    if (!RegExp(r'^\d+$').hasMatch(value) &&
        !RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(value)) {
      return null;
    }
    final amount = double.tryParse(value.replaceAll('.', ''));
    if (amount == null ||
        !amount.isFinite ||
        amount < 0 ||
        amount > maxRupiah ||
        amount != amount.roundToDouble()) {
      return null;
    }
    return amount;
  }

  Map<String, Object> toMap() {
    final error = validateName(name) ?? validatePhone(phone);
    if (error != null) throw ArgumentError(error);
    if (address.trim().length > 500 ||
        city.trim().length > 120 ||
        job.trim().length > 120) {
      throw ArgumentError('Alamat, kota, atau pekerjaan terlalu panjang.');
    }
    if (!monthlyIncome.isFinite ||
        monthlyIncome < 0 ||
        monthlyIncome > maxRupiah ||
        monthlyIncome != monthlyIncome.roundToDouble()) {
      throw ArgumentError('Pendapatan harus berupa rupiah bulat non-negatif.');
    }
    return {
      'name': name.trim(),
      'phone': phone.trim(),
      'address': address.trim(),
      'city': city.trim(),
      'job': job.trim(),
      'monthlyIncome': monthlyIncome.toInt(),
      'darkMode': darkMode,
      'notifEnabled': notifEnabled,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> data) {
    for (final field in ['name', 'phone', 'address', 'city', 'job']) {
      if (data[field] is! String) {
        throw const FormatException('Field profil tidak valid.');
      }
    }
    if (data['monthlyIncome'] is! int ||
        data['darkMode'] is! bool ||
        data['notifEnabled'] is! bool) {
      throw const FormatException(
        'Nominal atau preferensi profil tidak valid.',
      );
    }
    final result = UserProfile(
      name: data['name'],
      phone: data['phone'],
      address: data['address'],
      city: data['city'],
      job: data['job'],
      monthlyIncome: (data['monthlyIncome'] as int).toDouble(),
      darkMode: data['darkMode'],
      notifEnabled: data['notifEnabled'],
    );
    result.toMap();
    return result;
  }

  UserProfile copyWith({
    String? name,
    String? phone,
    String? address,
    String? city,
    String? job,
    double? monthlyIncome,
    bool? darkMode,
    bool? notifEnabled,
  }) => UserProfile(
    name: name ?? this.name,
    phone: phone ?? this.phone,
    address: address ?? this.address,
    city: city ?? this.city,
    job: job ?? this.job,
    monthlyIncome: monthlyIncome ?? this.monthlyIncome,
    darkMode: darkMode ?? this.darkMode,
    notifEnabled: notifEnabled ?? this.notifEnabled,
  );

  Map<String, Object> changesSince(UserProfile previous) {
    final before = previous.toMap();
    return Map.fromEntries(
      toMap().entries.where((entry) => before[entry.key] != entry.value),
    );
  }
}
