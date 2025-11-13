import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:dropdown_search/dropdown_search.dart';

class EditProcessesScreen extends StatefulWidget {
  @override
  _EditProcessesScreenState createState() => _EditProcessesScreenState();
}

class _EditProcessesScreenState extends State<EditProcessesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, List<String>> _baseProcesses = {};
  // Simpan daftar proses khusus PART per line (diisi dari basic_data.data_process.process_part)
  Map<String, List<String>> _partProcesses = {};
  // Scroll controllers untuk area kontrak tiap line (agar bisa menampilkan scrollbar horizontal)
  Map<String, ScrollController> _contractsScrollControllers = {};
  Map<String, List<String>> _contracts = {};
  Map<String, String> _selectedContracts = {};
  Map<String, Map<String, List<Map<String, dynamic>>>> _contractProcessData = {};
  bool _isLoading = true;
  DateTime selectedDate = DateTime.now();
  ScrollController _scrollController = ScrollController();
  List<String> _allContracts = [];

  final List<String> lines = ["A", "B", "C", "D", "E"];
  final Map<String, String> lineTitles = {
    "A": "Line A", "B": "Line B", "C": "Line C", 
    "D": "Line D", "E": "Line E",
  };

  // Fungsi untuk mengubah underscore menjadi spasi
  String _formatProcessName(String processName) {
    return processName.replaceAll('_', ' ');
  }

  @override
  void initState() {
    super.initState();
    for (var line in lines) {
      _baseProcesses[line] = [];
      _partProcesses[line] = [];
      _contractsScrollControllers[line] = ScrollController();
      _contracts[line] = [];
      _selectedContracts[line] = "";
      _contractProcessData[line] = {};
    }
    fetchMasterContracts();
  }

  @override
  void dispose() {
    // Dispose semua contracts scroll controllers
    for (var c in _contractsScrollControllers.values) {
      try {
        c.dispose();
      } catch (_) {}
    }
    
    try {
      _scrollController.dispose();
    } catch (_) {}
    super.dispose();
  }

  // Fungsi untuk mendapatkan document reference
  DocumentReference _getDocRef(String line, String formattedDate, String mode) {
    return _firestore
        .collection('counter_sistem')
        .doc(formattedDate)
        .collection(line)
        .doc(mode);
  }

  Future<void> fetchMasterContracts() async {
    try {
      // Mengambil kontrak dari struktur baru: basic_data/data_contracts/contracts/
      QuerySnapshot contractsSnapshot = 
          await _firestore
              .collection('basic_data')
              .doc('data_contracts')
              .collection('contracts')
              .get();
      
      if (contractsSnapshot.docs.isNotEmpty) {
        setState(() {
          _allContracts = contractsSnapshot.docs.map((doc) => doc.id).toList()..sort();
        });
      } else {
        // Fallback ke struktur lama jika struktur baru tidak ada
        DocumentSnapshot oldContractsSnapshot = 
            await _firestore.collection('basic_data').doc('contracts').get();
        
        if (oldContractsSnapshot.exists) {
          Map<String, dynamic> contractsData = _convertToStringDynamicMap(oldContractsSnapshot.data());
          setState(() {
            _allContracts = contractsData.keys.where((key) => key.isNotEmpty).toList()..sort();
          });
        } else {
          setState(() {
            _allContracts = [];
          });
        }
      }
      
      await fetchProcessLines();
    } catch (e) {
      // Fallback ke struktur lama jika error
      try {
        DocumentSnapshot oldContractsSnapshot = 
            await _firestore.collection('basic_data').doc('contracts').get();
        
        if (oldContractsSnapshot.exists) {
          Map<String, dynamic> contractsData = _convertToStringDynamicMap(oldContractsSnapshot.data());
          setState(() {
            _allContracts = contractsData.keys.where((key) => key.isNotEmpty).toList()..sort();
          });
        } else {
          setState(() {
            _allContracts = [];
          });
        }
        
        await fetchProcessLines();
      } catch (fallbackError) {
        await fetchProcessLines();
      }
    }
  }

  Map<String, dynamic> _convertToStringDynamicMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    } else if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {};
  }

  Future<void> fetchProcessLines() async {
    try {
      setState(() => _isLoading = true);
      // Ambil data proses umum dan khusus PART dari basic_data.data_process
      DocumentSnapshot processSnapshot = 
          await _firestore.collection('basic_data').doc('data_process').get();

      if (!processSnapshot.exists) {
        setState(() => _isLoading = false);
        return;
      }

      Map<String, dynamic> processData = _convertToStringDynamicMap(processSnapshot.data());

      // Isi _partProcesses jika ada field process_part
      if (processData.containsKey('process_part') && processData['process_part'] is List) {
        List<dynamic> partDyn = processData['process_part'];
        List<String> partList = partDyn.map((e) => e.toString()).toList();
        for (String line in lines) {
          _partProcesses[line] = partList;
        }
      }
      String formattedDate = DateFormat("yyyy-MM-dd").format(selectedDate);

      for (String line in lines) {
        String lineKey = "process_line_$line";
        if (!processData.containsKey(lineKey) || processData[lineKey] == null) {
          continue;
        }

        List<dynamic> processesDynamic = processData[lineKey] is List ? processData[lineKey] : [];
        List<String> processes = processesDynamic.map((item) => item.toString()).toList();
        
        _baseProcesses[line] = processes;
        await _fetchContractsFromCounterSistem(line, formattedDate);
        await _fetchContractProcesses(line, formattedDate);
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat data: ${e.toString()}')),
      );
    }
  }

  Future<void> _fetchContractsFromCounterSistem(String line, String formattedDate) async {
    try {
      // Ambil kontrak dari kedua mode (Kumitate dan Part)
      DocumentReference kumitateDocRef = _getDocRef(line, formattedDate, 'Kumitate');
      DocumentReference partDocRef = _getDocRef(line, formattedDate, 'Part');

      DocumentSnapshot kumitateSnapshot = await kumitateDocRef.get();
      DocumentSnapshot partSnapshot = await partDocRef.get();
      
      List<String> existingContracts = [];
      
      // Cek dari dokumen Kumitate
      if (kumitateSnapshot.exists) {
        Map<String, dynamic> data = _convertToStringDynamicMap(kumitateSnapshot.data());
        
        if (data.containsKey('Kontrak') && data['Kontrak'] is List) {
          List<dynamic> contractsArray = data['Kontrak'];
          for (var contract in contractsArray) {
            if (contract is String && contract.isNotEmpty && !existingContracts.contains(contract)) {
              existingContracts.add(contract);
            }
          }
        } else {
          data.forEach((key, value) {
            if (key != 'created' && key != 'updated' && key != 'contract_name' && 
                key.isNotEmpty && !existingContracts.contains(key)) {
              existingContracts.add(key);
            }
          });
        }
      }

      // Cek dari dokumen Part
      if (partSnapshot.exists) {
        Map<String, dynamic> data = _convertToStringDynamicMap(partSnapshot.data());
        
        if (data.containsKey('Kontrak') && data['Kontrak'] is List) {
          List<dynamic> contractsArray = data['Kontrak'];
          for (var contract in contractsArray) {
            if (contract is String && contract.isNotEmpty && !existingContracts.contains(contract)) {
              existingContracts.add(contract);
            }
          }
        }
      }

      setState(() {
        List<String> previousContracts = _contracts[line] ?? [];
        Set<String> allContracts = Set<String>.from(previousContracts);
        allContracts.addAll(existingContracts);
        
        _contracts[line] = allContracts.toList();
        
        if (_contracts[line]!.isNotEmpty && 
            (_selectedContracts[line]!.isEmpty || !_contracts[line]!.contains(_selectedContracts[line]))) {
          _selectedContracts[line] = _contracts[line]!.first;
        } else if (_contracts[line]!.isEmpty) {
          _selectedContracts[line] = "";
        }
      });
    } catch (e) {
      print("Error fetching contracts: $e");
    }
  }

  Future<void> _fetchContractProcesses(String line, String formattedDate) async {
    try {
      Map<String, List<Map<String, dynamic>>> contractData = {};
      
      DocumentReference kumitateDocRef = _getDocRef(line, formattedDate, 'Kumitate');

      DocumentSnapshot snapshot = await kumitateDocRef.get();
      List<String> contractOrder = [];
      
      if (snapshot.exists) {
        Map<String, dynamic> data = _convertToStringDynamicMap(snapshot.data());
        
        // Baca urutan kontrak dari field 'Kontrak'
        if (data.containsKey('Kontrak') && data['Kontrak'] is List) {
          List<dynamic> contractsArray = data['Kontrak'];
          contractOrder = contractsArray.map((item) => item.toString()).toList();
        }
      }
      
      // Jika tidak ada urutan, gunakan urutan dari _contracts[line]
      if (contractOrder.isEmpty) {
        contractOrder = List<String>.from(_contracts[line]!);
      }
      
      for (String contract in _contracts[line]!) {
        List<Map<String, dynamic>> processes = [];
        bool foundInNewStructure = false;
        
        if (snapshot.exists) {
          Map<String, dynamic> data = _convertToStringDynamicMap(snapshot.data());
          
          // Cek struktur array of strings untuk proses
          if (data.containsKey(contract) && data[contract] is List) {
            List<dynamic> contractArray = data[contract];
            
            for (int i = 0; i < contractArray.length; i++) {
              String processName = contractArray[i].toString();
              int sequence = i + 1;
              
              processes.add({
                'name': processName,
                'sequence': sequence,
              });
            }
            
            foundInNewStructure = true;
          }
        }
        
        // Jika tidak ditemukan di struktur baru, cek struktur lama
        if (!foundInNewStructure) {
          try {
            CollectionReference contractCollectionRef = kumitateDocRef.collection(contract);
            QuerySnapshot processSnapshot = await contractCollectionRef.get();
            
            if (processSnapshot.docs.isNotEmpty) {
              // Ambil data proses yang sudah ada termasuk data counter dari Arduino
              for (DocumentSnapshot doc in processSnapshot.docs) {
                Map<String, dynamic> processData = _convertToStringDynamicMap(doc.data());
                
                processes.add({
                  'name': doc.id,
                  'sequence': processData['sequence'] ?? 0,
                  'existing_data': processData,
                });
              }
              
              // Urutkan berdasarkan sequence
              processes.sort((a, b) => (a['sequence'] ?? 0).compareTo(b['sequence'] ?? 0));
            } else {
              // Default: semua sequence 0
              for (String processName in _baseProcesses[line]!) {
                processes.add({
                  'name': processName,
                  'sequence': 0,
                });
              }
            }
          } catch (e) {
            print("Error reading subcollection: $e");
            // Default: semua sequence 0
            for (String processName in _baseProcesses[line]!) {
              processes.add({
                'name': processName,
                'sequence': 0,
              });
            }
          }
        }

        contractData[contract] = processes;
      }

      setState(() {
        _contractProcessData[line] = contractData;
        
        // Urutkan kontrak berdasarkan urutan di field 'Kontrak'
        if (contractOrder.isNotEmpty) {
          _contracts[line]!.sort((a, b) {
            int indexA = contractOrder.indexOf(a);
            int indexB = contractOrder.indexOf(b);
            
            if (indexA == -1 && indexB == -1) return a.compareTo(b);
            if (indexA == -1) return 1;
            if (indexB == -1) return -1;
            
            return indexA.compareTo(indexB);
          });
        }
      });
    } catch (e) {
      print("Error fetching contract processes: $e");
    }
  }

  List<Map<String, dynamic>> _getSortedProcesses(String line, String contract) {
    if (_contractProcessData[line] == null || 
        _contractProcessData[line]![contract] == null) {
      return [];
    }
    
    List<Map<String, dynamic>> processes = List<Map<String, dynamic>>.from(
      _contractProcessData[line]![contract]!
    );
    
    processes.sort((a, b) {
      int aSeq = a['sequence'] ?? 0;
      int bSeq = b['sequence'] ?? 0;
      
      if (aSeq == 0 && bSeq == 0) return 0;
      if (aSeq == 0) return 1;
      if (bSeq == 0) return -1;
      
      return aSeq.compareTo(bSeq);
    });
    
    return processes;
  }

  Future<void> saveChangesPerLine(String line) async {
    try {
      if (_contracts[line]!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Tidak ada kontrak untuk disimpan!")),
        );
        return;
      }

      String formattedDate = DateFormat("yyyy-MM-dd").format(selectedDate);
      
      // Simpan ke kedua mode (Kumitate dan Part)
      DocumentReference kumitateDocRef = _getDocRef(line, formattedDate, 'Kumitate');
      DocumentReference partDocRef = _getDocRef(line, formattedDate, 'Part');

      // STRUKTUR BARU: Simpan array kontrak untuk menjaga urutan dengan field 'Kontrak'
      Map<String, dynamic> kumitateUpdateData = {
        'Kontrak': _contracts[line]!, // Array of contract names
      };

      Map<String, dynamic> partUpdateData = {
        'Kontrak': _contracts[line]!, // Array of contract names
      };

      // Simpan proses untuk Kumitate
      for (String contract in _contracts[line]!) {
        List<Map<String, dynamic>> currentProcesses = _contractProcessData[line]![contract] ?? [];
        
        // Urutkan processes berdasarkan sequence
        currentProcesses.sort((a, b) {
          int aSeq = a['sequence'] ?? 0;
          int bSeq = b['sequence'] ?? 0;
          return aSeq.compareTo(bSeq);
        });
        
        // Hanya simpan nama proses yang memiliki sequence > 0
        List<String> processNamesWithSequence = [];
        for (var process in currentProcesses) {
          String processName = process['name'];
          int sequence = process['sequence'] ?? 0;
          if (sequence > 0) {
            processNamesWithSequence.add(processName);
          }
        }
        
        if (processNamesWithSequence.isNotEmpty) {
          kumitateUpdateData[contract] = processNamesWithSequence;
        } else {
          // Hapus field kontrak jika tidak ada proses dengan sequence > 0
          kumitateUpdateData[contract] = FieldValue.delete();
        }

        // Untuk Part, simpan semua proses (tanpa sequence)
        List<String> partProcessNames = [];
        List<String> src = (_partProcesses[line] != null && _partProcesses[line]!.isNotEmpty)
            ? _partProcesses[line]!
            : _baseProcesses[line]!;
        for (String processName in src) {
          partProcessNames.add(processName);
        }
        partUpdateData[contract] = partProcessNames;
      }

      await kumitateDocRef.set(kumitateUpdateData, SetOptions(merge: true));
      await partDocRef.set(partUpdateData, SetOptions(merge: true));

      // Simpan processes dengan mempertahankan data counter yang sudah ada untuk Kumitate
      for (String contract in _contracts[line]!) {
        CollectionReference contractCollectionRef = kumitateDocRef.collection(contract);
        
        List<Map<String, dynamic>> currentProcesses = _contractProcessData[line]![contract] ?? [];
        for (var process in currentProcesses) {
          String processName = process['name'];
          int sequence = process['sequence'] ?? 0;
          
          if (sequence > 0) {
            DocumentReference processDocRef = contractCollectionRef.doc(processName);
            
            Map<String, dynamic> updateProcessData = {
              'sequence': sequence,
            };
            
            // Jika ada data existing, pertahankan field-field lainnya
            if (process.containsKey('existing_data') && process['existing_data'] is Map) {
              Map<String, dynamic> existingData = Map<String, dynamic>.from(process['existing_data']);
              existingData.remove('sequence');
              existingData.remove('updated');
              updateProcessData.addAll(existingData);
            }
            
            await processDocRef.set(updateProcessData, SetOptions(merge: true));
          } else {
            DocumentReference processDocRef = contractCollectionRef.doc(processName);
            DocumentSnapshot processSnapshot = await processDocRef.get();
            
            if (processSnapshot.exists) {
              await processDocRef.update({
                'sequence': FieldValue.delete(),
              });
            }
          }
        }
      }

      // Buat/Perbarui subcollections kontrak di dokumen Part
      try {
        for (String contract in _contracts[line]!) {
          List<String> processNames = partUpdateData[contract] is List ? List<String>.from(partUpdateData[contract]) : [];
          if (processNames.isEmpty) continue;

          CollectionReference contractCol = partDocRef.collection(contract);
          for (String pname in processNames) {
            await contractCol.doc(pname).set({'part': ''}, SetOptions(merge: true));
          }
        }
      } catch (e) {
        print('Gagal membuat subcollections untuk Part saat menyimpan: $e');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${lineTitles[line]} berhasil disimpan! Urutan kontrak: ${_contracts[line]!.join(', ')}")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal menyimpan ${lineTitles[line]}: $e")),
      );
    }
  }

  // Fungsi untuk mendapatkan proses Kumitate dari data_process
  Future<List<String>> _getKumitateProcesses() async {
    try {
      DocumentSnapshot processSnapshot = 
          await _firestore.collection('basic_data').doc('data_process').get();
      
      if (processSnapshot.exists) {
        Map<String, dynamic> processData = _convertToStringDynamicMap(processSnapshot.data());
        
        // Cek field process_kumitate
        if (processData.containsKey('process_kumitate') && processData['process_kumitate'] is List) {
          List<dynamic> kumitateDyn = processData['process_kumitate'];
          return kumitateDyn.map((e) => e.toString()).toList();
        }
      }
    } catch (e) {
      print("Error fetching kumitate processes: $e");
    }
    return [];
  }

  // Fungsi untuk menampilkan dialog input sequence
  Future<Map<String, int>?> _showSequenceDialog(List<String> processes) async {
    Map<String, int> sequenceMap = {};
    List<TextEditingController> controllers = [];
    List<FocusNode> focusNodes = [];
    
    for (String process in processes) {
      sequenceMap[process] = 0;
      controllers.add(TextEditingController());
      focusNodes.add(FocusNode());
    }
    
    return showDialog<Map<String, int>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(
                "Atur Sequence untuk Kontrak",
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.blue.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: Colors.blue.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.blue.shade300, width: 1),
              ),
              content: Container(
                width: 400, // Lebar dialog diperkecil
                height: 450, // Tinggi dialog ditambah
                child: Column(
                  children: [
                    SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: processes.length,
                        itemBuilder: (context, index) {
                          String process = processes[index];
                          return Container(
                            margin: EdgeInsets.only(bottom: 8),
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _formatProcessName(process),
                                    style: TextStyle(
                                      fontSize: 16, // Font nama proses diperbesar
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 10),
                                Container(
                                  width: 80,
                                  child: TextField(
                                    controller: controllers[index],
                                    focusNode: focusNodes[index],
                                    keyboardType: TextInputType.number,
                                    textInputAction: index < processes.length - 1 
                                        ? TextInputAction.next 
                                        : TextInputAction.done,
                                    decoration: InputDecoration(
                                      labelText: "Sequence",
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    ),
                                    onChanged: (value) {
                                      int seq = int.tryParse(value) ?? 0;
                                      sequenceMap[process] = seq;
                                    },
                                    onSubmitted: (value) {
                                      // Pindah ke field berikutnya ketika tekan Enter
                                      if (index < processes.length - 1) {
                                        FocusScope.of(context).requestFocus(focusNodes[index + 1]);
                                      } else {
                                        // Jika field terakhir, tutup keyboard
                                        FocusScope.of(context).unfocus();
                                      }
                                    },
                                  ),
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    "Batal",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context, sequenceMap);
                  },
                  child: Text(
                    "Simpan",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> addContractToMaster() async {
    TextEditingController controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            "Tambah Kontrak ke Master List",
            style: TextStyle(
              fontSize: 18,
              color: Colors.blue.shade800,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.blue.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.blue.shade300, width: 1),
          ),
          content: TextField(
            controller: controller,
            style: TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: "Nama Kontrak",
              hintStyle: TextStyle(fontSize: 16),
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                "Batal",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blue.shade800,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                if (controller.text.trim().isNotEmpty) {
                  String contractName = controller.text.trim();
                  
                  if (_allContracts.contains(contractName)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Kontrak '$contractName' sudah ada!")),
                    );
                    return;
                  }

                  Navigator.pop(context); // Tutup dialog input nama
                  
                  // Ambil daftar proses Kumitate
                  List<String> kumitateProcesses = await _getKumitateProcesses();
                  
                  if (kumitateProcesses.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Tidak ada proses Kumitate yang ditemukan!")),
                    );
                    return;
                  }
                  
                  // Tampilkan dialog input sequence
                  Map<String, int>? sequenceMap = await _showSequenceDialog(kumitateProcesses);
                  
                  if (sequenceMap == null) {
                    // User membatalkan input sequence
                    return;
                  }
                  
                  try {
                    // Hanya simpan ke struktur baru: basic_data/data_contracts/contracts/(nama kontrak)
                    // Hanya simpan proses dengan sequence > 0
                    Map<String, dynamic> contractProcessData = {};
                    
                    for (String process in kumitateProcesses) {
                      int sequence = sequenceMap[process] ?? 0;
                      if (sequence > 0) {
                        contractProcessData[process] = sequence;
                      }
                    }
                    
                    await _firestore.collection('basic_data').doc('data_contracts')
                        .collection('contracts').doc(contractName)
                        .set(contractProcessData);
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Kontrak '$contractName' berhasil ditambahkan dengan ${contractProcessData.length} proses aktif!")),
                    );

                    setState(() {
                      _allContracts.add(contractName);
                      _allContracts.sort();
                    });
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Gagal menambah kontrak: $e")),
                    );
                  }
                }
              },
              child: Text(
                "Lanjut",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blue.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Fungsi untuk mengambil proses dan sequence dari master kontrak
  Future<Map<String, dynamic>?> _getContractProcessesFromMaster(String contractName) async {
    try {
      DocumentSnapshot contractSnapshot = await _firestore
          .collection('basic_data')
          .doc('data_contracts')
          .collection('contracts')
          .doc(contractName)
          .get();
      
      if (contractSnapshot.exists) {
        return _convertToStringDynamicMap(contractSnapshot.data());
      }
    } catch (e) {
      print("Error fetching contract processes from master: $e");
    }
    return null;
  }

  Future<void> addContractToLine(String line) async {
    String? selectedContract;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(
                "Tambah Kontrak ke ${lineTitles[line]}",
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.blue.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: Colors.blue.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.blue.shade300, width: 1),
              ),
              content: Container(
                width: 280,
                child: DropdownSearch<String>(
                  popupProps: PopupProps.dialog(
                    showSearchBox: true,
                    searchFieldProps: TextFieldProps(
                      style: TextStyle(fontSize: 16),
                      decoration: InputDecoration(
                        hintText: "Cari kontrak...",
                        hintStyle: TextStyle(fontSize: 16),
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search, color: Colors.blue.shade600),
                        filled: true,
                        fillColor: Colors.blue.shade50,
                      ),
                    ),
                    dialogProps: DialogProps(
                      backgroundColor: Colors.blue.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    itemBuilder: (context, item, isSelected) {
                      return Container(
                        margin: EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.blue.shade100 : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: ListTile(
                          title: Text(
                            item,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  items: _allContracts,
                  dropdownBuilder: (context, selectedItem) {
                    return Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.shade400),
                      ),
                      child: Text(
                        selectedItem ?? "Pilih kontrak",
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    );
                  },
                  dropdownDecoratorProps: DropDownDecoratorProps(
                    dropdownSearchDecoration: InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  onChanged: (value) {
                    setStateDialog(() {
                      selectedContract = value;
                    });
                  },
                  selectedItem: selectedContract,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    "Batal",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    if (selectedContract != null && selectedContract!.isNotEmpty) {
                      try {
                        // Ambil proses dan sequence dari master kontrak
                        Map<String, dynamic>? masterProcesses = await _getContractProcessesFromMaster(selectedContract!);
                        
                        List<Map<String, dynamic>> newProcesses = [];
                        
                        if (masterProcesses != null && masterProcesses.isNotEmpty) {
                          // Gunakan proses dari master kontrak
                          masterProcesses.forEach((processName, sequence) {
                            newProcesses.add({
                              'name': processName,
                              'sequence': sequence is int ? sequence : 0,
                            });
                          });
                          
                          // Urutkan berdasarkan sequence
                          newProcesses.sort((a, b) => (a['sequence'] ?? 0).compareTo(b['sequence'] ?? 0));
                        } else {
                          // Fallback: gunakan base processes dengan sequence 0
                          newProcesses = _baseProcesses[line]!
                              .map((processName) => {'name': processName, 'sequence': 0})
                              .toList();
                        }
                        
                        setState(() {
                          if (!_contracts[line]!.contains(selectedContract!)) {
                            _contracts[line]!.add(selectedContract!);
                          }
                          
                          if (_contractProcessData[line] == null) {
                            _contractProcessData[line] = {};
                          }
                          
                          _contractProcessData[line]![selectedContract!] = newProcesses;
                          _selectedContracts[line] = selectedContract!;
                        });

                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Kontrak '$selectedContract' berhasil ditambahkan ke ${lineTitles[line]} pada urutan ke-${_contracts[line]!.length}")),
                        );
                      } catch (e) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Gagal menambah kontrak: ${e.toString()}")),
                        );
                      }
                    }
                  },
                  child: Text(
                    "Tambah",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> deleteContract(String line, String contractName) async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            "Hapus Kontrak",
            style: TextStyle(
              fontSize: 18,
              color: Colors.blue.shade800,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.blue.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.blue.shade300, width: 1),
          ),
          content: Text(
            "Apakah Anda yakin ingin menghapus kontrak '$contractName' dari tanggal ${DateFormat('yyyy-MM-dd').format(selectedDate)}?",
            style: TextStyle(
              fontSize: 16,
              color: Colors.blue.shade900,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                "Batal",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blue.shade800,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  String formattedDate = DateFormat("yyyy-MM-dd").format(selectedDate);

                  // Hapus dari kedua mode (Kumitate dan Part)
                  DocumentReference kumitateDocRef = _getDocRef(line, formattedDate, 'Kumitate');
                  DocumentReference partDocRef = _getDocRef(line, formattedDate, 'Part');

                  List<String> updatedContracts = List<String>.from(_contracts[line]!);
                  updatedContracts.remove(contractName);

                  Map<String, dynamic> updateData = {
                    'Kontrak': updatedContracts,
                    contractName: FieldValue.delete()
                  };

                  await kumitateDocRef.set(updateData, SetOptions(merge: true));
                  await partDocRef.set(updateData, SetOptions(merge: true));

                  setState(() {
                    _contracts[line]!.remove(contractName);
                    _contractProcessData[line]!.remove(contractName);
                    if (_selectedContracts[line] == contractName) {
                      _selectedContracts[line] = _contracts[line]!.isNotEmpty ? _contracts[line]!.first : "";
                    }
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Kontrak $contractName berhasil dihapus dari Line")),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Gagal menghapus kontrak: ${e.toString()}")),
                  );
                }
              },
              child: Text(
                "Hapus",
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
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
        for (var line in lines) {
          _contracts[line] = [];
          _selectedContracts[line] = "";
          _contractProcessData[line] = {};
        }
      });
      await fetchProcessLines();
    }
  }

  // Fungsi untuk mengubah urutan kontrak (drag and drop)
  void reorderContracts(String line, int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      
      String contract = _contracts[line]!.removeAt(oldIndex);
      _contracts[line]!.insert(newIndex, contract);
    });
  }

  @override
  Widget build(BuildContext context) {
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
          IconButton(
            icon: Icon(Icons.add, color: Colors.white, size: 26),
            onPressed: addContractToMaster,
            tooltip: 'Tambah Kontrak ke Master List',
            padding: EdgeInsets.all(10),
            constraints: BoxConstraints(minWidth: 44, minHeight: 44),
          ),
          Container(
            constraints: BoxConstraints(maxWidth: 130),
            child: TextButton(
              onPressed: () => selectDate(context),
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today, size: 20, color: Colors.white),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      DateFormat('yyyy-MM-dd').format(selectedDate),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh, size: 26, color: Colors.white),
            onPressed: fetchProcessLines,
            padding: EdgeInsets.all(10),
            constraints: BoxConstraints(minWidth: 44, minHeight: 44),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : GestureDetector(
              onHorizontalDragUpdate: (details) {
                _scrollController.jumpTo(_scrollController.offset - details.primaryDelta!);
              },
              child: Container(
                height: MediaQuery.of(context).size.height,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  child: Container(
                    padding: EdgeInsets.all(8),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: (350 * lines.length) + (12 * (lines.length - 1)).toDouble(),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: lines.map((line) => _buildLineCard(line)).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildLineCard(String line) {
    String selectedContract = _selectedContracts[line] ?? "";
    List<Map<String, dynamic>> sortedProcesses = _getSortedProcesses(line, selectedContract);

    return Container(
      width: 350,
      height: MediaQuery.of(context).size.height - 
              kToolbarHeight -
              MediaQuery.of(context).padding.top -
              16,
      margin: EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade500,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lineTitles[line]!,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.add, color: Colors.white, size: 20),
                      onPressed: () => addContractToLine(line),
                      tooltip: 'Tambah Kontrak ke Line',
                    ),
                    IconButton(
                      icon: Icon(Icons.save, color: Colors.white, size: 20),
                      onPressed: () => saveChangesPerLine(line),
                      tooltip: 'Simpan Perubahan',
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Kontrak dengan drag and drop
          Container(
            height: 70,
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: _contracts[line]!.isEmpty
                ? Center(
                    child: Text(
                      "Tidak ada kontrak",
                      style: TextStyle(
                        fontStyle: FontStyle.italic, 
                        fontSize: 14,
                      ),
                    ),
                  )
                : Scrollbar(
                    controller: _contractsScrollControllers[line],
                    thumbVisibility: true,
                    trackVisibility: true,
                    child: SingleChildScrollView(
                      controller: _contractsScrollControllers[line],
                      scrollDirection: Axis.horizontal,
                      child: ReorderableListView(
                        scrollDirection: Axis.horizontal,
                        physics: NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        onReorder: (oldIndex, newIndex) {
                          reorderContracts(line, oldIndex, newIndex);
                        },
                        children: _contracts[line]!.asMap().entries.map((entry) {
                            int index = entry.key;
                            String contract = entry.value;
                            bool isSelected = contract == selectedContract;
                            
                            return Container(
                              key: ValueKey(contract),
                              margin: EdgeInsets.only(right: 6),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedContracts[line] = contract;
                                      });
                                    },
                                    child: Container(
                                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isSelected ? Colors.blue.shade700 : Colors.grey.shade200,
                                        border: Border.all(
                                          color: isSelected ? Colors.blue.shade800 : Colors.grey.shade400,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            contract,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: isSelected ? Colors.white : Colors.black,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            "Urutan: ${index + 1}",
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: isSelected ? Colors.white70 : Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade600),
                                    onPressed: () => deleteContract(line, contract),
                                    padding: EdgeInsets.only(left: 4),
                                    constraints: BoxConstraints(),
                                    tooltip: 'Hapus Kontrak',
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                      ),
                    ),
                  ),
          ),
          
          Container(
            height: 1,
            color: Colors.grey.shade300,
            margin: EdgeInsets.symmetric(horizontal: 8),
          ),
          
          Expanded(
            child: Container(
              padding: EdgeInsets.all(8),
              child: _buildKumitateContent(line, selectedContract, sortedProcesses),
            ),
          ),
        ],
      ),
    );
  }

  // Widget untuk konten Kumitate (hanya menampilkan sequence, tidak bisa edit)
  Widget _buildKumitateContent(String line, String selectedContract, List<Map<String, dynamic>> sortedProcesses) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Processes untuk:",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.blue.shade800,
          ),
        ),
        Text(
          selectedContract.isNotEmpty ? selectedContract : "Pilih kontrak",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.blue.shade900,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: 8),
        
        Expanded(
          child: selectedContract.isEmpty
              ? Center(
                  child: Text(
                    _contracts[line]!.isNotEmpty
                        ? "Pilih kontrak di atas"
                        : "Klik + untuk tambah kontrak",
                    style: TextStyle(
                      fontStyle: FontStyle.italic, 
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              : sortedProcesses.isEmpty
                  ? Center(
                      child: Text(
                        "Tidak ada processes",
                        style: TextStyle(
                          fontStyle: FontStyle.italic, 
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: sortedProcesses.length,
                      itemBuilder: (context, index) {
                        Map<String, dynamic> process = sortedProcesses[index];
                        int sequence = process['sequence'] ?? 0;
                        String processName = process['name'];
                        
                        return Container(
                          margin: EdgeInsets.only(bottom: 6),
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: sequence > 0 ? Colors.green.shade50 : Colors.grey.shade100,
                            border: Border.all(
                              color: sequence > 0 ? Colors.green.shade200 : Colors.grey.shade300,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: sequence > 0 ? Colors.blue.shade500 : Colors.grey.shade400,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    sequence > 0 ? sequence.toString() : "0",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),
                              
                              Expanded(
                                child: Text(
                                  _formatProcessName(processName),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: sequence > 0 ? Colors.black87 : Colors.grey.shade600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              
                              // Kotak putih untuk membungkus angka sequence
                              Container(
                                width: 50,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Colors.grey.shade400,
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 2,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    sequence.toString(),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.black,
                                      //fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}