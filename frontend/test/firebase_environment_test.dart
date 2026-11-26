import 'package:flutter_test/flutter_test.dart';

import 'package:simanja/core/firebase_environment.dart';

/// B01: satu sumber konfigurasi Firebase dengan guard lingkungan.
///
/// Nilai di bawah adalah fixture berformat sah, bukan project nyata.
void main() {
  const apiKey = 'AIzaSyA1234567890abcdefghijklmnopqrstuv';
  const senderId = '123456789012';
  const androidAppId = '1:123456789012:android:0123456789abcdef';
  const webAppId = '1:123456789012:web:0123456789abcdef';
  const iosAppId = '1:123456789012:ios:0123456789abcdef';

  FirebaseEnvironmentConfig cloud(
    String env, {
    String projectId = 'simanja-staging-1',
    String key = apiKey,
    String appId = androidAppId,
    String sender = senderId,
    String authDomain = '',
    String iosBundleId = '',
    String emulatorHost = '',
    bool? legacy,
    FirebaseAppPlatform platform = FirebaseAppPlatform.android,
    bool release = false,
  }) => FirebaseEnvironmentConfig.resolve(
    env: env,
    legacyUseEmulators: legacy,
    projectId: projectId,
    apiKey: key,
    appId: appId,
    messagingSenderId: sender,
    authDomain: authDomain,
    iosBundleId: iosBundleId,
    emulatorHost: emulatorHost,
    platform: platform,
    releaseBuild: release,
  );

  Matcher rejects(String fragment) => throwsA(
    isA<FirebaseConfigException>().having(
      (e) => e.issues.join('\n'),
      'issues',
      contains(fragment),
    ),
  );

  group('dev / emulator', () {
    test('tanpa define apa pun tetap dev dengan demo-simanja', () {
      final config = FirebaseEnvironmentConfig.resolve(
        platform: FirebaseAppPlatform.android,
        releaseBuild: false,
      );
      expect(config.environment, FirebaseEnvironment.dev);
      expect(config.usesEmulators, isTrue);
      expect(config.projectId, 'demo-simanja');
      expect(config.authPort, 9099);
      expect(config.firestorePort, 8080);
    });

    test('USE_FIREBASE_EMULATORS=true lama tetap dev', () {
      final config = FirebaseEnvironmentConfig.resolve(
        legacyUseEmulators: true,
        platform: FirebaseAppPlatform.android,
        releaseBuild: false,
      );
      expect(config.environment, FirebaseEnvironment.dev);
    });

    test('host emulator default per platform dan dapat diganti', () {
      final config = FirebaseEnvironmentConfig.resolve(
        platform: FirebaseAppPlatform.android,
        releaseBuild: false,
      );
      expect(config.resolveEmulatorHost(isAndroidDevice: true), '10.0.2.2');
      expect(config.resolveEmulatorHost(isAndroidDevice: false), '127.0.0.1');

      final lan = FirebaseEnvironmentConfig.resolve(
        emulatorHost: '192.168.1.20',
        platform: FirebaseAppPlatform.android,
        releaseBuild: false,
      );
      expect(lan.resolveEmulatorHost(isAndroidDevice: true), '192.168.1.20');
    });

    test('host emulator placeholder atau berskema ditolak', () {
      for (final host in [
        'ISI_IP_LAN_LAPTOP_UNTUK_HP_FISIK',
        'http://192.168.1.20',
        '192.168.1.20:8080',
      ]) {
        expect(
          () => FirebaseEnvironmentConfig.resolve(
            emulatorHost: host,
            platform: FirebaseAppPlatform.android,
            releaseBuild: false,
          ),
          rejects('FIREBASE_EMULATOR_HOST harus nama host atau IP'),
          reason: host,
        );
      }
    });

    test('emulator menolak project non-demo', () {
      expect(
        () => FirebaseEnvironmentConfig.resolve(
          env: 'dev',
          projectId: 'simanja-prod',
          platform: FirebaseAppPlatform.android,
          releaseBuild: false,
        ),
        rejects('demo-*'),
      );
    });

    test('build rilis menolak emulator', () {
      expect(
        () => FirebaseEnvironmentConfig.resolve(
          platform: FirebaseAppPlatform.android,
          releaseBuild: true,
        ),
        rejects('Build rilis tidak boleh memakai Firebase Emulator'),
      );
    });

    test('port di luar rentang ditolak', () {
      expect(
        () => FirebaseEnvironmentConfig.resolve(
          authPort: 0,
          firestorePort: 70000,
          platform: FirebaseAppPlatform.android,
          releaseBuild: false,
        ),
        throwsA(
          isA<FirebaseConfigException>().having(
            (e) => e.issues.length,
            'jumlah masalah',
            2,
          ),
        ),
      );
    });
  });

  group('pemilihan lingkungan', () {
    test('SIMANJA_ENV tidak dikenal ditolak tanpa menebak', () {
      expect(
        () => FirebaseEnvironmentConfig.resolve(
          env: 'prod',
          platform: FirebaseAppPlatform.android,
          releaseBuild: false,
        ),
        throwsA(
          isA<FirebaseConfigException>()
              .having((e) => e.environment, 'environment', isNull)
              .having(
                (e) => e.issues.single,
                'issue',
                contains('dev, staging, atau production'),
              ),
        ),
      );
    });

    test('nilai env tidak peka huruf besar dan spasi', () {
      final config = cloud('  Staging ');
      expect(config.environment, FirebaseEnvironment.staging);
    });

    test('USE_FIREBASE_EMULATORS=false lama dipetakan ke staging, '
        'bukan produksi', () {
      final config = cloud('', legacy: false);
      expect(config.environment, FirebaseEnvironment.staging);
      expect(config.usesEmulators, isFalse);
    });

    test('flag lama yang bertentangan dengan SIMANJA_ENV ditolak', () {
      expect(() => cloud('production', legacy: true), rejects('bertentangan'));
      expect(
        () => FirebaseEnvironmentConfig.resolve(
          env: 'dev',
          legacyUseEmulators: false,
          platform: FirebaseAppPlatform.android,
          releaseBuild: false,
        ),
        rejects('bertentangan'),
      );
    });
  });

  group('staging / production', () {
    test('konfigurasi staging lengkap diterima apa adanya', () {
      final config = cloud('staging');
      expect(config.environment, FirebaseEnvironment.staging);
      expect(config.projectId, 'simanja-staging-1');
      expect(config.apiKey, apiKey);
      expect(config.appId, androidAppId);
      expect(config.messagingSenderId, senderId);
      expect(config.usesEmulators, isFalse);
    });

    test('produksi lengkap diterima pada build rilis', () {
      final config = cloud(
        'production',
        projectId: 'simanja-prod-1',
        release: true,
      );
      expect(config.environment, FirebaseEnvironment.production);
    });

    test('produksi menolak project demo-*', () {
      expect(
        () => cloud('production', projectId: 'demo-simanja'),
        rejects('project demo-*'),
      );
    });

    test('produksi menolak placeholder file contoh', () {
      expect(
        () => cloud(
          'production',
          projectId: 'ISI_PROJECT_ID_PRODUKSI',
          key: 'ISI_API_KEY_APLIKASI',
          appId: 'ISI_APP_ID_TARGET',
          sender: 'ISI_SENDER_ID',
        ),
        throwsA(
          isA<FirebaseConfigException>().having(
            (e) => e.issues.join('\n'),
            'issues',
            allOf(
              contains('placeholder'),
              contains('FIREBASE_API_KEY bukan format'),
              contains('FIREBASE_APP_ID bukan format'),
            ),
          ),
        ),
      );
    });

    test('field wajib kosong disebut satu per satu', () {
      expect(
        () => cloud('staging', projectId: '', key: '', appId: '', sender: ''),
        throwsA(
          isA<FirebaseConfigException>().having(
            (e) => e.issues.where((i) => i.contains('wajib diisi')).length,
            'field wajib',
            4,
          ),
        ),
      );
    });

    test('App ID platform lain ditolak', () {
      expect(
        () => cloud('production', appId: webAppId),
        rejects('terdaftar untuk web, sedangkan target ini android'),
      );
    });

    test('App ID dari project lain (sender berbeda) ditolak', () {
      expect(
        () => cloud(
          'production',
          appId: '1:999999999999:android:0123456789abcdef',
        ),
        rejects('tidak cocok'),
      );
    });

    test('Web/desktop wajib authDomain, iOS wajib bundle ID', () {
      expect(
        () => cloud(
          'staging',
          appId: webAppId,
          platform: FirebaseAppPlatform.web,
        ),
        rejects('FIREBASE_AUTH_DOMAIN wajib'),
      );
      expect(
        () => cloud(
          'staging',
          appId: iosAppId,
          platform: FirebaseAppPlatform.ios,
        ),
        rejects('FIREBASE_IOS_BUNDLE_ID wajib'),
      );
      expect(
        cloud(
          'staging',
          appId: webAppId,
          authDomain: 'simanja-staging-1.firebaseapp.com',
          platform: FirebaseAppPlatform.web,
        ).authDomain,
        'simanja-staging-1.firebaseapp.com',
      );
    });

    test('host emulator di lingkungan cloud ditolak', () {
      expect(
        () => cloud('staging', emulatorHost: '10.0.2.2'),
        rejects('hanya berlaku untuk SIMANJA_ENV=dev'),
      );
    });

    test('project ID dengan kata todo huruf kecil tetap sah', () {
      expect(
        cloud('staging', projectId: 'simanja-todo-1').projectId,
        'simanja-todo-1',
      );
    });

    test('pesan error tidak membocorkan nilai API key atau App ID', () {
      try {
        cloud(
          'production',
          key: 'AIzaSyBADKEY',
          appId: '1:111111111111:web:abc',
        );
        fail('seharusnya ditolak');
      } on FirebaseConfigException catch (error) {
        final text = error.toString();
        expect(text, isNot(contains('AIzaSyBADKEY')));
        expect(text, isNot(contains('111111111111')));
      }
    });
  });
}
