import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'dashboard_page.dart';
import 'asset_page.dart';
import 'data_table_page.dart';
import 'transaction_page.dart';
import 'analytics_page.dart';
import 'profile_page.dart';

/// Shell utama dengan enam tab navigasi.
///
/// - State tiap halaman dipertahankan via [IndexedStack] — tidak di-rebuild
///   saat berpindah tab.
/// - Portrait/narrow: [BottomNavigationBar].
/// - Landscape / lebar lebih besar: [NavigationRail] di sisi kiri.
/// - Tombol Back Android dikonsumsi saat di tab selain Dasbor;
///   dari Dasbor, Back diteruskan ke sistem (keluar aplikasi).
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  // Pages dibuat sekali dan disimpan sebagai field — IndexedStack menjaga
  // subtree tetap hidup sehingga state tiap halaman tidak hilang saat ganti tab.
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      DashboardPage(onNavigateToTab: _goToTab),
      const AssetPage(),
      const TransactionPage(),
      const DataTablePage(),
      const AnalyticsPage(),
      const ProfilePage(),
    ];
  }

  void _goToTab(int index) {
    if (index >= 0 && index < _pages.length) {
      setState(() => _selectedIndex = index);
    }
  }

  static const List<_NavItem> _navItems = [
    _NavItem(
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
      label: 'Dasbor',
      tooltip: 'Dasbor',
    ),
    _NavItem(
      icon: Icons.donut_large_outlined,
      activeIcon: Icons.donut_large,
      label: 'Aset',
      tooltip: 'Aset & Rekening',
    ),
    _NavItem(
      icon: Icons.swap_horiz_outlined,
      activeIcon: Icons.swap_horiz,
      label: 'Transaksi',
      tooltip: 'Tambah & Kelola Transaksi',
    ),
    _NavItem(
      icon: Icons.table_chart_outlined,
      activeIcon: Icons.table_chart,
      label: 'Data',
      tooltip: 'Tabel Data Transaksi',
    ),
    _NavItem(
      icon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart,
      label: 'Analitik',
      tooltip: 'Analitik Keuangan',
    ),
    _NavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profil',
      tooltip: 'Profil & Pengaturan',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 600 ||
        MediaQuery.of(context).orientation == Orientation.landscape;

    // PopScope: konsumsi Back saat bukan di tab Dasbor → kembali ke Dasbor.
    // Saat di Dasbor, Back diteruskan ke sistem.
    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
        }
      },
      child: isWide
          ? _WideLayout(
              pages: _pages,
              selectedIndex: _selectedIndex,
              navItems: _navItems,
              onSelect: _goToTab,
            )
          : _NarrowLayout(
              pages: _pages,
              selectedIndex: _selectedIndex,
              navItems: _navItems,
              onSelect: _goToTab,
            ),
    );
  }
}

// ── Layout portrait/narrow ────────────────────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  final List<Widget> pages;
  final int selectedIndex;
  final List<_NavItem> navItems;
  final ValueChanged<int> onSelect;

  const _NarrowLayout({
    required this.pages,
    required this.selectedIndex,
    required this.navItems,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: IndexedStack(index: selectedIndex, children: pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.dividerColor, width: 0.5),
          ),
        ),
        child: SafeArea(
          top: false,
          child: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: selectedIndex,
            onTap: onSelect,
            backgroundColor:
                theme.bottomNavigationBarTheme.backgroundColor ?? cs.surface,
            selectedItemColor:
                theme.bottomNavigationBarTheme.selectedItemColor ?? cs.primary,
            unselectedItemColor:
                theme.bottomNavigationBarTheme.unselectedItemColor ??
                    cs.onSurfaceVariant,
            showSelectedLabels: true,
            showUnselectedLabels: true,
            items: navItems
                .map(
                  (n) => BottomNavigationBarItem(
                    icon: Icon(n.icon),
                    activeIcon: Icon(n.activeIcon),
                    label: n.label,
                    tooltip: n.tooltip,
                  ),
                )
                .toList(),
            selectedLabelStyle: GoogleFonts.lato(
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelStyle: GoogleFonts.lato(
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Layout landscape/wide ─────────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  final List<Widget> pages;
  final int selectedIndex;
  final List<_NavItem> navItems;
  final ValueChanged<int> onSelect;

  const _WideLayout({
    required this.pages,
    required this.selectedIndex,
    required this.navItems,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            // NavigationRail di sisi kiri untuk landscape/tablet
            LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: NavigationRail(
                        selectedIndex: selectedIndex,
                        onDestinationSelected: onSelect,
                        labelType: NavigationRailLabelType.all,
                        backgroundColor: cs.surface,
                        selectedIconTheme: IconThemeData(color: cs.primary),
                        unselectedIconTheme:
                            IconThemeData(color: cs.onSurfaceVariant),
                        selectedLabelTextStyle: GoogleFonts.lato(
                          color: cs.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                        unselectedLabelTextStyle: GoogleFonts.lato(
                          color: cs.onSurfaceVariant,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                        leading: const SizedBox(height: 8),
                        destinations: navItems
                            .map(
                              (n) => NavigationRailDestination(
                                icon: Tooltip(
                                  message: n.tooltip,
                                  child: Icon(n.icon),
                                ),
                                selectedIcon: Tooltip(
                                  message: n.tooltip,
                                  child: Icon(n.activeIcon),
                                ),
                                label: Text(n.label),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
            // Divider vertikal
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: theme.dividerColor,
            ),
            // Konten halaman
            Expanded(
              child: IndexedStack(index: selectedIndex, children: pages),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data model navigasi ───────────────────────────────────────────────────

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String tooltip;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.tooltip,
  });
}
