import 'package:flutter/material.dart';

import 'mock_data.dart';

/// Global in-memory state untuk aplikasi SIMANJA.
/// Diakses via AppState.instance (singleton).
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
  String? photoPath; // path lokal foto profil

  // ── Preferensi ─────────────────────────────────────────────────────────
  bool notifEnabled = true;
  bool darkMode = true;

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

  // ── Transaksi ──────────────────────────────────────────────────────────
  final List<TransactionModel> _transactions = List.from(MockData.transactions);

  List<TransactionModel> get transactions => List.unmodifiable(_transactions);

  double get totalIncome =>
      _transactions.where((t) => t.isIncome).fold(0, (s, t) => s + t.amount);

  double get totalExpense =>
      _transactions.where((t) => !t.isIncome).fold(0, (s, t) => s + t.amount);

  void addTransaction(TransactionModel tx) {
    _transactions.insert(0, tx);
    notifyListeners();
  }

  void updateTransaction(int index, TransactionModel tx) {
    _transactions[index] = tx;
    notifyListeners();
  }

  void deleteTransaction(String id) {
    _transactions.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  String generateId() {
    return 'TRX${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Reset semua data ke default saat logout
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
    _transactions
      ..clear()
      ..addAll(MockData.transactions);
    notifyListeners();
  }
}
