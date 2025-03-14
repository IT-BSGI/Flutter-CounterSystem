import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'home.dart';
import 'counter_table_screen.dart';
import 'settings.dart';
import 'login_screen.dart';

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
            child: NavigationRail(
              extended: isRailExpanded,
              destinations: [
                NavigationRailDestination(
                  icon: Icon(Icons.home),
                  label: Text('Home'),
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
                setState(() => selectedIndex = value);
              },
              leading: Column(
                children: [
                  IconButton(
                    icon: Icon(isRailExpanded ? Icons.arrow_back : Icons.menu),
                    onPressed: () {
                      setState(() => isRailExpanded = !isRailExpanded);
                    },
                  ),
                  Divider(),
                ],
              ),
              trailing: IconButton(
                icon: Icon(Icons.logout),
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
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
