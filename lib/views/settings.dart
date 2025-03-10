import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditProcessesScreen extends StatefulWidget {
  @override
  _EditProcessesScreenState createState() => _EditProcessesScreenState();
}

class _EditProcessesScreenState extends State<EditProcessesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, List<TextEditingController>> _controllers = {};
  bool _isLoading = true;

  final Map<String, String> lineTitles = {
    "process_line_A": "Process Name Line A",
    "process_line_B": "Process Name Line B",
    "process_line_C": "Process Name Line C",
    "process_line_D": "Process Name Line D",
    "process_line_E": "Process Name Line E",
  };

  @override
  void initState() {
    super.initState();
    fetchProcessLines();
  }

  Future<void> fetchProcessLines() async {
    try {
      DocumentSnapshot snapshot = await _firestore
          .collection('basic_data')
          .doc('data_process')
          .get();

      if (!snapshot.exists) return;

      Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;

      List<String> orderedLines = ["process_line_A", "process_line_B", "process_line_C", "process_line_D", "process_line_E"];

      Map<String, List<TextEditingController>> controllers = {};

      for (String line in orderedLines) {
        List<String> processes = data[line] != null ? List<String>.from(data[line]) : [];
        controllers[line] = processes.map((process) => TextEditingController(text: process)).toList();
      }

      setState(() {
        _controllers = controllers;
        _isLoading = false;
      });
    } catch (e) {
      print("Error fetching data: $e");
    }
  }

  Future<void> saveChangesPerLine(String line) async {
    try {
      List<String> updatedProcesses = _controllers[line]!
          .map((controller) => controller.text.trim())
          .where((text) => text.isNotEmpty)
          .toList();

      await _firestore.collection('basic_data').doc('data_process').update({
        line: updatedProcesses,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${lineTitles[line]} berhasil disimpan!")),
      );
    } catch (e) {
      print("Error updating data for $line: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal menyimpan ${lineTitles[line]}")),
      );
    }
  }

  void addProcess(String line) {
    setState(() {
      _controllers[line]!.add(TextEditingController(text: ""));
    });
  }

  void deleteProcess(String line, int index) {
    setState(() {
      _controllers[line]!.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Edit Processes Per Line')),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12.0), // Padding untuk seluruh layar
              child: ListView(
                children: _controllers.keys.map((line) {
                  return Card(
                    elevation: 3, // Efek shadow agar lebih menarik
                    margin: EdgeInsets.only(bottom: 12), // Spasi antar card
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Column(
                        children: [
                          // Header dengan Nama Line + Tombol Aksi
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                lineTitles[line]!,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey[800],
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.add, color: Colors.green),
                                    onPressed: () => addProcess(line),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.save, color: Colors.blue),
                                    onPressed: () => saveChangesPerLine(line),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Divider(), // Garis pemisah

                          // List Item Process
                          Column(
                            children: _controllers[line]!.asMap().entries.map((entry) {
                              int index = entry.key;
                              TextEditingController controller = entry.value;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6), // Spasi antar TextField
                                child: Row(
                                  children: [
                                    // Label Nomor Urut
                                    Text(
                                      "${index + 1}. ",
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                    ),
                                    Expanded(
                                      child: TextField(
                                        controller: controller,
                                        decoration: InputDecoration(
                                          labelText: "Process ${index + 1}",
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 8), // Jarak kecil antara TextField dan tombol hapus
                                    IconButton(
                                      icon: Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => deleteProcess(line, index),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
    );
  }
}
