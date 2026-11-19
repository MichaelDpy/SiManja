import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Emulator adalah default pengembangan. Cloud memerlukan konfigurasi asli.
abstract final class FirebaseBootstrap {
  static FirebaseApp? _app;
  static FirebaseApp get app => _app ?? Firebase.app();
  static FirebaseAuth get auth => FirebaseAuth.instanceFor(app: app);
  static FirebaseFirestore get firestore =>
      FirebaseFirestore.instanceFor(app: app);
  static const useEmulators = bool.fromEnvironment(
    'USE_FIREBASE_EMULATORS',
    defaultValue: true,
  );
  static const projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'demo-simanja',
  );

  static Future<void> initialize() async {
    if (_app == null) {
      if (useEmulators) {
        if (!projectId.startsWith('demo-')) {
          throw StateError('Mode emulator memerlukan project ID demo-.');
        }
        // Firestore platform interface memerlukan app default, juga saat demo.
        // demoProjectId tanpa name justru membuat app bernama project ID.
        final existing = Firebase.apps
            .where((item) => item.name == defaultFirebaseAppName)
            .firstOrNull;
        if (existing != null && existing.options.projectId != projectId) {
          throw StateError('App Firebase default memakai project berbeda.');
        }
        _app =
            existing ??
            await Firebase.initializeApp(
              name: defaultFirebaseAppName,
              demoProjectId: projectId,
            );
      } else {
        const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
        const appId = String.fromEnvironment('FIREBASE_APP_ID');
        const senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
        if (projectId.startsWith('demo-') ||
            apiKey.isEmpty ||
            appId.isEmpty ||
            senderId.isEmpty) {
          throw StateError(
            'Konfigurasi Firebase asli belum lengkap. '
            'Periksa konfigurasi Firebase atau jalankan Emulator Suite.',
          );
        }
        _app = await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: apiKey,
            appId: appId,
            messagingSenderId: senderId,
            projectId: projectId,
            authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
            iosBundleId: String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
          ),
        );
      }
    }
    if (useEmulators) {
      const suppliedHost = String.fromEnvironment('FIREBASE_EMULATOR_HOST');
      final host = suppliedHost.isNotEmpty
          ? suppliedHost
          : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android
                ? '10.0.2.2'
                : '127.0.0.1');
      await auth.useAuthEmulator(
        host,
        const int.fromEnvironment('FIREBASE_AUTH_PORT', defaultValue: 9099),
      );
      firestore.useFirestoreEmulator(
        host,
        const int.fromEnvironment(
          'FIREBASE_FIRESTORE_PORT',
          defaultValue: 8080,
        ),
      );
    }
  }
}
