import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/main.dart';
import 'package:simanja/screens/intro_page.dart';
import 'package:simanja/screens/login_page.dart';
import 'package:simanja/screens/main_shell.dart';
import 'package:simanja/screens/profile_page.dart';
import 'package:simanja/screens/session_gate.dart';
import 'package:simanja/screens/splash_page.dart';
import 'package:simanja/services/auth_service.dart';
import 'package:simanja/widgets/session_scope.dart';

import 'support/session_auth.dart';
import 'support/memory_profiles.dart';
import 'support/memory_transactions.dart';

class ProtectedHome extends StatelessWidget {
  const ProtectedHome({super.key});
  @override
  Widget build(BuildContext context) {
    final session = SessionScope.maybeOf(context)!;
    return Scaffold(
      body: Column(
        children: [
          Text('Home ${session.user!.uid}'),
          TextButton(
            onPressed: session.signOut,
            child: const Text('Keluar tes'),
          ),
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  AlertDialog(content: Text('Dialog ${session.user!.email}')),
            ),
            child: const Text('Buka dialog'),
          ),
        ],
      ),
    );
  }
}

Future<void> pumpSession(
  WidgetTester tester,
  SessionAuth auth, {
  String route = '/home',
  bool profile = false,
  AppState? state,
}) async {
  final appState = state ?? AppState.instance;
  Widget page(String name) => switch (name) {
    '/login' => LoginPage(auth: auth),
    _ => SessionGate(
      auth: auth,
      state: appState,
      showIntroWhenSignedOut: name == '/session',
      homeBuilder: (_) => profile ? const ProfilePage() : const ProtectedHome(),
    ),
  };
  Route<void> createRoute(RouteSettings settings) => MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => page(settings.name!),
  );
  await tester.pumpWidget(
    MaterialApp(
      initialRoute: route,
      onGenerateInitialRoutes: (name) => [
        createRoute(RouteSettings(name: name)),
      ],
      onGenerateRoute: createRoute,
    ),
  );
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('id_ID', null);
  });
  setUp(() {
    AppState.instance.clearSession();
    AppState.instance.useProfileRepository(MemoryProfiles());
    AppState.instance.useTransactionRepository(MemoryTransactions());
  });

  Future<void> cleanup(WidgetTester tester, SessionAuth auth) async {
    await tester.pumpWidget(const SizedBox());
    await auth.events.close();
  }

  testWidgets('splash menuju pemeriksaan sesi dan memulihkan Home', (
    tester,
  ) async {
    final auth = SessionAuth(
      currentUser: const SessionUser('A', 'a@example.com'),
    );
    addTearDown(() => cleanup(tester, auth));
    await tester.pumpWidget(
      MaterialApp(
        home: const SplashPage(nextRoute: '/session'),
        routes: {
          '/session': (_) => SessionGate(
            auth: auth,
            showIntroWhenSignedOut: true,
            homeBuilder: (_) => const ProtectedHome(),
          ),
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 2900));
    await tester.pumpAndSettle();
    expect(find.text('Home A'), findsOneWidget);
    expect(find.byType(IntroPage), findsNothing);
  });

  testWidgets('sesi sah membuka MainShell asli dari route aplikasi', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = SessionAuth(
      currentUser: const SessionUser('A', 'a@example.com'),
    );
    addTearDown(() => cleanup(tester, auth));
    await tester.pumpWidget(SimanjaApp(initialRoute: '/home', auth: auth));
    await tester.pumpAndSettle();
    expect(find.byType(MainShell), findsOneWidget);
    expect(AppState.instance.email, 'a@example.com');
    expect(AppState.instance.transactions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home tetap tertutup selama pemeriksaan sesi', (tester) async {
    final auth = SessionAuth(emitInitial: false);
    addTearDown(() => cleanup(tester, auth));
    await pumpSession(tester, auth);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ProtectedHome), findsNothing);
    auth.emit(null);
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('route Home anonim tidak membuka konten terlindungi', (
    tester,
  ) async {
    final auth = SessionAuth();
    addTearDown(() => cleanup(tester, auth));
    await tester.pumpWidget(SimanjaApp(initialRoute: '/home', auth: auth));
    await tester.pumpAndSettle();
    expect(find.byType(MainShell), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(
      Navigator.of(tester.element(find.byType(LoginPage))).canPop(),
      isFalse,
    );
  });

  testWidgets('startup tanpa sesi menuju Intro lalu Login', (tester) async {
    final auth = SessionAuth();
    addTearDown(() => cleanup(tester, auth));
    await pumpSession(tester, auth, route: '/session');
    await tester.pumpAndSettle();
    expect(find.byType(IntroPage), findsOneWidget);
    await tester.ensureVisible(find.text('Mulai Sekarang'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mulai Sekarang'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(ProtectedHome), findsNothing);
  });

  testWidgets('startup dengan sesi melewati Intro dan Login', (tester) async {
    final auth = SessionAuth(
      currentUser: const SessionUser('A', 'a@example.com'),
    );
    addTearDown(() => cleanup(tester, auth));
    await pumpSession(tester, auth, route: '/session');
    await tester.pumpAndSettle();
    expect(find.text('Home A'), findsOneWidget);
    expect(find.byType(IntroPage), findsNothing);
    expect(find.byType(LoginPage), findsNothing);
    expect(AppState.instance.email, 'a@example.com');
  });

  testWidgets('logout menutup dialog serta stack; Back tidak membuka Home', (
    tester,
  ) async {
    final auth = SessionAuth(
      currentUser: const SessionUser('A', 'a@example.com'),
    );
    addTearDown(() => cleanup(tester, auth));
    await pumpSession(tester, auth);
    await tester.pumpAndSettle();
    AppState.instance.updatePhoto('private-A');
    await tester.tap(find.text('Buka dialog'));
    await tester.pumpAndSettle();
    expect(find.text('Dialog a@example.com'), findsOneWidget);
    await auth.signOut();
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ProtectedHome), findsNothing);
    expect(AppState.instance.photoPath, isNull);
    expect(
      Navigator.of(tester.element(find.byType(LoginPage))).canPop(),
      isFalse,
    );
  });

  testWidgets('pergantian UID menutup form lama dan membersihkan stack', (
    tester,
  ) async {
    final auth = SessionAuth(
      currentUser: const SessionUser('A', 'a@example.com'),
    );
    addTearDown(() => cleanup(tester, auth));
    await pumpSession(tester, auth);
    await tester.pumpAndSettle();
    AppState.instance.updatePhoto('private-A');
    await tester.tap(find.text('Buka dialog'));
    await tester.pumpAndSettle();
    auth.emit(const SessionUser('B', 'b@example.com'));
    await tester.pumpAndSettle();
    expect(find.text('Home B'), findsOneWidget);
    expect(find.textContaining('a@example.com'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(AppState.instance.photoPath, isNull);
    expect(
      Navigator.of(tester.element(find.byType(ProtectedHome))).canPop(),
      isFalse,
    );
  });

  testWidgets('error pemeriksaan sesi dapat dicoba ulang tanpa data dummy', (
    tester,
  ) async {
    final auth = SessionAuth(emitInitial: false);
    addTearDown(() => cleanup(tester, auth));
    await pumpSession(tester, auth);
    await tester.pump();
    auth.events.addError(StateError('lost connection'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sesi belum dapat diperiksa'), findsOneWidget);
    expect(find.byType(ProtectedHome), findsNothing);
    await tester.tap(find.text('Coba lagi'));
    await tester.pump();
    auth.emit(const SessionUser('A', 'a@example.com'));
    await tester.pumpAndSettle();
    expect(find.text('Home A'), findsOneWidget);
    expect(AppState.instance.transactions, isEmpty);
  });

  testWidgets('keluar dari Profil memanggil signOut dan membersihkan Home', (
    tester,
  ) async {
    final auth = SessionAuth(
      currentUser: const SessionUser('A', 'a@example.com'),
    );
    addTearDown(() => cleanup(tester, auth));
    await pumpSession(tester, auth, profile: true);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('profile-logout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-logout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-logout')));
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 1);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(AppState.instance.sessionUid, isNull);
    expect(AppState.instance.transactions, isEmpty);
  });

  testWidgets(
    'logout gagal di Profil mempertahankan sesi dan menampilkan error',
    (tester) async {
      final auth = SessionAuth(
        currentUser: const SessionUser('A', 'a@example.com'),
      )..signOutFailure = StateError('offline');
      addTearDown(() => cleanup(tester, auth));
      await pumpSession(tester, auth, profile: true);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('profile-logout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-logout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-logout')));
      await tester.pumpAndSettle();
      expect(find.text('Gagal keluar. Silakan coba lagi.'), findsOneWidget);
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(AppState.instance.sessionUid, 'A');
    },
  );
  testWidgets('membatalkan konfirmasi logout tidak mengakhiri sesi', (
    tester,
  ) async {
    final auth = SessionAuth(
      currentUser: const SessionUser('A', 'a@example.com'),
    );
    addTearDown(() => cleanup(tester, auth));
    await pumpSession(tester, auth, profile: true);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('profile-logout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-logout')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 0);
    expect(AppState.instance.sessionUid, 'A');
    expect(find.byType(ProfilePage), findsOneWidget);
  });

  testWidgets(
    'controller dilepas sebelum snapshot tidak menjalankan callback widget lama',
    (tester) async {
      final auth = SessionAuth(emitInitial: false);
      addTearDown(() => cleanup(tester, auth));
      await pumpSession(tester, auth);
      await tester.pumpWidget(const SizedBox());
      auth.emit(const SessionUser('A', 'a@example.com'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(AppState.instance.sessionUid, isNull);
    },
  );
}
