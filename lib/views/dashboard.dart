import 'package:flutter/material.dart';
// import 'package:flutter_application_1/widgets/drawer.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import '../providers/esp32_provider.dart';
import 'home.dart';
import 'settings.dart';
import 'data.dart';
import 'esp32_view.dart';

class DashboardPanel extends StatefulWidget {
  @override
  _DashboardPanelState createState() => _DashboardPanelState();
}

class _DashboardPanelState extends State<DashboardPanel> {
  int selectedIndex = 0;
  bool isRailExpanded = true; // Status NavigationRail (terbuka atau tertutup)

  // List halaman yang akan ditampilkan
  final List<Widget> _pages = [
    HomePage(),
    DataPage(),
    // SettingsPage(),
    CounterDataView(),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Scaffold(
          body: Row(
            children: [
              SafeArea(
                child: NavigationRail(
                  extended: isRailExpanded,
                  destinations: [
                    NavigationRailDestination(
                      icon: Icon(Icons.dashboard),
                      label: Text('Dashboard'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.bar_chart),
                      label: Text('Data'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings),
                      label: Text('Settings'),
                    ),
                  ],
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (value) {
                    setState(() {
                      selectedIndex = value;
                    });
                  },
                  // Tambahkan tombol toggle di bagian bawah
                  leading: Column(
                    children: [
                      IconButton(
                        icon: Icon(isRailExpanded ? Icons.arrow_back : Icons.menu),
                        onPressed: () {
                          setState(() {
                            isRailExpanded = !isRailExpanded;
                          });
                        },
                        
                      ),
                      Divider(), // Garis pemisah
                    ],
                  ),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: selectedIndex,
                  children: _pages,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}