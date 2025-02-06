import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/esp32_provider.dart';

class CounterDataView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basicData = ref.watch(basicDataProvider);

    return Scaffold(
      appBar: AppBar(title: Text("Data Process")),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, ref),
        child: Icon(Icons.add),
      ),
      body: Padding(
        padding: EdgeInsets.only(left: 20.0, right: 20.0, top: 10.0, bottom: 15.0),
        child: basicData.when(
          loading: () => Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text("Error: $err")),
          data: (data) {
            if (data == null) return Center(child: Text("No Data Found"));

            final processNames = List<String>.from(data['process_name'] ?? []);

            return ListView.builder(
              itemCount: processNames.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: EdgeInsets.only(left: 8.0, right: 64.0, top: 4.0, bottom: 2.0),
                  child: Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      contentPadding: EdgeInsets.only(left: 12.0, right: 12.0, top: 6.0, bottom: 6.0),
                      leading: CircleAvatar(child: Text("${index + 1}")),
                      title: Text(processNames[index], style: TextStyle(fontSize: 14.0)),
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
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final _controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Add Process"),
          content: Padding(
            padding: EdgeInsets.all(8.0),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(labelText: "Enter process name"),
            ),
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

  void _showEditDialog(BuildContext context, WidgetRef ref, int index, String currentName) {
    final _controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Edit Process"),
          content: Padding(
            padding: EdgeInsets.all(8.0),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(labelText: "Enter new name"),
            ),
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
