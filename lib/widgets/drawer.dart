import 'package:flutter/material.dart';

class MyDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Colors.blue),
            child: Text(
              'Menu',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
          ),
          ListTile(
            leading: Icon(Icons.dashboard),
            title: Text('Home'),
            onTap: () {
              Navigator.pop(context); // Tutup drawer saat item dipilih
            },
          ),
          ListTile(
            leading: Icon(Icons.bar_chart),
            title: Text('Home'),
            onTap: () {
              Navigator.pop(context); // Tutup drawer saat item dipilih
            },
          ),
          ListTile(
            leading: Icon(Icons.settings),
            title: Text('Settings'),
            onTap: () {
              Navigator.pushNamed(context, '/settings'); // Navigasi ke SettingsPage
            },
          ),
        ],
      ),
    );
  }
}
