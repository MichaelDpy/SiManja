import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/models/user_profile.dart';
import 'package:simanja/screens/login_page.dart';
import 'package:simanja/screens/profile_page.dart';
import 'package:simanja/screens/session_gate.dart';
import 'package:simanja/services/auth_service.dart';

import 'support/memory_profiles.dart';
import 'support/memory_transactions.dart';
import 'support/session_auth.dart';

Finder field(String name) => find.descendant(
  of: find.byKey(Key('profile-$name')),
  matching: find.byType(TextFormField),
);

Future<void> submit(WidgetTester tester) async {
  final save = find.byKey(const Key('profile-save'));
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pump();
}

void main() {
  late MemoryProfiles repository;
  late SessionAuth auth;
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    repository = MemoryProfiles();
    repository.profiles['A'] = const UserProfile(
      name: 'Nama Server',
      city: 'Bandung',
      monthlyIncome: 5000,
    );
    auth = SessionAuth(currentUser: const SessionUser('A', 'a@example.com'));
    AppState.instance.clearSession();
    AppState.instance.useTransactionRepository(MemoryTransactions());
  });
  Future<void> pump(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await auth.events.close();
      AppState.instance.clearSession();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: SessionGate(
          auth: auth,
          profiles: repository,
          homeBuilder: (_) => const ProfilePage(),
        ),
        routes: {'/login': (_) => LoginPage(auth: auth)},
      ),
    );
  }

  testWidgets('form menunggu profil server dan email identitas hanya-baca', (
    tester,
  ) async {
    repository.delayedLoads['A'] = Completer<UserProfile>();
    await pump(tester);
    await tester.pump();
    expect(find.text('Memuat profil…'), findsOneWidget);
    expect(find.byType(ProfilePage), findsNothing);
    repository.delayedLoads['A']!.complete(repository.profiles['A']!);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(field('name')).controller!.text,
      'Nama Server',
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: field('email'),
              matching: find.byType(TextField),
            ),
          )
          .readOnly,
      isTrue,
    );
    expect(
      tester.widget<TextFormField>(field('email')).controller!.text,
      'a@example.com',
    );
  });

  testWidgets('simpan menunggu write dan tidak menampilkan sukses palsu', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();
    repository.pendingSave = Completer<void>();
    await tester.enterText(field('name'), 'Nama Baru');
    await submit(tester);
    expect(repository.saves, hasLength(1));
    expect(repository.saves.single.changes, {'name': 'Nama Baru'});
    expect(find.text('Profil berhasil disimpan ke akun.'), findsNothing);
    expect(AppState.instance.name, 'Nama Server');
    expect(
      tester
          .widget<ElevatedButton>(find.byKey(const Key('profile-save')))
          .onPressed,
      isNull,
    );
    repository.pendingSave!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Profil berhasil disimpan ke akun.'), findsOneWidget);
    expect(AppState.instance.name, 'Nama Baru');
  });

  testWidgets('write gagal mempertahankan input dan dapat diulang', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();
    repository.saveFailure = StateError('detail private backend');
    await tester.enterText(field('name'), 'Nama Belum Tersimpan');
    await submit(tester);
    await tester.pumpAndSettle();
    expect(
      find.text('Profil belum dapat disimpan. Periksa koneksi dan coba lagi.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextFormField>(field('name')).controller!.text,
      'Nama Belum Tersimpan',
    );
    expect(AppState.instance.name, 'Nama Server');
    expect(find.textContaining('detail private backend'), findsNothing);
    repository.saveFailure = null;
    await submit(tester);
    await tester.pumpAndSettle();
    expect(AppState.instance.name, 'Nama Belum Tersimpan');
  });

  testWidgets('nominal pecahan tidak diam-diam berubah menjadi nominal lain', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();
    await tester.enterText(field('income'), '1,5');
    await submit(tester);
    await tester.pumpAndSettle();
    expect(repository.saves, isEmpty);
    expect(
      tester.widget<TextFormField>(field('income')).controller!.text,
      '1,5',
    );
    await tester.enterText(field('income'), '5.000.000');
    await submit(tester);
    await tester.pumpAndSettle();
    expect(repository.profiles['A']!.monthlyIncome, 5000000);
  });

  testWidgets('preferensi menunggu server dan kegagalan tidak mengubah tema', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();
    repository.pendingSave = Completer<void>();
    final notif = find.byType(Switch).at(0);
    await tester.ensureVisible(notif);
    await tester.pumpAndSettle();
    await tester.tap(notif);
    await tester.pump();
    expect(tester.widget<Switch>(notif).value, isTrue);
    expect(tester.widget<Switch>(notif).onChanged, isNull);
    repository.pendingSave!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(notif).value, isFalse);
    repository.pendingSave = null;
    repository.saveFailure = StateError('offline');
    final theme = find.byType(Switch).at(1);
    await tester.ensureVisible(theme);
    await tester.pumpAndSettle();
    await tester.tap(theme);
    await tester.pumpAndSettle();
    expect(AppState.instance.darkMode, isTrue);
    expect(find.text('Preferensi gagal disimpan. Coba lagi.'), findsOneWidget);
  });

  testWidgets(
    'profil gagal dimuat dapat dicoba ulang tanpa menampilkan form kosong',
    (tester) async {
      repository.loadFailure = StateError('denied');
      await pump(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsNothing);
      expect(find.text('Muat ulang profil'), findsOneWidget);
      repository.loadFailure = null;
      await tester.tap(find.text('Muat ulang profil'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(
        tester.widget<TextFormField>(field('name')).controller!.text,
        'Nama Server',
      );
    },
  );
}
