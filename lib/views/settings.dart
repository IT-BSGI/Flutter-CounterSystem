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
    "process_line_A": "Line A",
    "process_line_B": "Line B",
    "process_line_C": "Line C",
    "process_line_D": "Line D",
    "process_line_E": "Line E",
  };

  @override
  void initState() {
    super.initState();
    fetchProcessLines();
  }

  Future<void> fetchProcessLines() async {
    try {
      DocumentSnapshot snapshot =
          await _firestore.collection('basic_data').doc('data_process').get();

      if (!snapshot.exists) return;

      Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;

      List<String> orderedLines = [
        "process_line_A",
        "process_line_B",
        "process_line_C",
        "process_line_D",
        "process_line_E"
      ];

      Map<String, List<TextEditingController>> controllers = {};

      for (String line in orderedLines) {
        List<String> processes =
            data[line] != null ? List<String>.from(data[line]) : [];
        controllers[line] =
            processes.map((process) => TextEditingController(text: process)).toList();
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
      _controllers[line]![index].dispose();
      _controllers[line]!.removeAt(index);
    });
  }

  @override
  void dispose() {
    _controllers.forEach((key, controllers) {
      for (var controller in controllers) {
        controller.dispose();
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Edit Processes')),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Padding(
              padding: EdgeInsets.all(8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal, // Scroll secara horizontal
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _controllers.keys.map((line) {
                    return Container(
                      width: 250, // Lebar setiap card agar tidak terlalu kecil
                      margin: EdgeInsets.only(right: 12), // Jarak antar line
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header dengan Nama Line + Tombol Aksi
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    lineTitles[line]!,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.add, size: 18, color: Colors.green),
                                        onPressed: () => addProcess(line),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.save, size: 18, color: Colors.blue),
                                        onPressed: () => saveChangesPerLine(line),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              Divider(),
                              // List Item Process
                              Expanded(
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _controllers[line]!.length,
                                  itemBuilder: (context, index) {
                                    TextEditingController controller =
                                        _controllers[line]![index];
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: controller,
                                              decoration: InputDecoration(
                                                labelText: "Process ${index + 1}",
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                contentPadding:
                                                    EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 6),
                                          IconButton(
                                            icon: Icon(Icons.delete, size: 18, color: Colors.red),
                                            onPressed: () => deleteProcess(line, index),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
    );
  }
}
