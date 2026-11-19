import 'package:flutter/foundation.dart';

import 'mock_data.dart';
import '../models/user_profile.dart';
import '../repositories/profile_repository.dart';

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
  AppState._() : _allowLocalProfile = false;
  @visibleForTesting
  AppState.forTesting({ProfileRepository? profiles})
    : _profileRepository = profiles,
      _allowLocalProfile = profiles == null;
  static final AppState instance = AppState._();

  ProfileRepository? _profileRepository;
  bool _allowLocalProfile;
  UserProfile? _loadedProfile;
  Future<void>? _profileLoad;
  bool profileLoading = false;
  bool profileSaving = false;
  bool profileReady = false;
  String? profileError;

  bool get hasProfileRepository => _profileRepository != null;
  void useProfileRepository(ProfileRepository repository) {
    _profileRepository = repository;
    _allowLocalProfile = false;
  }

  String? sessionUid;
  int _sessionRevision = 0;
  int get sessionRevision => _sessionRevision;

  Future<void> beginSession(String uid, String authEmail) {
    if (sessionUid != uid) {
      _clearUserData();
      sessionUid = uid;
      name = authEmail.isEmpty ? 'Pengguna' : authEmail.split('@').first;
    }
    email = authEmail;
    if (!profileReady) return retryProfile();
    notifyListeners();
    return Future.value();
  }

  Future<void> retryProfile() {
    if (sessionUid == null) return Future.value();
    if (profileLoading) return _profileLoad ?? Future.value();
    final uid = sessionUid!;
    final revision = _sessionRevision;
    final repository = _profileRepository;
    profileLoading = true;
    profileError = null;
    profileReady = false;
    notifyListeners();
    final request = _loadProfile(repository, uid, email, revision);
    _profileLoad = request;
    return request;
  }

  Future<void> _loadProfile(
    ProfileRepository? repository,
    String uid,
    String authEmail,
    int revision,
  ) async {
    try {
      if (repository == null && !_allowLocalProfile) {
        throw StateError('Repository profil belum siap.');
      }
      final profile = repository == null
          ? _currentProfile()
          : await repository.loadOrCreate(uid, authEmail);
      profile.toMap();
      if (revision != _sessionRevision) return;
      _applyProfile(profile);
      _loadedProfile = profile;
      profileReady = true;
    } catch (error) {
      if (revision == _sessionRevision) {
        profileError = error is FormatException || error is ArgumentError
            ? 'Data profil tidak valid. Periksa data akun sebelum mencoba lagi.'
            : 'Profil belum dapat dimuat. Periksa koneksi dan coba lagi.';
      }
    } finally {
      if (revision == _sessionRevision) {
        profileLoading = false;
        _profileLoad = null;
        notifyListeners();
      }
    }
  }

  UserProfile _currentProfile() => UserProfile(
    name: name,
    phone: phone,
    address: address,
    city: city,
    job: job,
    monthlyIncome: monthlyIncome,
    darkMode: darkMode,
    notifEnabled: notifEnabled,
  );

  void _applyProfile(UserProfile profile) {
    name = profile.name;
    phone = profile.phone;
    address = profile.address;
    city = profile.city;
    job = profile.job;
    monthlyIncome = profile.monthlyIncome;
    darkMode = profile.darkMode;
    notifEnabled = profile.notifEnabled;
  }

  Future<void> _saveProfile(UserProfile candidate) async {
    final profile = UserProfile.fromMap(candidate.toMap());
    if (!profileReady || (sessionUid == null && !_allowLocalProfile)) {
      throw StateError('Profil belum siap.');
    }
    if (profileSaving) throw StateError('Penyimpanan profil masih berjalan.');
    final repository = _profileRepository;
    if (repository == null && !_allowLocalProfile) {
      throw StateError('Repository profil belum siap.');
    }
    final uid = sessionUid;
    final revision = _sessionRevision;
    final previous = _loadedProfile ?? _currentProfile();
    profileSaving = true;
    notifyListeners();
    try {
      if (repository != null) {
        await repository.save(uid!, profile, previous: previous);
      }
      if (revision != _sessionRevision) throw StateError('Sesi telah berubah.');
      _loadedProfile = profile;
      _applyProfile(profile);
    } finally {
      if (revision == _sessionRevision) {
        profileSaving = false;
        notifyListeners();
      }
    }
  }

  /// Logout tidak memuat fixture. Tema tetap preferensi perangkat pada tahap ini.
  void clearSession() {
    _clearUserData();
    notifyListeners();
  }

  void _clearUserData() {
    _sessionRevision++;
    sessionUid = null;
    name = '';
    email = '';
    phone = '';
    address = '';
    city = '';
    job = '';
    monthlyIncome = 0;
    photoPath = null;
    notifEnabled = true;
    _transactions = [];
    transactionsLoading = false;
    transactionsError = null;
    _loadedProfile = null;
    _profileLoad = null;
    profileLoading = false;
    profileSaving = false;
    profileReady = false;
    profileError = null;
  }

  // ── Profil User ────────────────────────────────────────────────────────
  String name = '';
  String email = '';
  String phone = '';
  String address = '';
  String city = '';
  String job = '';
  double monthlyIncome = 0;

  /// Path lokal foto profil (null = belum ada foto).
  String? photoPath;

  // ── Preferensi ─────────────────────────────────────────────────────────
  bool notifEnabled = true;
  bool darkMode = true;

  // ── Transaksi ──────────────────────────────────────────────────────────

  List<TransactionModel> _transactions = [];

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

  Future<void> updateProfile({
    required String newName,
    required String newEmail,
    required String newPhone,
    required String newAddress,
    required String newCity,
    required String newJob,
    required double newIncome,
  }) async {
    if (newEmail.trim() != email) {
      throw ArgumentError('Email identitas tidak dapat diubah dari profil.');
    }
    await _saveProfile(
      _currentProfile().copyWith(
        name: newName,
        phone: newPhone,
        address: newAddress,
        city: newCity,
        job: newJob,
        monthlyIncome: newIncome,
      ),
    );
  }

  void updatePhoto(String path) {
    photoPath = path.isEmpty ? null : path;
    notifyListeners();
  }

  Future<void> setNotif(bool val) =>
      _saveProfile(_currentProfile().copyWith(notifEnabled: val));

  Future<void> setDarkMode(bool val) =>
      _saveProfile(_currentProfile().copyWith(darkMode: val));

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

  /// Periksa ulang state lokal tanpa mengisi data contoh akun lain.
  ///
  /// C6 mengganti ini dengan re-fetch dari Firestore.
  Future<void> retryTransactions() async {
    transactionsLoading = true;
    transactionsError = null;
    notifyListeners();
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

  /// Fixture eksplisit untuk tes frontend; tidak dipanggil alur logout.
  ///
  /// C6/C4: saat logout, hentikan stream Firestore dan kosongkan data
  /// sebelum mengembalikan ke halaman login.
  @visibleForTesting
  void reset() {
    _clearUserData();
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
    _allowLocalProfile = true;
    profileReady = true;
    _loadedProfile = _currentProfile();
    notifyListeners();
  }

  // ── Private ────────────────────────────────────────────────────────────

  void _sortTransactions() {
    _transactions.sort((a, b) {
      final d = b.date.compareTo(a.date);
      return d != 0 ? d : a.id.compareTo(b.id);
    });
  }

  @override
  void dispose() {
    _sessionRevision++;
    super.dispose();
  }
}
