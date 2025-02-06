import 'package:flutter/material.dart';
// import 'package:flutter_application_1/widgets/drawer.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import '../providers/esp32_provider.dart';
import 'home.dart';
import 'settings.dart';
import 'data.dart';

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
    SettingsPage(),
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

  

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: Text('Flutter App')),
//       drawer: Drawer(
//         child: ListView(
//           padding: EdgeInsets.zero,
//           children: [
//             DrawerHeader(
//               decoration: BoxDecoration(color: Colors.blue),
//               child: Text(
//                 'Menu',
//                 style: TextStyle(color: Colors.white, fontSize: 24),
//               ),
//             ),
//             ListTile(
//               leading: Icon(Icons.home),
//               title: Text('Home'),
//               onTap: () => _onSelectPage(0),
//             ),
//             ListTile(
//               leading: Icon(Icons.settings),
//               title: Text('Settings'),
//               onTap: () => _onSelectPage(1),
//             ),
//           ],
//         ),
//       ),
//       body: IndexedStack(
//         index: _selectedIndex,
//         children: _pages,
//       ),
//     );
//   }

// }


//   Widget build(BuildContext context, WidgetRef ref) {
//     final basicData = ref.watch(basicDataProvider);

//     return Scaffold(
//       appBar: AppBar(title: Text("Counter Sistem")),
//       drawer: MyDrawer(),
      
//       body: Padding(
//         padding: EdgeInsets.all(16),
//         child: GridView.count(
//           crossAxisCount: 5,
//           crossAxisSpacing: 10,
//           mainAxisSpacing: 10,
//           children: [
//             Card(
//               child: Center(child: Text("LINE A")),
//             ),
//             Card(
//               child: Center(child: Text("LINE B")),
//             ),
//             Card(
//               child: Center(child: Text("LINE C")),
//             ),
//             Card(
//               child: Center(child: Text("LINE D")),
//             ),
//             Card(
//               child: Center(child: Text("LINE E")),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// // 🔹 Dialog untuk menambah proses baru
//   void _showAddDialog(BuildContext context, WidgetRef ref) {
//     final _controller = TextEditingController();
//     showDialog(
//       context: context,
//       builder: (context) {
//         return AlertDialog(
//           title: Text("Add Process"),
//           content: TextField(
//             controller: _controller,
//             decoration: InputDecoration(labelText: "Enter process name"),
//           ),
//           actions: [
//             TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel")),
//             TextButton(
//               onPressed: () {
//                 final newProcess = _controller.text.trim();
//                 if (newProcess.isNotEmpty) {
//                   ref.read(addProcessProvider(newProcess));
//                   Navigator.pop(context);
//                 }
//               },
//               child: Text("Add"),
//             ),
//           ],
//         );
//       },
//     );
//   }

//   // 🔹 Dialog untuk mengupdate proses
//   void _showEditDialog(BuildContext context, WidgetRef ref, int index, String currentName) {
//     final _controller = TextEditingController(text: currentName);
//     showDialog(
//       context: context,
//       builder: (context) {
//         return AlertDialog(
//           title: Text("Edit Process"),
//           content: TextField(
//             controller: _controller,
//             decoration: InputDecoration(labelText: "Enter new name"),
//           ),
//           actions: [
//             TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel")),
//             TextButton(
//               onPressed: () {
//                 final updatedName = _controller.text.trim();
//                 if (updatedName.isNotEmpty) {
//                   ref.read(updateProcessProvider({'index': index, 'updatedName': updatedName}));
//                   Navigator.pop(context);
//                 }
//               },
//               child: Text("Update"),
//             ),
//           ],
//         );
//       },
//     );
//   }
