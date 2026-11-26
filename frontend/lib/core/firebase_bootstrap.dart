import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'firebase_environment.dart';

/// Satu-satunya titik inisialisasi Firebase (app default).
///
/// Lingkungan dipilih melalui `SIMANJA_ENV` dan divalidasi oleh
/// [FirebaseEnvironmentConfig] sebelum `Firebase.initializeApp` dipanggil.
/// Konfigurasi tidak valid melempar [FirebaseConfigException]; tidak ada
/// fallback ke emulator atau data dummy.
abstract final class FirebaseBootstrap {
  static FirebaseApp? _app;
  static FirebaseEnvironmentConfig? _config;
  static bool _emulatorsConnected = false;

  static FirebaseApp get app => _app ?? Firebase.app();
  static FirebaseAuth get auth => FirebaseAuth.instanceFor(app: app);
  static FirebaseFirestore get firestore =>
      FirebaseFirestore.instanceFor(app: app);

  /// Konfigurasi aktif; null sebelum inisialisasi berhasil divalidasi.
  static FirebaseEnvironmentConfig? get config => _config;

  /// Lingkungan build ini memakai emulator. Konfigurasi tidak valid → false,
  /// sehingga UI tidak menjanjikan perilaku emulator.
  static bool get useEmulators {
    try {
      return (_config ??= FirebaseEnvironmentConfig.fromEnvironment())
          .usesEmulators;
    } on FirebaseConfigException {
      return false;
    }
  }

  static String? get projectId => _config?.projectId;

  static Future<void> initialize() async {
    // Validasi selalu lebih dulu: konfigurasi salah tidak boleh membuat app.
    final config = _config ?? FirebaseEnvironmentConfig.fromEnvironment();
    _config = config;

    if (_app == null) {
      final existing = Firebase.apps
          .where((item) => item.name == defaultFirebaseAppName)
          .firstOrNull;
      if (existing != null && existing.options.projectId != config.projectId) {
        throw StateError('App Firebase default memakai project berbeda.');
      }
      if (existing != null) {
        _app = existing;
      } else if (config.usesEmulators) {
        // Firestore platform interface memerlukan app default, juga saat demo.
        // demoProjectId tanpa name justru membuat app bernama project ID.
        _app = await Firebase.initializeApp(
          name: defaultFirebaseAppName,
          demoProjectId: config.projectId,
        );
      } else {
        _app = await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: config.apiKey,
            appId: config.appId,
            messagingSenderId: config.messagingSenderId,
            projectId: config.projectId,
            authDomain: config.authDomain.isEmpty ? null : config.authDomain,
            iosBundleId: config.iosBundleId.isEmpty ? null : config.iosBundleId,
          ),
        );
      }
    }

    if (config.usesEmulators && !_emulatorsConnected) {
      final host = config.resolveEmulatorHost(
        isAndroidDevice:
            !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      );
      await auth.useAuthEmulator(host, config.authPort);
      firestore.useFirestoreEmulator(host, config.firestorePort);
      _emulatorsConnected = true;
    }
  }
}
