import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:simanja/screens/auth_form_page.dart';
import 'package:simanja/screens/login_page.dart';
import 'package:simanja/services/auth_service.dart';

import 'support/fake_firebase_auth.dart';

/// B2-03: kebijakan password dan pemulihan pada jalur produksi.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late FakeFirebaseAuth sdk;
  late AuthService service;

  setUp(() {
    sdk = FakeFirebaseAuth();
    service = AuthService(sdk, google: FakeGoogleSource(available: false));
  });

  group('AuthService.resetPassword (produksi)', () {
    test('email tidak terdaftar: selesai seperti email terdaftar', () async {
      sdk.registered.add('ada@example.com');
      await service.resetPassword(' ada@example.com ');
      await service.resetPassword('tidakada@example.com');
      expect(sdk.mutations, [
        'reset:ada@example.com',
        'reset:tidakada@example.com',
      ]);
    });

    test('kegagalan lain diteruskan, bukan ditelan sebagai sukses', () async {
      for (final code in ['network-request-failed', 'too-many-requests']) {
        sdk.resetFailure = FirebaseAuthException(code: code);
        await expectLater(
          service.resetPassword('ada@example.com'),
          throwsA(
            isA<FirebaseAuthException>().having((e) => e.code, 'code', code),
          ),
        );
      }
    });

    test('pemeriksaan password lokal memakai batas Firebase', () async {
      final short = await service.checkPassword('12345');
      expect(short.isValid, isFalse);
      expect(short.fromServerPolicy, isFalse);
      expect((await service.checkPassword('      ')).isValid, isTrue);
    });
  });

  Future<void> pumpReset(WidgetTester tester, AuthGateway auth) => tester
      .pumpWidget(MaterialApp(home: AuthFormPage(register: false, auth: auth)));

  testWidgets('pesan reset seragam untuk email terdaftar dan tidak', (
    tester,
  ) async {
    sdk.registered.add('ada@example.com');
    final messages = <String>[];
    for (final email in ['ada@example.com', 'tidakada@example.com']) {
      await pumpReset(tester, service);
      await tester.enterText(find.byKey(const Key('auth-email')), email);
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();
      messages.add(
        tester.widget<Text>(find.byKey(const Key('auth-result'))).data!,
      );
      await tester.pumpWidget(const SizedBox());
    }
    expect(messages[0], messages[1]);
    expect(messages[0], isNot(contains('tidak terdaftar')));
  });

  testWidgets('reset terlalu sering: input tetap, tombol aktif lagi', (
    tester,
  ) async {
    sdk.resetFailure = FirebaseAuthException(code: 'too-many-requests');
    await pumpReset(tester, service);
    await tester.enterText(
      find.byKey(const Key('auth-email')),
      'a@example.com',
    );
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Terlalu banyak percobaan'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('auth-email')))
          .controller!
          .text,
      'a@example.com',
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('auth-submit')))
          .onPressed,
      isNotNull,
    );
  });

  group('pendaftaran', () {
    Future<_SpyAuth> pumpRegister(WidgetTester tester, _SpyAuth auth) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AuthFormPage(register: true, auth: auth),
          routes: {'/home': (_) => const Scaffold(body: Text('Home tes'))},
        ),
      );
      await tester.enterText(
        find.byKey(const Key('auth-email')),
        'b@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('auth-password')),
        ' Spasi 123 ',
      );
      await tester.enterText(
        find.byKey(const Key('auth-confirm')),
        ' Spasi 123 ',
      );
      return auth;
    }

    testWidgets('Done ganda: satu signUp, password tidak di-trim', (
      tester,
    ) async {
      final auth = await pumpRegister(
        tester,
        _SpyAuth()..pending = Completer<void>(),
      );
      await tester.showKeyboard(find.byKey(const Key('auth-confirm')));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(auth.signUps, [('b@example.com', ' Spasi 123 ')]);
      auth.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Home tes'), findsOneWidget);
    });

    testWidgets('gagal jaringan: input tetap dan dapat dicoba lagi', (
      tester,
    ) async {
      final auth = await pumpRegister(
        tester,
        _SpyAuth()
          ..failure = FirebaseAuthException(code: 'network-request-failed'),
      );
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Koneksi gagal'), findsOneWidget);
      for (final key in ['auth-email', 'auth-password', 'auth-confirm']) {
        expect(
          tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text,
          isNotEmpty,
          reason: key,
        );
      }
      expect(find.text('Home tes'), findsNothing);

      auth.failure = null;
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();
      expect(auth.signUps, hasLength(2));
      expect(find.text('Home tes'), findsOneWidget);
    });

    testWidgets('kedua kolom password baru mendukung password manager', (
      tester,
    ) async {
      await pumpRegister(tester, _SpyAuth());
      for (final key in ['auth-password', 'auth-confirm']) {
        final field = tester.widget<TextField>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(TextField),
          ),
        );
        expect(
          field.autofillHints,
          contains(AutofillHints.newPassword),
          reason: key,
        );
        expect(field.obscureText, isTrue);
        expect(field.enableInteractiveSelection, isNot(false), reason: 'paste');
      }
    });
  });

  testWidgets('login dalam AutofillGroup dengan petunjuk email/password', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: _SpyAuth())));
    expect(
      find.ancestor(
        of: find.byKey(const Key('login-password')),
        matching: find.byType(AutofillGroup),
      ),
      findsOneWidget,
    );
    final password = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('login-password')),
        matching: find.byType(TextField),
      ),
    );
    expect(password.autofillHints, contains(AutofillHints.password));
  });
}

class _SpyAuth implements AuthGateway {
  final signUps = <(String, String)>[];
  Completer<void>? pending;
  Object? failure;

  @override
  Future<void> signUp(String email, String password) async {
    signUps.add((email.trim(), password));
    await pending?.future;
    if (failure != null) throw failure!;
  }

  @override
  Future<PasswordCheck> checkPassword(String password) async =>
      PasswordCheck(localPasswordIssues(password), fromServerPolicy: false);

  @override
  bool get googleSignInAvailable => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
