import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firestore CRUD',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const FirestoreCrudPage(),
    );
  }
}

class FirestoreCrudPage extends StatefulWidget {
  const FirestoreCrudPage({super.key});

  @override
  State<FirestoreCrudPage> createState() => _FirestoreCrudPageState();
}

class _FirestoreCrudPageState extends State<FirestoreCrudPage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // Referensi koleksi Firestore
  CollectionReference get basicDataCollection =>
      firestore.collection('basic_data');

  Future<void> addItem(String fieldName, String newValue) async {
    await basicDataCollection.doc('counter').update({
      fieldName: FieldValue.arrayUnion([newValue]),
    });
  }

  Future<void> updateItem(String fieldName, String oldValue, String newValue) async {
    final docSnapshot = await basicDataCollection.doc('counter').get();
    final List<dynamic> currentArray = docSnapshot[fieldName];
    currentArray[currentArray.indexOf(oldValue)] = newValue;

    await basicDataCollection.doc('counter').update({
      fieldName: currentArray,
    });
  }

  Future<void> deleteItem(String fieldName, String valueToDelete) async {
    await basicDataCollection.doc('counter').update({
      fieldName: FieldValue.arrayRemove([valueToDelete]),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Firestore CRUD')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: basicDataCollection.doc('counter').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('No data found'));
          }

          final data = snapshot.data!;
          final lines = List<String>.from(data['line']);
          final lineNumbers = List<String>.from(data['line_number']);
          final processNames = List<String>.from(data['process_name']);

          return ListView(
            children: [
              buildSection('Line', lines, 'line'),
              buildSection('Line Number', lineNumbers, 'line_number'),
              buildSection('Process Name', processNames, 'process_name'),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) {
              String newValue = '';
              return AlertDialog(
                title: const Text('Add Item'),
                content: TextField(
                  onChanged: (value) => newValue = value,
                  decoration: const InputDecoration(hintText: 'Enter new value'),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      addItem('line', newValue);
                      Navigator.pop(context);
                    },
                    child: const Text('Add'),
                  ),
                ],
              );
            },
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget buildSection(String title, List<String> items, String fieldName) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          ListTile(
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          ...items.map((item) {
            return ListTile(
              title: Text(item),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () {
                      String updatedValue = item;
                      showDialog(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: const Text('Update Item'),
                            content: TextField(
                              onChanged: (value) => updatedValue = value,
                              decoration: const InputDecoration(hintText: 'Enter new value'),
                              controller: TextEditingController(text: item),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () {
                                  updateItem(fieldName, item, updatedValue);
                                  Navigator.pop(context);
                                },
                                child: const Text('Update'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () {
                      deleteItem(fieldName, item);
                    },
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}
