import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:simanja/screens/auth_form_page.dart';
import 'package:simanja/screens/login_page.dart';
import 'package:simanja/services/auth_service.dart';

class ControlledAuth implements AuthGateway {
  final calls = <({String action, String email, String? password})>[];
  Completer<void>? pending;
  Object? failure;

  Future<void> _request(String action, String email, [String? password]) async {
    calls.add((action: action, email: email, password: password));
    await pending?.future;
    if (failure != null) throw failure!;
  }

  @override
  Stream<SessionUser?> get authStateChanges => Stream.value(null);
  @override
  Future<void> signIn(String email, String password) =>
      _request('signIn', email, password);
  @override
  Future<void> signUp(String email, String password) =>
      _request('signUp', email, password);
  @override
  Future<void> resetPassword(String email) => _request('reset', email);
  @override
  Future<void> signOut() => _request('signOut', '');
}

Future<void> pumpPage(
  WidgetTester tester,
  ControlledAuth auth, {
  bool? register,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: register == null
          ? LoginPage(auth: auth)
          : AuthFormPage(register: register, auth: auth),
      routes: {
        '/home': (_) => const Scaffold(body: Text('Home tes')),
        '/register': (_) => AuthFormPage(register: true, auth: auth),
        '/reset-password': (_) => AuthFormPage(register: false, auth: auth),
      },
    ),
  );
}

Future<void> tapButton(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> loginInput(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('login-email')),
    'user@example.com',
  );
  await tester.enterText(
    find.byKey(const Key('login-password')),
    ' password tetap ',
  );
}

Future<void> registerInput(WidgetTester tester, {String? confirmation}) async {
  await tester.enterText(
    find.byKey(const Key('auth-email')),
    'new@example.com',
  );
  await tester.enterText(
    find.byKey(const Key('auth-password')),
    'Password123!',
  );
  await tester.enterText(
    find.byKey(const Key('auth-confirm')),
    confirmation ?? 'Password123!',
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('login invalid tidak memanggil layanan', (tester) async {
    final auth = ControlledAuth();
    await pumpPage(tester, auth);
    await tester.enterText(find.byKey(const Key('login-email')), 'bukan-email');
    await tapButton(tester, 'login-submit');
    expect(find.text('Format email tidak valid'), findsOneWidget);
    expect(find.text('Password wajib diisi'), findsOneWidget);
    expect(auth.calls, isEmpty);
  });

  testWidgets(
    'login menunggu hasil, menjaga password, dan mencegah submit keyboard ganda',
    (tester) async {
      final auth = ControlledAuth()..pending = Completer<void>();
      await pumpPage(tester, auth);
      await loginInput(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(auth.calls, hasLength(1));
      expect(auth.calls.single.password, ' password tetap ');
      expect(find.text('Home tes'), findsNothing);
      expect(
        tester
            .widget<ElevatedButton>(find.byKey(const Key('login-submit')))
            .onPressed,
        isNull,
      );
      auth.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Home tes'), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
    },
  );

  testWidgets('login gagal tetap di form dan mempertahankan input', (
    tester,
  ) async {
    final auth = ControlledAuth()
      ..failure = FirebaseAuthException(
        code: 'invalid-credential',
        message: 'detail rahasia',
      );
    await pumpPage(tester, auth);
    await loginInput(tester);
    await tapButton(tester, 'login-submit');
    await tester.pumpAndSettle();
    expect(find.text('Email atau password salah.'), findsOneWidget);
    expect(find.textContaining('detail rahasia'), findsNothing);
    expect(find.text('Home tes'), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('login-email')))
          .controller!
          .text,
      'user@example.com',
    );
    expect(
      tester
          .widget<ElevatedButton>(find.byKey(const Key('login-submit')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'hasil login setelah halaman ditutup tidak mengakses widget lama',
    (tester) async {
      final auth = ControlledAuth()..pending = Completer<void>();
      await pumpPage(tester, auth);
      await loginInput(tester);
      await tapButton(tester, 'login-submit');
      await tester.pumpWidget(const SizedBox());
      auth.pending!.completeError(
        FirebaseAuthException(code: 'network-request-failed'),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tautan login membuka pendaftaran dan reset', (tester) async {
    final auth = ControlledAuth();
    await pumpPage(tester, auth);
    await tester.ensureVisible(find.text('Buat akun'));
    await tester.pump();
    await tester.tap(find.text('Buat akun'));
    await tester.pumpAndSettle();
    expect(find.text('Buat Akun'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Lupa password?'));
    await tester.pump();
    await tester.tap(find.text('Lupa password?'));
    await tester.pumpAndSettle();
    expect(find.text('Pulihkan Password'), findsOneWidget);
  });

  testWidgets('konfirmasi password berbeda tidak membuat akun', (tester) async {
    final auth = ControlledAuth();
    await pumpPage(tester, auth, register: true);
    await registerInput(tester, confirmation: 'Berbeda');
    await tapButton(tester, 'auth-submit');
    expect(find.text('Konfirmasi password berbeda'), findsOneWidget);
    expect(auth.calls, isEmpty);
  });

  testWidgets('pendaftaran berhasil hanya menavigasi setelah layanan selesai', (
    tester,
  ) async {
    final auth = ControlledAuth()..pending = Completer<void>();
    await pumpPage(tester, auth, register: true);
    await registerInput(tester);
    await tapButton(tester, 'auth-submit');
    expect(auth.calls.single.action, 'signUp');
    expect(find.text('Home tes'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('auth-submit')))
          .onPressed,
      isNull,
    );
    auth.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Home tes'), findsOneWidget);
  });

  testWidgets('kebijakan password server ditampilkan tanpa sukses palsu', (
    tester,
  ) async {
    final auth = ControlledAuth()
      ..failure = FirebaseAuthException(code: 'weak-password');
    await pumpPage(tester, auth, register: true);
    await registerInput(tester);
    await tapButton(tester, 'auth-submit');
    await tester.pumpAndSettle();
    expect(
      find.text('Password belum memenuhi kebijakan keamanan akun.'),
      findsOneWidget,
    );
    expect(find.text('Home tes'), findsNothing);
  });

  testWidgets('reset menunggu hasil dan menjelaskan tautan mode emulator', (
    tester,
  ) async {
    final auth = ControlledAuth()..pending = Completer<void>();
    await pumpPage(tester, auth, register: false);
    await tester.enterText(
      find.byKey(const Key('auth-email')),
      'user@example.com',
    );
    await tapButton(tester, 'auth-submit');
    expect(auth.calls.single.action, 'reset');
    expect(find.byKey(const Key('auth-result')), findsNothing);
    auth.pending!.complete();
    await tester.pumpAndSettle();
    expect(
      find.textContaining('tautan pemulihan tersedia di Auth Emulator'),
      findsOneWidget,
    );
    expect(find.text('Home tes'), findsNothing);
  });

  testWidgets('reset gagal tidak mengklaim email sudah terkirim', (
    tester,
  ) async {
    final auth = ControlledAuth()
      ..failure = FirebaseAuthException(code: 'network-request-failed');
    await pumpPage(tester, auth, register: false);
    await tester.enterText(
      find.byKey(const Key('auth-email')),
      'user@example.com',
    );
    await tapButton(tester, 'auth-submit');
    await tester.pumpAndSettle();
    expect(find.textContaining('Koneksi gagal'), findsOneWidget);
    expect(find.textContaining('Permintaan pemulihan berhasil'), findsNothing);
  });

  testWidgets(
    'pendaftaran tetap dapat dipakai pada layar 320 dan teks 1,5 saat keyboard terbuka',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.reset);
      final auth = ControlledAuth();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: AuthFormPage(register: true, auth: auth),
          routes: {'/home': (_) => const Scaffold(body: Text('Home tes'))},
        ),
      );
      await registerInput(tester);
      await tapButton(tester, 'auth-submit');
      await tester.pumpAndSettle();
      expect(find.text('Home tes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
