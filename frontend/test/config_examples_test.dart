import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/core/firebase_environment.dart';

/// B2-05: file contoh config tetap contoh — tanpa kredensial asli, hanya
/// kunci yang dikenal, dan contoh cloud tetap ditolak guard B01.
void main() {
  const known = {
    'SIMANJA_ENV',
    'FIREBASE_PROJECT_ID',
    'FIREBASE_API_KEY',
    'FIREBASE_APP_ID',
    'FIREBASE_MESSAGING_SENDER_ID',
    'FIREBASE_AUTH_DOMAIN',
    'FIREBASE_IOS_BUNDLE_ID',
    'FIREBASE_EMULATOR_HOST',
    'GOOGLE_SERVER_CLIENT_ID',
  };

  Map<String, Object?> read(String env) =>
      jsonDecode(File('config/firebase.$env.example.json').readAsStringSync())
          as Map<String, Object?>;

  FirebaseEnvironmentConfig resolve(Map<String, Object?> v) =>
      FirebaseEnvironmentConfig.resolve(
        env: '${v['SIMANJA_ENV'] ?? ''}',
        projectId: '${v['FIREBASE_PROJECT_ID'] ?? ''}',
        apiKey: '${v['FIREBASE_API_KEY'] ?? ''}',
        appId: '${v['FIREBASE_APP_ID'] ?? ''}',
        messagingSenderId: '${v['FIREBASE_MESSAGING_SENDER_ID'] ?? ''}',
        emulatorHost: '${v['FIREBASE_EMULATOR_HOST'] ?? ''}',
        googleServerClientId: '${v['GOOGLE_SERVER_CLIENT_ID'] ?? ''}',
        platform: FirebaseAppPlatform.android,
        releaseBuild: false,
      );

  for (final env in ['dev', 'staging', 'production']) {
    test('contoh $env: kunci dikenal dan tanpa kredensial asli', () {
      final values = read(env);
      expect(values['SIMANJA_ENV'], env);
      expect(known.containsAll(values.keys), isTrue, reason: '${values.keys}');
      final text = values.values.join(' ');
      expect(text, isNot(matches(RegExp(r'AIza[0-9A-Za-z_-]{35}'))));
      expect(text, isNot(matches(RegExp(r'1:\d+:(android|ios|web):'))));
      expect(text, isNot(contains('PRIVATE KEY')));
      expect(text, isNot(contains('private_key')));
    });
  }

  test('contoh staging dan production ditolak guard (placeholder)', () {
    for (final env in ['staging', 'production']) {
      expect(
        () => resolve(read(env)),
        throwsA(
          isA<FirebaseConfigException>().having(
            (e) => e.issues.join(),
            'issues',
            contains('placeholder'),
          ),
        ),
        reason: env,
      );
    }
  });

  test('contoh dev ditolak sampai host LAN diisi', () {
    expect(() => resolve(read('dev')), throwsA(isA<FirebaseConfigException>()));
  });

  test('file config asli diabaikan Git, contoh tidak', () {
    final ignore = File('../.gitignore').readAsStringSync();
    expect(ignore, contains('frontend/config/firebase.*.json'));
    expect(ignore, contains('!frontend/config/firebase.*.example.json'));
    expect(ignore, contains('key.properties'));
    expect(ignore, contains('*.jks'));
  });
}
