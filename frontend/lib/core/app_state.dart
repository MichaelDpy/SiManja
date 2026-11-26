import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'finance_summary.dart';
import 'mock_data.dart';
import '../models/user_profile.dart';
import '../models/record_version.dart';
import '../repositories/profile_repository.dart';
import '../repositories/transaction_repository.dart';

/// Facade tunggal untuk profil dan stream transaksi milik UID aktif.
/// Implementasi lokal hanya tersedia untuk fixture pengujian eksplisit.
class AppState extends ChangeNotifier {
  AppState._() : _allowLocalProfile = false, _allowLocalTransactions = false;
  @visibleForTesting
  AppState.forTesting({
    ProfileRepository? profiles,
    TransactionRepository? transactions,
  }) : _profileRepository = profiles,
       _allowLocalProfile = profiles == null,
       _transactionRepository = transactions,
       _allowLocalTransactions = transactions == null;
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

  TransactionRepository? _transactionRepository;
  bool _allowLocalTransactions;
  StreamSubscription<TransactionSnapshot>? _transactionSubscription;
  int _transactionGeneration = 0;
  String? _streamUid;
  final Set<String> _mutatingIds = {};
  int pendingMutations = 0;
  bool transactionsFromCache = false;
  bool transactionsHasPendingWrites = false;
  bool get hasTransactionRepository => _transactionRepository != null;

  void useTransactionRepository(TransactionRepository repository) {
    if (identical(_transactionRepository, repository)) return;
    _transactionGeneration++;
    _transactionSubscription?.cancel();
    _transactionSubscription = null;
    _streamUid = null;
    _transactionRepository = repository;
    _allowLocalTransactions = false;
  }

  void _startTransactionsIfNeeded() {
    if (profileReady && sessionUid != null && _streamUid != sessionUid) {
      unawaited(retryTransactions());
    }
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
    _startTransactionsIfNeeded();
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
      _startTransactionsIfNeeded();
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
    version: _loadedProfile?.version,
  );

  UserProfile get profileSnapshot => _currentProfile();

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

  Future<void> _saveProfile(
    UserProfile candidate, {
    UserProfile? previous,
  }) async {
    var profile = UserProfile.fromMap(
      candidate.toMap(),
      version: candidate.version,
    );
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
    final base = previous ?? _loadedProfile ?? _currentProfile();
    profileSaving = true;
    notifyListeners();
    try {
      if (repository != null) {
        profile = await repository.save(uid!, profile, previous: base);
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
    _transactionGeneration++;
    _transactionSubscription?.cancel();
    _transactionSubscription = null;
    _streamUid = null;
    _mutatingIds.clear();
    pendingMutations = 0;
    transactionsFromCache = false;
    transactionsHasPendingWrites = false;
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

  /// Menunggu snapshot pertama dari langganan aktif.
  bool transactionsLoading = false;

  /// Pesan kegagalan langganan; kegagalan write dikembalikan ke pemanggil.
  String? transactionsError;

  // ── Computed ───────────────────────────────────────────────────────────

  BigInt get totalIncome => FinanceSummary.totalIncome(_transactions);

  BigInt get totalExpense => FinanceSummary.totalExpense(_transactions);

  // ── Profil actions ─────────────────────────────────────────────────────

  Future<void> updateProfile({
    required String newName,
    required String newEmail,
    required String newPhone,
    required String newAddress,
    required String newCity,
    required String newJob,
    required double newIncome,
    UserProfile? previous,
  }) async {
    if (newEmail.trim() != email) {
      throw ArgumentError('Email identitas tidak dapat diubah dari profil.');
    }
    await _saveProfile(
      (previous ?? _currentProfile()).copyWith(
        name: newName,
        phone: newPhone,
        address: newAddress,
        city: newCity,
        job: newJob,
        monthlyIncome: newIncome,
      ),
      previous: previous,
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
  /// Runtime menunggu konfirmasi repository; daftar diperbarui oleh stream.
  Future<void> addTransaction(TransactionModel tx) async {
    TransactionModel.validate(tx.amount);
    if (_allowLocalTransactions) {
      if (_transactions.any((item) => item.id == tx.id)) {
        throw StateError('ID sudah digunakan.');
      }
      _transactions = [tx, ..._transactions];
      _sortTransactions();
      notifyListeners();
      return;
    }
    TransactionMapper.toMap(tx);
    await _mutate(tx.id, (repository, uid) => repository.add(uid, tx));
  }

  Future<void> updateTransaction(String id, TransactionModel tx) async {
    TransactionModel.validate(tx.amount);
    if (id != tx.id) throw ArgumentError('ID transaksi tidak boleh berubah.');
    if (_allowLocalTransactions) {
      final index = _transactions.indexWhere((item) => item.id == id);
      if (index == -1) throw ArgumentError('Transaksi tidak ditemukan.');
      _transactions = List.from(_transactions)..[index] = tx;
      _sortTransactions();
      notifyListeners();
      return;
    }
    TransactionMapper.toMap(tx);
    await _mutate(id, (repository, uid) => repository.update(uid, id, tx));
  }

  Future<void> deleteTransaction(
    String id, {
    TransactionModel? previous,
  }) async {
    if (previous != null && previous.id != id) {
      throw ArgumentError('ID snapshot hapus tidak cocok.');
    }
    if (_allowLocalTransactions) {
      _transactions = _transactions.where((item) => item.id != id).toList();
      notifyListeners();
      return;
    }
    TransactionMapper.validateId(id);
    final base =
        previous ?? _transactions.where((tx) => tx.id == id).firstOrNull;
    await _mutate(
      id,
      (repository, uid) =>
          repository.delete(uid, id, expectedVersion: base?.version),
    );
  }

  Future<void> _mutate(
    String id,
    Future<void> Function(TransactionRepository, String) action,
  ) async {
    final repository = _transactionRepository;
    final uid = sessionUid;
    if (repository == null || uid == null || !profileReady) {
      throw StateError('Sesi transaksi belum siap.');
    }
    if (!_mutatingIds.add(id)) {
      throw StateError('Transaksi ini masih diproses.');
    }
    final revision = _sessionRevision;
    pendingMutations++;
    notifyListeners();
    try {
      await action(repository, uid);
      if (revision != _sessionRevision) throw StateError('Sesi telah berubah.');
    } on RecordConflict {
      rethrow;
    } catch (_) {
      throw StateError(
        'Perubahan belum dikonfirmasi server. Periksa koneksi atau izin akun.',
      );
    } finally {
      if (revision == _sessionRevision) {
        pendingMutations--;
        _mutatingIds.remove(id);
        notifyListeners();
      }
    }
  }

  Future<void> retryTransactions() async {
    if (_allowLocalTransactions) {
      transactionsLoading = false;
      transactionsError = null;
      _sortTransactions();
      notifyListeners();
      return;
    }
    final uid = sessionUid;
    final repository = _transactionRepository;
    if (uid == null || repository == null) return;
    final revision = _sessionRevision;
    final generation = ++_transactionGeneration;
    _transactionSubscription?.cancel();
    _transactionSubscription = null;
    _streamUid = uid;
    transactionsLoading = true;
    transactionsError = null;
    notifyListeners();
    bool active() =>
        revision == _sessionRevision && generation == _transactionGeneration;
    void failed(Object error) {
      if (!active()) return;
      transactionsLoading = false;
      transactionsError = error is FormatException || error is ArgumentError
          ? 'Ada data transaksi tidak valid. Periksa data akun sebelum mencoba lagi.'
          : 'Transaksi belum dapat dimuat. Periksa koneksi lalu coba lagi.';
      notifyListeners();
    }

    try {
      _transactionSubscription = repository
          .watch(uid)
          .listen(
            (snapshot) {
              scheduleMicrotask(() {
                if (!active()) return;
                _transactions = List.from(snapshot.transactions);
                _sortTransactions();
                transactionsFromCache = snapshot.fromCache;
                transactionsHasPendingWrites = snapshot.hasPendingWrites;
                transactionsLoading = false;
                transactionsError = null;
                notifyListeners();
              });
            },
            onError: (Object error) => scheduleMicrotask(() => failed(error)),
            onDone: () =>
                scheduleMicrotask(() => failed(StateError('Stream terputus.'))),
          );
    } catch (error) {
      failed(error);
    }
  }

  String generateId() {
    if (!_allowLocalTransactions) {
      if (sessionUid == null || _transactionRepository == null) {
        throw StateError('Sesi transaksi belum siap.');
      }
      return _transactionRepository!.newId(sessionUid!);
    }
    final random = Random.secure();
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(
      20,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  // ── Reset ──────────────────────────────────────────────────────────────

  /// Fixture eksplisit untuk tes frontend; tidak dipanggil alur logout.
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
    _allowLocalTransactions = true;
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
    _transactionGeneration++;
    _transactionSubscription?.cancel();
    super.dispose();
  }
}
