import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/esp32_provider.dart';
import '../widgets/drawer.dart';

class HomePage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basicData = ref.watch(basicDataProvider);

    return Scaffold(
      appBar: AppBar(title: Text("Counter Sistem")),
      // drawer: MyDrawer(),
      
      body: Padding(
        padding: EdgeInsets.all(16),
        child: GridView.count(
          crossAxisCount: 5,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: [
            Card(
              child: Center(child: Text("LINE A")),
            ),
            Card(
              child: Center(child: Text("LINE B")),
            ),
            Card(
              child: Center(child: Text("LINE C")),
            ),
            Card(
              child: Center(child: Text("LINE D")),
            ),
            Card(
              child: Center(child: Text("LINE E")),
            ),
          ],
        ),
      ),
    );
  }
}

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
