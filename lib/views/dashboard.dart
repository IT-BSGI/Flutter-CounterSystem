import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'home.dart';
import 'counter_table_screen.dart';
import 'settings.dart';

class DashboardPanel extends StatefulWidget {
  @override
  _DashboardPanelState createState() => _DashboardPanelState();
}

class _DashboardPanelState extends State<DashboardPanel> {
  int selectedIndex = 0;
  bool isRailExpanded = true;

  final List<Widget> _pages = [
    HomePage(), 
    CounterTableScreen(),
    EditProcessesScreen(),
  ];

  @override
Widget build(BuildContext context) {
  return Scaffold(
    body: Row(
      children: [
        SafeArea(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade400, Colors.blueAccent.shade700],
                // colors: [Colors.blue.shade700, Colors.blueAccent.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: NavigationRail(
              backgroundColor: Colors.transparent, // Gunakan transparent agar mengikuti gradient
              indicatorColor: Colors.white24, // Warna indikator untuk item terpilih
              selectedIconTheme: IconThemeData(color: Colors.white),
              unselectedIconTheme: IconThemeData(color: Colors.white70),
              selectedLabelTextStyle: TextStyle(fontSize: 16, color: Colors.white),
              unselectedLabelTextStyle: TextStyle(fontSize: 14, color: Colors.white70),
              extended: isRailExpanded,
              destinations: [
                NavigationRailDestination(icon: Icon(Icons.home), label: Text('Home')),
                NavigationRailDestination(icon: Icon(Icons.bar_chart), label: Text('Data')),
                NavigationRailDestination(icon: Icon(Icons.settings), label: Text('Settings')),
              ],
              selectedIndex: selectedIndex,
              onDestinationSelected: (value) {
                setState(() => selectedIndex = value);
              },
              leading: Column(
                children: [
                  IconButton(
                    icon: Icon(isRailExpanded ? Icons.arrow_back : Icons.menu, color: Colors.white),
                    onPressed: () {
                      setState(() => isRailExpanded = !isRailExpanded);
                    },
                  ),
                  Divider(color: Colors.white54), // Divider lebih soft
                ],
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: Tooltip(
                      message: "Logout",
                      child: isRailExpanded
                          ? InkWell(
                              onTap: () async {
                                await FirebaseAuth.instance.signOut();
                                Navigator.of(context).popUntil((route) => route.isFirst);
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.logout, color: Colors.white),
                                    SizedBox(width: 8),
                                    Text("Logout", style: TextStyle(color: Colors.white, fontSize: 16)),
                                  ],
                                ),
                              ),
                            )
                          : IconButton(
                              icon: Icon(Icons.logout, color: Colors.white),
                              onPressed: () async {
                                await FirebaseAuth.instance.signOut();
                                Navigator.of(context).popUntil((route) => route.isFirst);
                              },
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: selectedIndex < _pages.length ? selectedIndex : 0,
            children: _pages,
          ),
        ),
      ],
    ),
  );
}

}
