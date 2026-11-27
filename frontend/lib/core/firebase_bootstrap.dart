import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'firebase_environment.dart';
import 'firestore_cache_policy.dart';
import 'session_artifacts.dart';

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

  /// Region harus sama dengan backend/functions/src/index.js (REGION).
  static const functionsRegion = 'us-central1';
  static FirebaseFunctions get functions =>
      FirebaseFunctions.instanceFor(app: app, region: functionsRegion);

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

    FirestoreCachePolicy.configure(firestore);
    try {
      await SessionExportStore.instance.prepare();
    } catch (_) {
      // Finance/Auth can start; export retries preparation and fails safely.
    }

    if (config.usesEmulators && !_emulatorsConnected) {
      final host = config.resolveEmulatorHost(
        isAndroidDevice:
            !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      );
      await auth.useAuthEmulator(host, config.authPort);
      firestore.useFirestoreEmulator(host, config.firestorePort);
      functions.useFunctionsEmulator(host, config.functionsPort);
      _emulatorsConnected = true;
    }
  }
}
