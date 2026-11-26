import 'package:flutter/foundation.dart';

/// Lingkungan Firebase yang dipilih saat build melalui Dart define
/// `SIMANJA_ENV`.
///
/// - [dev]: Firebase Emulator Suite dengan project `demo-*` (default).
/// - [staging]: project cloud non-produksi untuk uji tim.
/// - [production]: project cloud rilis; hanya aktif bila dipilih eksplisit.
enum FirebaseEnvironment {
  dev('dev', 'Pengembangan (emulator)'),
  staging('staging', 'Staging'),
  production('production', 'Produksi');

  const FirebaseEnvironment(this.key, this.label);
  final String key;
  final String label;

  bool get usesEmulators => this == dev;
}

/// Platform target yang menentukan jenis Firebase App ID yang sah.
enum FirebaseAppPlatform { android, ios, web }

/// Konfigurasi tidak valid. Pesan aman ditampilkan: tidak memuat nilai
/// API key/App ID, hanya nama field dan alasan.
class FirebaseConfigException implements Exception {
  FirebaseConfigException(this.environment, this.issues);

  /// Lingkungan yang diminta, atau null bila `SIMANJA_ENV` tidak dikenali.
  final FirebaseEnvironment? environment;
  final List<String> issues;

  @override
  String toString() =>
      'Konfigurasi Firebase ${environment?.key ?? '(tidak dikenal)'} '
      'tidak valid: ${issues.join('; ')}';
}

/// Satu-satunya sumber konfigurasi Firebase aplikasi.
///
/// Nilai dibaca dari Dart defines (`--dart-define` atau
/// `--dart-define-from-file=config/firebase.<env>.json`). Konfigurasi client
/// Firebase bukan secret server; secret/service-account tidak pernah dibaca
/// di sini.
@immutable
class FirebaseEnvironmentConfig {
  const FirebaseEnvironmentConfig._({
    required this.environment,
    required this.projectId,
    this.apiKey = '',
    this.appId = '',
    this.messagingSenderId = '',
    this.authDomain = '',
    this.iosBundleId = '',
    this.emulatorHost = '',
    this.authPort = 9099,
    this.firestorePort = 8080,
  });

  final FirebaseEnvironment environment;
  final String projectId;
  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String authDomain;
  final String iosBundleId;

  /// Host emulator yang diberikan pengguna; kosong berarti default platform.
  final String emulatorHost;
  final int authPort;
  final int firestorePort;

  bool get usesEmulators => environment.usesEmulators;

  static const _envDefine = String.fromEnvironment('SIMANJA_ENV');
  static const _legacyEmulatorDefined = bool.hasEnvironment(
    'USE_FIREBASE_EMULATORS',
  );
  static const _legacyEmulator = bool.fromEnvironment(
    'USE_FIREBASE_EMULATORS',
    defaultValue: true,
  );

  /// Konfigurasi dari Dart defines build ini, sudah divalidasi.
  static FirebaseEnvironmentConfig fromEnvironment() => resolve(
    env: _envDefine,
    legacyUseEmulators: _legacyEmulatorDefined ? _legacyEmulator : null,
    projectId: const String.fromEnvironment('FIREBASE_PROJECT_ID'),
    apiKey: const String.fromEnvironment('FIREBASE_API_KEY'),
    appId: const String.fromEnvironment('FIREBASE_APP_ID'),
    messagingSenderId: const String.fromEnvironment(
      'FIREBASE_MESSAGING_SENDER_ID',
    ),
    authDomain: const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
    iosBundleId: const String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
    emulatorHost: const String.fromEnvironment('FIREBASE_EMULATOR_HOST'),
    authPort: const int.fromEnvironment(
      'FIREBASE_AUTH_PORT',
      defaultValue: 9099,
    ),
    firestorePort: const int.fromEnvironment(
      'FIREBASE_FIRESTORE_PORT',
      defaultValue: 8080,
    ),
    platform: currentPlatform(),
    releaseBuild: kReleaseMode,
  );

  /// Platform App ID yang diharapkan untuk target yang sedang berjalan.
  /// Desktop memakai konfigurasi aplikasi Web Firebase.
  static FirebaseAppPlatform currentPlatform() {
    if (kIsWeb) return FirebaseAppPlatform.web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => FirebaseAppPlatform.android,
      TargetPlatform.iOS || TargetPlatform.macOS => FirebaseAppPlatform.ios,
      _ => FirebaseAppPlatform.web,
    };
  }

  /// Menentukan lingkungan lalu memvalidasi seluruh nilai.
  ///
  /// [legacyUseEmulators] adalah `USE_FIREBASE_EMULATORS` lama bila diberikan.
  /// Tanpa `SIMANJA_ENV`: `true`/tidak ada → dev, `false` → staging. Produksi
  /// tidak pernah dipilih secara implisit.
  @visibleForTesting
  static FirebaseEnvironmentConfig resolve({
    String env = '',
    bool? legacyUseEmulators,
    String projectId = '',
    String apiKey = '',
    String appId = '',
    String messagingSenderId = '',
    String authDomain = '',
    String iosBundleId = '',
    String emulatorHost = '',
    int authPort = 9099,
    int firestorePort = 8080,
    required FirebaseAppPlatform platform,
    required bool releaseBuild,
  }) {
    final requested = env.trim().toLowerCase();
    final FirebaseEnvironment environment;
    if (requested.isEmpty) {
      environment = legacyUseEmulators == false
          ? FirebaseEnvironment.staging
          : FirebaseEnvironment.dev;
    } else {
      final match = FirebaseEnvironment.values
          .where((item) => item.key == requested)
          .firstOrNull;
      if (match == null) {
        throw FirebaseConfigException(null, [
          'SIMANJA_ENV harus dev, staging, atau production.',
        ]);
      }
      environment = match;
    }

    final issues = <String>[];
    if (legacyUseEmulators != null &&
        legacyUseEmulators != environment.usesEmulators) {
      issues.add(
        'USE_FIREBASE_EMULATORS=$legacyUseEmulators bertentangan dengan '
        'SIMANJA_ENV=${environment.key}. Hapus salah satunya.',
      );
    }

    final project = projectId.trim().isEmpty && environment.usesEmulators
        ? 'demo-simanja'
        : projectId.trim();

    if (environment.usesEmulators) {
      if (releaseBuild) {
        issues.add('Build rilis tidak boleh memakai Firebase Emulator.');
      }
      if (!project.startsWith('demo-')) {
        issues.add('Mode emulator memerlukan FIREBASE_PROJECT_ID demo-*.');
      }
      final host = emulatorHost.trim();
      if (host.isNotEmpty &&
          (_placeholderPattern.hasMatch(host) ||
              !_emulatorHostPattern.hasMatch(host))) {
        issues.add(
          'FIREBASE_EMULATOR_HOST harus nama host atau IP tanpa skema/port, '
          'misalnya 192.168.1.20.',
        );
      }
      if (authPort <= 0 || authPort > 65535) {
        issues.add('FIREBASE_AUTH_PORT harus 1–65535.');
      }
      if (firestorePort <= 0 || firestorePort > 65535) {
        issues.add('FIREBASE_FIRESTORE_PORT harus 1–65535.');
      }
    } else {
      _validateCloud(
        issues,
        environment: environment,
        projectId: project,
        apiKey: apiKey.trim(),
        appId: appId.trim(),
        senderId: messagingSenderId.trim(),
        authDomain: authDomain.trim(),
        iosBundleId: iosBundleId.trim(),
        emulatorHost: emulatorHost.trim(),
        platform: platform,
      );
    }

    if (issues.isNotEmpty) throw FirebaseConfigException(environment, issues);

    return FirebaseEnvironmentConfig._(
      environment: environment,
      projectId: project,
      apiKey: apiKey.trim(),
      appId: appId.trim(),
      messagingSenderId: messagingSenderId.trim(),
      authDomain: authDomain.trim(),
      iosBundleId: iosBundleId.trim(),
      emulatorHost: emulatorHost.trim(),
      authPort: authPort,
      firestorePort: firestorePort,
    );
  }

  static final _projectIdPattern = RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$');
  static final _apiKeyPattern = RegExp(r'^AIza[0-9A-Za-z_-]{35}$');
  static final _appIdPattern = RegExp(r'^1:(\d+):(android|ios|web):[0-9a-f]+$');
  static final _senderPattern = RegExp(r'^\d+$');
  static final _emulatorHostPattern = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9.-]*)$');
  // Penanda placeholder huruf besar. Project ID/App ID/domain asli selalu
  // huruf kecil, jadi penanda ini tidak menolak nilai sah. API key tidak
  // diperiksa di sini karena acak; formatnya sudah divalidasi terpisah.
  static final _placeholderPattern = RegExp(
    r'ISI_|YOUR[_-]|PLACEHOLDER|CHANGE[_-]?ME|TODO|XXXX',
  );

  static void _validateCloud(
    List<String> issues, {
    required FirebaseEnvironment environment,
    required String projectId,
    required String apiKey,
    required String appId,
    required String senderId,
    required String authDomain,
    required String iosBundleId,
    required String emulatorHost,
    required FirebaseAppPlatform platform,
  }) {
    final name = environment.label;
    void required(String field, String value) {
      if (value.isEmpty) issues.add('$field wajib diisi untuk $name.');
    }

    required('FIREBASE_PROJECT_ID', projectId);
    required('FIREBASE_API_KEY', apiKey);
    required('FIREBASE_APP_ID', appId);
    required('FIREBASE_MESSAGING_SENDER_ID', senderId);

    final placeholderFields = <String>[
      if (_placeholderPattern.hasMatch(projectId)) 'FIREBASE_PROJECT_ID',
      if (_placeholderPattern.hasMatch(appId)) 'FIREBASE_APP_ID',
      if (_placeholderPattern.hasMatch(senderId))
        'FIREBASE_MESSAGING_SENDER_ID',
      if (_placeholderPattern.hasMatch(authDomain)) 'FIREBASE_AUTH_DOMAIN',
      if (_placeholderPattern.hasMatch(iosBundleId)) 'FIREBASE_IOS_BUNDLE_ID',
    ];
    if (placeholderFields.isNotEmpty) {
      issues.add(
        'Masih berisi placeholder contoh: ${placeholderFields.join(', ')}.',
      );
    }

    if (projectId.startsWith('demo-')) {
      issues.add('$name tidak boleh memakai project demo-* milik emulator.');
    } else if (projectId.isNotEmpty && !_projectIdPattern.hasMatch(projectId)) {
      issues.add('FIREBASE_PROJECT_ID bukan format project ID Firebase.');
    }
    if (apiKey.isNotEmpty && !_apiKeyPattern.hasMatch(apiKey)) {
      issues.add('FIREBASE_API_KEY bukan format API key Firebase.');
    }
    if (senderId.isNotEmpty && !_senderPattern.hasMatch(senderId)) {
      issues.add('FIREBASE_MESSAGING_SENDER_ID harus berupa angka.');
    }
    if (appId.isNotEmpty) {
      final match = _appIdPattern.firstMatch(appId);
      if (match == null) {
        issues.add('FIREBASE_APP_ID bukan format App ID Firebase.');
      } else {
        if (senderId.isNotEmpty && match.group(1) != senderId) {
          issues.add(
            'FIREBASE_APP_ID tidak cocok dengan '
            'FIREBASE_MESSAGING_SENDER_ID (project berbeda).',
          );
        }
        if (match.group(2) != platform.name) {
          issues.add(
            'FIREBASE_APP_ID terdaftar untuk ${match.group(2)}, '
            'sedangkan target ini ${platform.name}.',
          );
        }
      }
    }
    if (platform == FirebaseAppPlatform.web && authDomain.isEmpty) {
      issues.add('FIREBASE_AUTH_DOMAIN wajib untuk target Web/desktop.');
    }
    if (platform == FirebaseAppPlatform.ios && iosBundleId.isEmpty) {
      issues.add('FIREBASE_IOS_BUNDLE_ID wajib untuk target iOS.');
    }
    if (emulatorHost.isNotEmpty) {
      issues.add('FIREBASE_EMULATOR_HOST hanya berlaku untuk SIMANJA_ENV=dev.');
    }
  }

  /// Host emulator efektif: nilai pengguna, atau default per platform.
  String resolveEmulatorHost({required bool isAndroidDevice}) {
    if (emulatorHost.isNotEmpty) return emulatorHost;
    return isAndroidDevice ? '10.0.2.2' : '127.0.0.1';
  }
}
