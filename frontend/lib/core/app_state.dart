import 'package:flutter/foundation.dart';

import 'mock_data.dart';

/// Global in-memory state untuk aplikasi SIMANJA.
///
/// Diakses via [AppState.instance] (singleton).
///
/// Kontrak (lihat 00-panduan-tim.md § Kontrak antarmodul):
/// - Satu-satunya sumber transaksi adalah [transactions] — daftar immutable.
/// - Widget tidak boleh memodifikasi daftar secara langsung.
/// - Mutasi ([addTransaction], [updateTransaction], [deleteTransaction])
///   bersifat [Future<void>] agar call site menunggu dengan await.
/// - Edit memakai ID stabil, bukan indeks daftar tersaring.
/// - [transactionsLoading] dan [transactionsError] menyediakan state
///   untuk UI loading/error; [retryTransactions] untuk mencoba ulang.
/// - Implementasi lokal langsung selesai (tidak ada I/O async nyata);
///   kontrak Future tetap terpenuhi sehingga C6 bisa mengganti
///   implementasi tanpa mengubah call site.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  // ── Profil User ────────────────────────────────────────────────────────
  String name = MockData.dummyUser.name;
  String email = MockData.dummyUser.email;
  String phone = MockData.dummyUser.phone;
  String address = MockData.dummyUser.address;
  String city = MockData.dummyUser.city;
  String job = MockData.dummyUser.job;
  double monthlyIncome = MockData.dummyUser.monthlyIncome;

  /// Path lokal foto profil (null = belum ada foto).
  String? photoPath;

  // ── Preferensi ─────────────────────────────────────────────────────────
  bool notifEnabled = true;
  bool darkMode = true;

  // ── Transaksi ──────────────────────────────────────────────────────────

  List<TransactionModel> _transactions = List.from(MockData.transactions);

  /// Daftar transaksi yang tidak dapat diubah langsung oleh widget.
  /// Diurutkan: tanggal terbaru dulu, ID sebagai pembanding stabil.
  List<TransactionModel> get transactions => List.unmodifiable(_transactions);

  /// true saat operasi transaksi sedang berjalan (lokal: selalu false).
  bool transactionsLoading = false;

  /// Pesan error terakhir dari operasi transaksi; null = tidak ada error.
  String? transactionsError;

  // ── Computed ───────────────────────────────────────────────────────────

  double get totalIncome =>
      _transactions.where((t) => t.isIncome).fold(0.0, (s, t) => s + t.amount);

  double get totalExpense =>
      _transactions.where((t) => !t.isIncome).fold(0.0, (s, t) => s + t.amount);

  // ── Profil actions ─────────────────────────────────────────────────────

  void updateProfile({
    required String newName,
    required String newEmail,
    required String newPhone,
    required String newAddress,
    required String newCity,
    required String newJob,
    required double newIncome,
  }) {
    name = newName;
    email = newEmail;
    phone = newPhone;
    address = newAddress;
    city = newCity;
    job = newJob;
    monthlyIncome = newIncome;
    notifyListeners();
  }

  void updatePhoto(String path) {
    photoPath = path.isEmpty ? null : path;
    notifyListeners();
  }

  void setNotif(bool val) {
    notifEnabled = val;
    notifyListeners();
  }

  void setDarkMode(bool val) {
    darkMode = val;
    notifyListeners();
  }

  // ── Transaksi actions ──────────────────────────────────────────────────

  /// Tambah transaksi baru.
  ///
  /// Validasi [amount] dilakukan di sini; lempar [ArgumentError] jika gagal.
  /// Implementasi lokal langsung selesai; C6 mengganti dengan Firestore.
  Future<void> addTransaction(TransactionModel tx) async {
    TransactionModel.validate(tx.amount);
    _transactions = [tx, ..._transactions];
    _sortTransactions();
    notifyListeners();
  }

  /// Edit transaksi berdasarkan [id] stabil — bukan indeks daftar tersaring.
  ///
  /// Lempar [ArgumentError] jika ID tidak ditemukan.
  Future<void> updateTransaction(String id, TransactionModel tx) async {
    TransactionModel.validate(tx.amount);
    final idx = _transactions.indexWhere((t) => t.id == id);
    if (idx == -1) {
      throw ArgumentError('Transaksi dengan id=$id tidak ditemukan');
    }
    final updated = List<TransactionModel>.from(_transactions);
    updated[idx] = tx;
    _transactions = updated;
    _sortTransactions();
    notifyListeners();
  }

  /// Hapus transaksi berdasarkan [id].
  ///
  /// Tidak error jika ID tidak ada (idempoten).
  Future<void> deleteTransaction(String id) async {
    _transactions = _transactions.where((t) => t.id != id).toList();
    notifyListeners();
  }

  /// Coba muat ulang transaksi (lokal: reset ke fixture demo).
  ///
  /// C6 mengganti ini dengan re-fetch dari Firestore.
  Future<void> retryTransactions() async {
    transactionsLoading = true;
    transactionsError = null;
    notifyListeners();
    // Implementasi lokal: langsung pakai data demo
    _transactions = List.from(MockData.transactions);
    _sortTransactions();
    transactionsLoading = false;
    notifyListeners();
  }

  /// Buat ID transaksi baru yang unik.
  ///
  /// Format: `TRX<millisecondsSinceEpoch>`.
  /// Tahap cloud memeriksa benturan; jangan hanya andalkan timestamp.
  String generateId() => 'TRX${DateTime.now().millisecondsSinceEpoch}';

  // ── Reset ──────────────────────────────────────────────────────────────

  /// Reset semua data ke default saat logout.
  ///
  /// C6/C4: saat logout, hentikan stream Firestore dan kosongkan data
  /// sebelum mengembalikan ke halaman login.
  void reset() {
    name = MockData.dummyUser.name;
    email = MockData.dummyUser.email;
    phone = MockData.dummyUser.phone;
    address = MockData.dummyUser.address;
    city = MockData.dummyUser.city;
    job = MockData.dummyUser.job;
    monthlyIncome = MockData.dummyUser.monthlyIncome;
    photoPath = null;
    notifEnabled = true;
    darkMode = true;
    transactionsLoading = false;
    transactionsError = null;
    _transactions = List.from(MockData.transactions);
    _sortTransactions();
    notifyListeners();
  }

  // ── Private ────────────────────────────────────────────────────────────

  void _sortTransactions() {
    _transactions.sort((a, b) {
      final d = b.date.compareTo(a.date);
      return d != 0 ? d : a.id.compareTo(b.id);
    });
  }
}
