import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class EditProcessesScreen extends StatefulWidget {
  @override
  _EditProcessesScreenState createState() => _EditProcessesScreenState();
}

class _EditProcessesScreenState extends State<EditProcessesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, List<TextEditingController>> _processControllers = {};
  Map<String, List<TextEditingController>> _sequenceControllers = {};
  bool _isLoading = true;
  ScrollController _scrollController = ScrollController();
  DateTime selectedDate = DateTime.now();

  final List<String> lines = ["A", "B", "C", "D", "E", "Z"];
  final Map<String, String> lineTitles = {
    "A": "Line A",
    "B": "Line B",
    "C": "Line C",
    "D": "Line D",
    "E": "Line E",
    "Z": "Line Z",
  };

  @override
  void initState() {
    super.initState();
    fetchProcessLines();
  }

  Future<void> fetchProcessLines() async {
    try {
      DocumentSnapshot processSnapshot = 
          await _firestore.collection('basic_data').doc('data_process').get();

      if (!processSnapshot.exists) return;

      Map<String, dynamic> processData = processSnapshot.data() as Map<String, dynamic>;

      Map<String, List<TextEditingController>> processControllers = {};
      Map<String, List<TextEditingController>> sequenceControllers = {};

      String formattedSelectedDate = DateFormat("yyyy-MM-dd").format(selectedDate);
      String formattedToday = DateFormat("yyyy-MM-dd").format(DateTime.now());

      for (String line in lines) {
        String lineKey = "process_line_$line";
        List<String> processes = 
            processData[lineKey] != null ? List<String>.from(processData[lineKey]) : [];
        
        processControllers[line] =
            processes.map((process) => TextEditingController(text: process)).toList();
        sequenceControllers[line] =
            processes.map((_) => TextEditingController()).toList();

        for (int i = 0; i < processes.length; i++) {
          String processName = processes[i];
          
          DocumentReference processRef = _firestore
              .collection('counter_sistem')
              .doc(formattedSelectedDate)
              .collection(line)
              .doc('Kumitate')
              .collection('Process')
              .doc(processName);

          DocumentSnapshot processSnapshot = await processRef.get();
          
          if (processSnapshot.exists) {
            Map<String, dynamic>? processDoc = processSnapshot.data() as Map<String, dynamic>?;
            if (processDoc != null) {
              dynamic seqValue = processDoc['sequence'];
              if (seqValue != null) {
                sequenceControllers[line]![i].text = seqValue.toString();
              }
            }
          } 
          else if (formattedSelectedDate != formattedToday) {
            DocumentReference todayProcessRef = _firestore
                .collection('counter_sistem')
                .doc(formattedToday)
                .collection(line)
                .doc('Kumitate')
                .collection('Process')
                .doc(processName);

            DocumentSnapshot todayProcessSnapshot = await todayProcessRef.get();
            
            if (todayProcessSnapshot.exists) {
              Map<String, dynamic>? todayProcessDoc = todayProcessSnapshot.data() as Map<String, dynamic>?;
              if (todayProcessDoc != null) {
                dynamic seqValue = todayProcessDoc['sequence'];
                if (seqValue != null) {
                  sequenceControllers[line]![i].text = seqValue.toString();
                }
              }
            }
          }
        }

        _sortProcessesBySequence(line, processControllers, sequenceControllers);
      }

      setState(() {
        _processControllers = processControllers;
        _sequenceControllers = sequenceControllers;
        _isLoading = false;
      });
    } catch (e) {
      print("Error fetching data: $e");
      setState(() => _isLoading = false);
    }
  }

  void _sortProcessesBySequence(
    String line, 
    Map<String, List<TextEditingController>> processControllers, 
    Map<String, List<TextEditingController>> sequenceControllers
  ) {
    List<Map<String, dynamic>> tempList = [];
    for (int i = 0; i < processControllers[line]!.length; i++) {
      tempList.add({
        'process': processControllers[line]![i].text,
        'sequence': int.tryParse(sequenceControllers[line]![i].text) ?? 0,
      });
    }

    tempList.sort((a, b) => a['sequence'].compareTo(b['sequence']));

    for (int i = 0; i < tempList.length; i++) {
      processControllers[line]![i].text = tempList[i]['process'];
      sequenceControllers[line]![i].text = tempList[i]['sequence'].toString();
    }
  }

  Future<void> saveChangesPerLine(String line) async {
    try {
      List<Map<String, dynamic>> processData = [];
      for (int i = 0; i < _processControllers[line]!.length; i++) {
        String processName = _processControllers[line]![i].text.trim();
        String sequenceText = _sequenceControllers[line]![i].text.trim();
        int sequence = sequenceText.isEmpty ? 0 : int.tryParse(sequenceText) ?? 0;
        
        if (processName.isNotEmpty) {
          processData.add({
            'process': processName,
            'sequence': sequence,
          });
        }
      }

      processData.sort((a, b) => a['sequence'].compareTo(b['sequence']));

      List<String> updatedProcesses = processData.map((e) => e['process'] as String).toList();
      await _firestore.collection('basic_data').doc('data_process').update({
        "process_line_$line": updatedProcesses,
      });

      String formattedDate = DateFormat("yyyy-MM-dd").format(selectedDate);
      WriteBatch batch = _firestore.batch();
      
      for (var item in processData) {
        DocumentReference processRef = _firestore
            .collection('counter_sistem')
            .doc(formattedDate)
            .collection(line)
            .doc('Kumitate')
            .collection('Process')
            .doc(item['process']);

        batch.set(processRef, {'sequence': item['sequence']}, SetOptions(merge: true));
      }

      await batch.commit();

      setState(() {
        for (int i = 0; i < processData.length; i++) {
          _processControllers[line]![i].text = processData[i]['process'];
          _sequenceControllers[line]![i].text = processData[i]['sequence'].toString();
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${lineTitles[line]} berhasil disimpan dan diurutkan!")),
      );
    } catch (e) {
      print("Error saving data: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal menyimpan ${lineTitles[line]}: ${e.toString()}")),
      );
    }
  }

  void addProcess(String line) {
    setState(() {
      _processControllers[line]!.add(TextEditingController(text: ""));
      _sequenceControllers[line]!.add(TextEditingController(text: "0"));
    });
  }

  void deleteProcess(String line, int index) async {
    String processName = _processControllers[line]![index].text;
    
    try {
      List<String> updatedProcesses = [];
      for (int i = 0; i < _processControllers[line]!.length; i++) {
        if (i != index) {
          updatedProcesses.add(_processControllers[line]![i].text);
        }
      }
      
      await _firestore.collection('basic_data').doc('data_process').update({
        "process_line_$line": updatedProcesses,
      });

      String formattedDate = DateFormat("yyyy-MM-dd").format(selectedDate);
      DocumentReference processRef = _firestore
          .collection('counter_sistem')
          .doc(formattedDate)
          .collection(line)
          .doc('Kumitate')
          .collection('Process')
          .doc(processName);

      await processRef.delete();

      setState(() {
        _processControllers[line]![index].dispose();
        _processControllers[line]!.removeAt(index);
        _sequenceControllers[line]![index].dispose();
        _sequenceControllers[line]!.removeAt(index);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Proses $processName dihapus dari ${lineTitles[line]}")),
      );
    } catch (e) {
      print("Error deleting process: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal menghapus proses: ${e.toString()}")),
      );
    }
  }

  Future<void> selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(Duration(days: 365)),
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
      await fetchProcessLines();
    }
  }

  @override
  void dispose() {
    _processControllers.forEach((_, controllers) {
      for (var controller in controllers) {
        controller.dispose();
      }
    });
    _sequenceControllers.forEach((_, controllers) {
      for (var controller in controllers) {
        controller.dispose();
      }
    });
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double cardWidth = 350;

    return Scaffold(
      backgroundColor: Colors.blue.shade100,
      appBar: AppBar(
        title: Text(
          'Edit Processes',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade400, Colors.blueAccent.shade700],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 4,
        actions: [
          TextButton(
            onPressed: () => selectDate(context),
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.white),
                SizedBox(width: 4),
                Text(
                  DateFormat('yyyy-MM-dd').format(selectedDate),
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh, size: 26, color: Colors.white),
            onPressed: fetchProcessLines,
          ),
        ],
      ),
      body: GestureDetector(
        onHorizontalDragUpdate: (details) {
          _scrollController.jumpTo(_scrollController.offset - details.primaryDelta!);
        },
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : Padding(
                padding: EdgeInsets.all(4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  controller: _scrollController,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: lines.map((line) {
                      return Container(
                        width: cardWidth,
                        margin: EdgeInsets.all(8),
                        child: Card(
                          color: Colors.blue.shade50,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
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
                                Expanded(
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: _processControllers[line]?.length ?? 0,
                                    itemBuilder: (context, index) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              flex: 3,
                                              child: TextField(
                                                controller: _processControllers[line]![index],
                                                decoration: InputDecoration(
                                                  labelText: "Process ${index + 1}",
                                                  border: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  contentPadding: EdgeInsets.symmetric(
                                                      horizontal: 8, vertical: 6),
                                                ),
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Container(
                                              width: 70,
                                              child: TextField(
                                                controller: _sequenceControllers[line]![index],
                                                keyboardType: TextInputType.number,
                                                decoration: InputDecoration(
                                                  labelText: "Seq",
                                                  border: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  contentPadding: EdgeInsets.symmetric(
                                                      horizontal: 8, vertical: 6),
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
      ),
    );
  }
}