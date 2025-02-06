import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/esp32_provider.dart';

class CounterDataView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basicData = ref.watch(basicDataProvider);

    return Scaffold(
      appBar: AppBar(title: Text("Counter Data")),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, ref),
        child: Icon(Icons.add),
      ),
      body: basicData.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text("Error: $err")),
        data: (data) {
          if (data == null) return Center(child: Text("No Data Found"));

          final processNames = List<String>.from(data['process_name'] ?? []);

          return ListView.builder(
            itemCount: processNames.length,
            itemBuilder: (context, index) {
              return ListTile(
                leading: CircleAvatar(child: Text("${index + 1}")),
                title: Text(processNames[index]),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => _showEditDialog(context, ref, index, processNames[index]),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        ref.read(deleteProcessProvider(index));
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // 🔹 Dialog untuk menambah proses baru
  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final _controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Add Process"),
          content: TextField(
            controller: _controller,
            decoration: InputDecoration(labelText: "Enter process name"),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel")),
            TextButton(
              onPressed: () {
                final newProcess = _controller.text.trim();
                if (newProcess.isNotEmpty) {
                  ref.read(addProcessProvider(newProcess));
                  Navigator.pop(context);
                }
              },
              child: Text("Add"),
            ),
          ],
        );
      },
    );
  }

  // 🔹 Dialog untuk mengupdate proses
  void _showEditDialog(BuildContext context, WidgetRef ref, int index, String currentName) {
    final _controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Edit Process"),
          content: TextField(
            controller: _controller,
            decoration: InputDecoration(labelText: "Enter new name"),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel")),
            TextButton(
              onPressed: () {
                final updatedName = _controller.text.trim();
                if (updatedName.isNotEmpty) {
                  ref.read(updateProcessProvider({'index': index, 'updatedName': updatedName}));
                  Navigator.pop(context);
                }
              },
              child: Text("Update"),
            ),
          ],
        );
      },
    );
  }
}