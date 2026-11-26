import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/calendar_date.dart';
import '../core/rupiah.dart';
import '../models/transaction_model.dart';

class TransactionSnapshot {
  TransactionSnapshot(
    List<TransactionModel> transactions, {
    this.fromCache = false,
    this.hasPendingWrites = false,
  }) : transactions = List.unmodifiable(transactions);

  final List<TransactionModel> transactions;
  final bool fromCache;
  final bool hasPendingWrites;
}

abstract interface class TransactionRepository {
  String newId(String uid);
  Stream<TransactionSnapshot> watch(String uid);
  Future<void> add(String uid, TransactionModel transaction);
  Future<void> update(String uid, String id, TransactionModel transaction);
  Future<void> delete(String uid, String id);
}

abstract final class TransactionMapper {
  static const maxRupiah = Rupiah.maxRecord;
  static const dateVersion = 2;

  static void validateId(String id) {
    if (id.trim().isEmpty ||
        id.contains('/') ||
        id == '.' ||
        id == '..' ||
        utf8.encode(id).length > 1500) {
      throw ArgumentError('ID dokumen tidak valid.');
    }
  }

  static Map<String, Object> toMap(TransactionModel transaction) {
    validateId(transaction.id);
    TransactionModel.validate(transaction.amount);
    if (transaction.amount > maxRupiah ||
        transaction.category.trim().isEmpty ||
        transaction.category.trim().length > 120 ||
        transaction.description.trim().isEmpty ||
        transaction.description.trim().length > 1000) {
      throw ArgumentError(
        'Kategori, keterangan, nominal, atau tanggal transaksi tidak valid.',
      );
    }
    final legacy = transaction.legacyDate;
    final storedDate = legacy == null
        ? Timestamp.fromDate(CalendarDate.canonical(transaction.date))
        : Timestamp(legacy.seconds, legacy.nanoseconds);
    final instant = storedDate.toDate().toUtc();
    if (instant.isBefore(DateTime.utc(1900)) ||
        !instant.isBefore(DateTime.utc(2201))) {
      throw ArgumentError('Tanggal di luar rentang.');
    }
    if (legacy != null &&
        !CalendarDate.same(transaction.date, instant.toLocal())) {
      throw ArgumentError('Tanggal legacy perlu dikonfirmasi ulang.');
    }
    return {
      'category': transaction.category.trim(),
      'description': transaction.description.trim(),
      'amount': transaction.amount.toInt(),
      'isIncome': transaction.isIncome,
      'date': storedDate,
      if (legacy == null) 'dateVersion': dateVersion,
    };
  }

  static TransactionModel fromMap(
    String id,
    Map<String, dynamic> data, {
    bool allowPendingTimestamps = false,
  }) {
    if (data['category'] is! String ||
        data['description'] is! String ||
        data['amount'] is! int ||
        data['isIncome'] is! bool ||
        data['date'] is! Timestamp) {
      throw const FormatException('Dokumen transaksi tidak valid.');
    }
    for (final field in ['createdAt', 'updatedAt']) {
      if (!data.containsKey(field) ||
          (data[field] is! Timestamp &&
              !(allowPendingTimestamps && data[field] == null))) {
        throw const FormatException('Metadata transaksi tidak valid.');
      }
    }
    final hasVersion = data.containsKey('dateVersion');
    final timestamp = data['date'] as Timestamp;
    final instant = timestamp.toDate().toUtc();
    if (hasVersion &&
        (data['dateVersion'] is! int ||
            data['dateVersion'] != dateVersion ||
            timestamp != Timestamp.fromDate(CalendarDate.canonical(instant)))) {
      throw const FormatException('Versi atau tanggal kalender tidak valid.');
    }
    final transaction = TransactionModel(
      id: id,
      category: data['category'],
      description: data['description'],
      amount: (data['amount'] as int).toDouble(),
      isIncome: data['isIncome'],
      date: hasVersion ? CalendarDate.canonical(instant) : instant.toLocal(),
      legacyDate: hasVersion
          ? null
          : LegacyTransactionDate(timestamp.seconds, timestamp.nanoseconds),
    );
    toMap(transaction);
    return transaction;
  }
}

class FirestoreTransactionRepository implements TransactionRepository {
  FirestoreTransactionRepository(FirebaseFirestore database)
    : _database = (() => database);
  FirestoreTransactionRepository.lazy(this._database);
  final FirebaseFirestore Function() _database;

  CollectionReference<Map<String, dynamic>> _collection(String uid) {
    TransactionMapper.validateId(uid);
    return _database().collection('users').doc(uid).collection('transactions');
  }

  DocumentReference<Map<String, dynamic>> _ref(String uid, String id) {
    TransactionMapper.validateId(id);
    return _collection(uid).doc(id);
  }

  @override
  String newId(String uid) => _collection(uid).doc().id;

  @override
  Stream<TransactionSnapshot> watch(String uid) => _collection(uid)
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => TransactionSnapshot(
          snapshot.docs
              .map(
                (document) => TransactionMapper.fromMap(
                  document.id,
                  document.data(),
                  allowPendingTimestamps: document.metadata.hasPendingWrites,
                ),
              )
              .toList(),
          fromCache: snapshot.metadata.isFromCache,
          hasPendingWrites: snapshot.metadata.hasPendingWrites,
        ),
      );

  @override
  Future<void> add(String uid, TransactionModel transaction) async {
    final data = TransactionMapper.toMap(transaction);
    final ref = _ref(uid, transaction.id);
    await _database().runTransaction((operation) async {
      if ((await operation.get(ref)).exists) {
        throw StateError('ID transaksi sudah digunakan.');
      }
      operation.set(ref, {
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> update(
    String uid,
    String id,
    TransactionModel transaction,
  ) async {
    if (id != transaction.id) {
      throw ArgumentError('ID transaksi tidak boleh berubah.');
    }
    final data = TransactionMapper.toMap(transaction);
    await _ref(
      uid,
      id,
    ).update({...data, 'updatedAt': FieldValue.serverTimestamp()});
  }

  @override
  Future<void> delete(String uid, String id) => _ref(uid, id).delete();
}
