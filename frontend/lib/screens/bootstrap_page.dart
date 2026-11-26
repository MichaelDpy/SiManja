import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import '../core/firebase_bootstrap.dart';
import '../core/firebase_environment.dart';
import 'splash_page.dart';

class BootstrapPage extends StatefulWidget {
  const BootstrapPage({super.key, this.initialize, this.onReady});

  /// Pengganti [FirebaseBootstrap.initialize] untuk pengujian.
  final Future<void> Function()? initialize;

  /// Halaman setelah inisialisasi berhasil; default splash → sesi.
  final WidgetBuilder? onReady;

  @override
  State<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends State<BootstrapPage> {
  late Future<void> _initialization;

  Future<void> _start() =>
      (widget.initialize ?? FirebaseBootstrap.initialize)();

  @override
  void initState() {
    super.initState();
    _initialization = _start();
    // Native splash dilepas pada frame pertama, termasuk saat init gagal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _initialization,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (!snapshot.hasError) {
        return widget.onReady?.call(context) ??
            const SplashPage(nextRoute: '/session');
      }
      final error = snapshot.error;
      return error is FirebaseConfigException
          ? _ConfigErrorView(error: error)
          : _InitErrorView(
              onRetry: () => setState(() {
                _initialization = _start();
              }),
            );
    },
  );
}

/// Konfigurasi build salah: mencoba lagi tidak akan berhasil, jadi tidak ada
/// tombol retry. Pesan hanya menyebut nama field, bukan nilai konfigurasi.
class _ConfigErrorView extends StatelessWidget {
  const _ConfigErrorView({required this.error});
  final FirebaseConfigException error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final env = error.environment?.label ?? 'tidak dikenal';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.settings_suggest_outlined,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Konfigurasi Firebase tidak valid',
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Lingkungan: $env',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  for (final issue in error.issues)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  '),
                          Expanded(child: Text(issue)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Perbaiki file konfigurasi lingkungan lalu build ulang '
                    'aplikasi. Lihat bagian "Lingkungan Firebase" di README.',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InitErrorView extends StatelessWidget {
  const _InitErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final emulator = FirebaseBootstrap.useEmulators;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Firebase belum dapat disiapkan',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  emulator
                      ? 'Pastikan Firebase Emulator berjalan dan dapat '
                            'dijangkau perangkat, lalu coba lagi.'
                      : 'Periksa koneksi internet, lalu coba lagi.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
