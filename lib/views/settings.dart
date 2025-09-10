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

  final List<String> lines = ["A", "B", "C", "D", "E"];
  final Map<String, String> lineTitles = {
    "A": "Line A",
    "B": "Line B",
    "C": "Line C",
    "D": "Line D",
    "E": "Line E",
  };

  @override
  void initState() {
    super.initState();
    // Initialize controllers for all lines
    for (var line in lines) {
      _processControllers[line] = [];
      _sequenceControllers[line] = [];
    }
    fetchProcessLines();
  }

  Future<void> fetchProcessLines() async {
    try {
      setState(() => _isLoading = true);
      
      DocumentSnapshot processSnapshot = 
          await _firestore.collection('basic_data').doc('data_process').get();

      if (!processSnapshot.exists) {
        print('Document data_process not found');
        setState(() => _isLoading = false);
        return;
      }

      Map<String, dynamic> processData = processSnapshot.data() as Map<String, dynamic>;
      String formattedDate = DateFormat("yyyy-MM-dd").format(selectedDate);

      for (String line in lines) {
        String lineKey = "process_line_$line";
        
        if (!processData.containsKey(lineKey) || processData[lineKey] == null) {
          print('Key $lineKey not found or null in document');
          continue;
        }

        List<String> processes = List<String>.from(processData[lineKey] ?? []);
        
        _processControllers[line] = 
            processes.map((p) => TextEditingController(text: p)).toList();
        _sequenceControllers[line] = 
            processes.map((_) => TextEditingController(text: "0")).toList();

        // Fetch sequence for each process
        CollectionReference sequenceRef = _firestore
            .collection('counter_sistem')
            .doc(formattedDate)
            .collection(line)
            .doc('Kumitate')
            .collection('Process');

        for (int i = 0; i < processes.length; i++) {
          String processName = processes[i];
          
          // Skip if process name is empty
          if (processName.isEmpty) {
            print('Empty process name at index $i in line $line');
            continue;
          }

          try {
            DocumentSnapshot seqDoc = await sequenceRef.doc(processName).get();
            
            if (seqDoc.exists && seqDoc.data() != null) {
              dynamic seqValue = (seqDoc.data() as Map<String, dynamic>)['sequence'];
              if (seqValue != null) {
                _sequenceControllers[line]![i].text = seqValue.toString();
              }
            }
          } catch (e) {
            print('Error fetching sequence for $processName: $e');
          }
        }

        _sortProcessesBySequence(line);
      }

      setState(() => _isLoading = false);
    } catch (e) {
      print("Error fetching data: $e");
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat data: ${e.toString()}')),
      );
    }
  }

  void _sortProcessesBySequence(String line) {
    List<Map<String, dynamic>> tempList = [];
    for (int i = 0; i < _processControllers[line]!.length; i++) {
      int sequence = int.tryParse(_sequenceControllers[line]![i].text) ?? 0;
      
      // Untuk sorting, kita anggap 0 sebagai angka terbesar
      int sortValue = sequence == 0 ? 999999 : sequence;
      
      tempList.add({
        'process': _processControllers[line]![i].text,
        'sequence': sequence,
        'sortValue': sortValue,
      });
    }

    tempList.sort((a, b) => a['sortValue'].compareTo(b['sortValue']));

    for (int i = 0; i < tempList.length; i++) {
      _processControllers[line]![i].text = tempList[i]['process'];
      _sequenceControllers[line]![i].text = tempList[i]['sequence'].toString();
    }
  }

  Future<void> saveChangesPerLine(String line) async {
    try {
      // Prepare data for saving
      List<Map<String, dynamic>> processData = [];
      for (int i = 0; i < _processControllers[line]!.length; i++) {
        String processName = _processControllers[line]![i].text.trim();
        int sequence = int.tryParse(_sequenceControllers[line]![i].text.trim()) ?? 0;
        
        if (processName.isNotEmpty) {
          processData.add({
            'process': processName,
            'sequence': sequence,
          });
        }
      }

      // Sort by sequence (dengan 0 dianggap sebagai angka terbesar)
      processData.sort((a, b) {
        int aValue = a['sequence'] == 0 ? 999999 : a['sequence'];
        int bValue = b['sequence'] == 0 ? 999999 : b['sequence'];
        return aValue.compareTo(bValue);
      });

      // 1. Save process names to basic_data
      await _firestore.collection('basic_data').doc('data_process').update({
        "process_line_$line": processData.map((e) => e['process']).toList(),
      });

      // 2. Save sequences to counter_sistem with merge option - HANYA untuk sequence yang bukan 0
      String formattedDate = DateFormat("yyyy-MM-dd").format(selectedDate);
      WriteBatch batch = _firestore.batch();
      
      // First get all existing processes to clean up removed ones
      QuerySnapshot existingProcesses = await _firestore
          .collection('counter_sistem')
          .doc(formattedDate)
          .collection(line)
          .doc('Kumitate')
          .collection('Process')
          .get();

      // Create set of current process names
      Set<String> currentProcesses = processData.map((e) => e['process'] as String).toSet();

      // Delete processes that were removed
      for (DocumentSnapshot doc in existingProcesses.docs) {
        if (!currentProcesses.contains(doc.id)) {
          batch.delete(doc.reference);
        }
      }

      // Update or add new processes - HANYA untuk sequence yang bukan 0
      for (var item in processData) {
        // Jangan simpan sequence 0 ke Firebase
        if (item['sequence'] == 0) continue;
        
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

      // Update UI with sorted data
      setState(() {
        for (int i = 0; i < processData.length; i++) {
          _processControllers[line]![i].text = processData[i]['process'];
          _sequenceControllers[line]![i].text = processData[i]['sequence'].toString();
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${lineTitles[line]} berhasil disimpan!")),
      );
    } catch (e) {
      print("Error saving data: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal menyimpan ${lineTitles[line]}: $e")),
      );
    }
  }

  void addProcess(String line) {
    setState(() {
      _processControllers[line]!.add(TextEditingController(text: "New Process"));
      _sequenceControllers[line]!.add(TextEditingController(text: "0"));
    });
  }

  void deleteProcess(String line, int index) async {
    String processName = _processControllers[line]![index].text;
    
    try {
      // Update basic_data
      List<String> updatedProcesses = [];
      for (int i = 0; i < _processControllers[line]!.length; i++) {
        if (i != index) {
          updatedProcesses.add(_processControllers[line]![i].text);
        }
      }
      
      await _firestore.collection('basic_data').doc('data_process').update({
        "process_line_$line": updatedProcesses,
      });

      // Delete from counter_sistem
      String formattedDate = DateFormat("yyyy-MM-dd").format(selectedDate);
      await _firestore
          .collection('counter_sistem')
          .doc(formattedDate)
          .collection(line)
          .doc('Kumitate')
          .collection('Process')
          .doc(processName)
          .delete();

      setState(() {
        _processControllers[line]![index].dispose();
        _processControllers[line]!.removeAt(index);
        _sequenceControllers[line]![index].dispose();
        _sequenceControllers[line]!.removeAt(index);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Process $processName deleted from ${lineTitles[line]}")),
      );
    } catch (e) {
      print("Error deleting process: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to delete process: ${e.toString()}")),
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
      setState(() => selectedDate = picked);
      await fetchProcessLines();
    }
  }

  @override
  void dispose() {
    _processControllers.forEach((_, controllers) => controllers.forEach((c) => c.dispose()));
    _sequenceControllers.forEach((_, controllers) => controllers.forEach((c) => c.dispose()));
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
                                        // IconButton untuk tambah proses dihilangkan
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
                                              child: TextFormField(
                                                controller: _processControllers[line]![index],
                                                enabled: false, // Tidak bisa di edit
                                                decoration: InputDecoration(
                                                  labelText: "Process ${index + 1}",
                                                  border: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  contentPadding: EdgeInsets.symmetric(
                                                      horizontal: 8, vertical: 6),
                                                  filled: true,
                                                  fillColor: Colors.grey[200],
                                                ),
                                                style: TextStyle(
                                                  color: Colors.grey[700],
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
                                            // IconButton untuk hapus proses dihilangkan
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