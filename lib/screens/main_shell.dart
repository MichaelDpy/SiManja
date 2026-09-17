import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import 'dashboard_page.dart';
import 'asset_page.dart';
import 'data_table_page.dart';
import 'transaction_page.dart';
import 'analytics_page.dart';
import 'profile_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  static const _pages = <Widget>[
    DashboardPage(),
    AssetPage(),
    TransactionPage(),
    DataTablePage(),
    AnalyticsPage(),
    ProfilePage(),
  ];

  static const _navItems = <BottomNavigationBarItem>[
    BottomNavigationBarItem(
      icon: Icon(Icons.dashboard_outlined),
      activeIcon: Icon(Icons.dashboard),
      label: 'Dasbor',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.donut_large_outlined),
      activeIcon: Icon(Icons.donut_large),
      label: 'Aset',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.swap_horiz_outlined),
      activeIcon: Icon(Icons.swap_horiz),
      label: 'Transaksi',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.table_chart_outlined),
      activeIcon: Icon(Icons.table_chart),
      label: 'Data',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.bar_chart_outlined),
      activeIcon: Icon(Icons.bar_chart),
      label: 'Analitik',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.person_outline),
      activeIcon: Icon(Icons.person),
      label: 'Profil',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.divider, width: 0.5),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (i) => setState(() => _selectedIndex = i),
          items: _navItems,
          selectedLabelStyle:
              GoogleFonts.lato(fontSize: 10, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              GoogleFonts.lato(fontSize: 10),
        ),
      ),
    );
  }
}
