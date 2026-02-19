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
  
  // State untuk mode (Kumitate/Part)
  String _currentMode = 'Kumitate'; // Default: Kumitate

  final List<String> lines = ["A", "B", "C", "D", "E"];
  final Map<String, String> lineTitles = {
    "A": "Line A", "B": "Line B", "C": "Line C", 
    "D": "Line D", "E": "Line E", 
  };

  // Map untuk menyimpan controller dan focus node tiap input sequence
  Map<String, TextEditingController> _sequenceControllers = {};
  Map<String, FocusNode> _sequenceFocusNodes = {};

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
    
    // Dispose semua sequence controllers dan focus nodes
    for (var controller in _sequenceControllers.values) {
      controller.dispose();
    }
    for (var focusNode in _sequenceFocusNodes.values) {
      focusNode.dispose();
    }
    
    try {
      _scrollController.dispose();
    } catch (_) {}
    super.dispose();
  }

  // Fungsi untuk mendapatkan document reference berdasarkan mode
  DocumentReference _getDocRef(String line, String formattedDate) {
    return _firestore
        .collection('counter_sistem')
        .doc(formattedDate)
        .collection(line)
        .doc(_currentMode);
  }

  Future<void> fetchMasterContracts() async {
    try {
      DocumentSnapshot contractsSnapshot = 
          await _firestore.collection('basic_data').doc('contracts').get();
      
      if (contractsSnapshot.exists) {
        Map<String, dynamic> contractsData = _convertToStringDynamicMap(contractsSnapshot.data());
        setState(() {
          _allContracts = contractsData.keys.where((key) => key.isNotEmpty).toList();
          _allContracts.sort();
        });
      }
      
      await fetchProcessLines();
    } catch (e) {
      await fetchProcessLines();
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

      // Ambil process_kumitate untuk semua line
      List<String> kumitateProcesses = [];
      if (processData.containsKey('process_kumitate') && processData['process_kumitate'] is List) {
        List<dynamic> processesDynamic = processData['process_kumitate'];
        kumitateProcesses = processesDynamic.map((item) => item.toString()).toList();
      }

      for (String line in lines) {
        _baseProcesses[line] = kumitateProcesses;
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
      DocumentReference docRef = _getDocRef(line, formattedDate);

      DocumentSnapshot snapshot = await docRef.get();
      
      List<String> existingContracts = [];
      
      if (snapshot.exists) {
        Map<String, dynamic> data = _convertToStringDynamicMap(snapshot.data());
        
        // STRUKTUR BARU: Cek field 'Kontrak' yang berisi array of contracts
        if (data.containsKey('Kontrak') && data['Kontrak'] is List) {
          List<dynamic> contractsArray = data['Kontrak'];
          for (var contract in contractsArray) {
            if (contract is String && contract.isNotEmpty && !existingContracts.contains(contract)) {
              existingContracts.add(contract);
            }
          }
        } else {
          // Struktur lama: ambil dari keys
          data.forEach((key, value) {
            if (key != 'created' && key != 'updated' && key != 'contract_name' && 
                key.isNotEmpty && !existingContracts.contains(key)) {
              existingContracts.add(key);
            }
          });
        }
      }

      // Untuk mode Part, tidak perlu cek subcollection
      if (_currentMode == 'Kumitate') {
        // Juga cek kontrak dari struktur subcollection (hanya untuk Kumitate)
        try {
          CollectionReference lineCollectionRef = _firestore
              .collection('counter_sistem')
              .doc(formattedDate)
              .collection(line);

          QuerySnapshot subcollections = await lineCollectionRef.get();
          for (DocumentSnapshot doc in subcollections.docs) {
            if (doc.id == _currentMode) continue;
            
            CollectionReference contractSubcollections = doc.reference.collection(doc.id);
            QuerySnapshot contractProcesses = await contractSubcollections.get();
            if (contractProcesses.docs.isNotEmpty && !existingContracts.contains(doc.id)) {
              existingContracts.add(doc.id);
            }
          }
        } catch (e) {
          print("Error checking new structure contracts: $e");
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
      
      DocumentReference docRef = _getDocRef(line, formattedDate);

      DocumentSnapshot snapshot = await docRef.get();
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
        
        // Jika tidak ditemukan di struktur baru, cek struktur lama (hanya untuk Kumitate)
        if (!foundInNewStructure && _currentMode == 'Kumitate') {
          try {
            CollectionReference contractCollectionRef = docRef.collection(contract);
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
        } else if (!foundInNewStructure && _currentMode == 'Part') {
          // Untuk Part, gunakan base processes dengan sequence 0
          for (String processName in _baseProcesses[line]!) {
            processes.add({
              'name': processName,
              'sequence': 0,
            });
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
    
    // Jika semua sequence = 0 (belum diatur), pertahankan urutan index array asli
    bool allZero = processes.every((p) => (p['sequence'] ?? 0) == 0);
    if (allZero) return processes;

    // Tambahkan index asli sebelum sort agar item sequence=0 tetap terurut sesuai array asli
    List<Map<String, dynamic>> indexed = processes
        .asMap()
        .entries
        .map((e) => {...e.value, '_originalIndex': e.key})
        .toList();

    indexed.sort((a, b) {
      int aSeq = a['sequence'] ?? 0;
      int bSeq = b['sequence'] ?? 0;
      
      // Keduanya sequence > 0: urutkan berdasarkan sequence
      if (aSeq > 0 && bSeq > 0) return aSeq.compareTo(bSeq);
      // a sudah diisi, b belum → a naik ke atas
      if (aSeq > 0) return -1;
      // b sudah diisi, a belum → b naik ke atas
      if (bSeq > 0) return 1;
      // Keduanya 0: pertahankan urutan asli dari array _baseProcesses
      return (a['_originalIndex'] as int).compareTo(b['_originalIndex'] as int);
    });

    // Hapus field helper _originalIndex sebelum dikembalikan
    return indexed.map((p) {
      Map<String, dynamic> copy = Map<String, dynamic>.from(p);
      copy.remove('_originalIndex');
      return copy;
    }).toList();
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
      
      DocumentReference docRef = _getDocRef(line, formattedDate);

      // STRUKTUR BARU: Simpan array kontrak untuk menjaga urutan dengan field 'Kontrak'
      Map<String, dynamic> updateData = {
        'Kontrak': _contracts[line]!, // Array of contract names
      };

      // Untuk mode Kumitate, simpan proses dengan sequence
      if (_currentMode == 'Kumitate') {
        // Simpan proses untuk setiap kontrak
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
            updateData[contract] = processNamesWithSequence;
          } else {
            // Hapus field kontrak jika tidak ada proses dengan sequence > 0
            updateData[contract] = FieldValue.delete();
          }
        }

        await docRef.set(updateData, SetOptions(merge: true));

        // Simpan processes dengan mempertahankan data counter yang sudah ada
        for (String contract in _contracts[line]!) {
          CollectionReference contractCollectionRef = docRef.collection(contract);
          
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
      } else {
        // Untuk mode Part, simpan semua proses (tanpa sequence)
        for (String contract in _contracts[line]!) {
          List<String> processNames = [];
          List<String> src = (_partProcesses[line] != null && _partProcesses[line]!.isNotEmpty)
              ? _partProcesses[line]!
              : _baseProcesses[line]!;
          for (String processName in src) {
            processNames.add(processName);
          }
          updateData[contract] = processNames;
        }

        await docRef.set(updateData, SetOptions(merge: true));

        // Buat/Perbarui subcollections kontrak di dokumen Part
        try {
          for (String contract in _contracts[line]!) {
            List<String> processNames = updateData[contract] is List ? List<String>.from(updateData[contract]) : [];
            if (processNames.isEmpty) continue;

            CollectionReference contractCol = docRef.collection(contract);
            for (String pname in processNames) {
              await contractCol.doc(pname).set({'part': ''}, SetOptions(merge: true));
            }
          }
        } catch (e) {
          print('Gagal membuat subcollections untuk Part saat menyimpan: $e');
        }
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

                  try {
                    await _firestore.collection('basic_data').doc('contracts')
                        .set({contractName: contractName}, SetOptions(merge: true));

                    setState(() {
                      _allContracts.add(contractName);
                      _allContracts.sort();
                    });

                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Kontrak '$contractName' berhasil ditambahkan ke master list!")),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Gagal menambah kontrak: $e")),
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
                        setState(() {
                          if (!_contracts[line]!.contains(selectedContract!)) {
                            _contracts[line]!.add(selectedContract!);
                          }
                          
                          List<Map<String, dynamic>> newProcesses = _baseProcesses[line]!
                              .map((processName) => {'name': processName, 'sequence': 0})
                              .toList();
                          
                          if (_contractProcessData[line] == null) {
                            _contractProcessData[line] = {};
                          }
                          
                          _contractProcessData[line]![selectedContract!] = newProcesses;
                          _selectedContracts[line] = selectedContract!;
                        });

                        // Jika saat ini di mode Kumitate, juga simpan struktur Part
                        // sehingga kontrak yang ditambahkan ke Kumitate otomatis tersedia di Part
                        if (_currentMode == 'Kumitate') {
                          try {
                            String formattedDate = DateFormat("yyyy-MM-dd").format(selectedDate);
                            DocumentReference partDocRef = _firestore
                                .collection('counter_sistem')
                                .doc(formattedDate)
                                .collection(line)
                                .doc('Part');

              // Untuk Part, gunakan daftar proses khusus PART jika ada,
              // jika tidak ada gunakan baseProcesses sebagai fallback
              List<String> processNames = (_partProcesses[line] != null && _partProcesses[line]!.isNotEmpty)
                ? List<String>.from(_partProcesses[line]!)
                : List<String>.from(_baseProcesses[line]!);

                            await partDocRef.set({
                              'Kontrak': FieldValue.arrayUnion([selectedContract]),
                              selectedContract!: processNames,
                            }, SetOptions(merge: true));
                            // Buat subcollection kontrak di bawah dokumen Part dan tambahkan dokumen proses
                            try {
                              CollectionReference contractCol = partDocRef.collection(selectedContract!);
                              for (String p in processNames) {
                                await contractCol.doc(p).set({'part': ''}, SetOptions(merge: true));
                              }
                            } catch (e) {
                              print('Gagal membuat subcollection kontrak di Part: $e');
                            }
                          } catch (e) {
                            print('Gagal menyimpan kontrak ke Part: $e');
                          }
                        }

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

                  // Hapus dari dokumen sesuai mode saat ini (mis. Kumitate)
                  DocumentReference docRef = _getDocRef(line, formattedDate);

                  List<String> updatedContracts = List<String>.from(_contracts[line]!);
                  updatedContracts.remove(contractName);

                  Map<String, dynamic> updateData = {
                    'Kontrak': updatedContracts,
                    contractName: FieldValue.delete()
                  };

                  await docRef.set(updateData, SetOptions(merge: true));

                  // Selalu coba hapus juga dari Part (field dan subcollection)
                  try {
                    DocumentReference partDocRef = _firestore
                        .collection('counter_sistem')
                        .doc(formattedDate)
                        .collection(line)
                        .doc('Part');

                    // Hapus nama kontrak dari array 'Kontrak' di Part
                    await partDocRef.set({
                      'Kontrak': FieldValue.arrayRemove([contractName]),
                      contractName: FieldValue.delete()
                    }, SetOptions(merge: true));

                    // Jangan hapus subcollection kontrak di Part — hanya hapus array/field.
                  } catch (e) {
                    print('Gagal menghapus kontrak di Part: $e');
                  }

                  setState(() {
                    _contracts[line]!.remove(contractName);
                    _contractProcessData[line]!.remove(contractName);
                    if (_selectedContracts[line] == contractName) {
                      _selectedContracts[line] = _contracts[line]!.isNotEmpty ? _contracts[line]!.first : "";
                    }
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Kontrak $contractName berhasil dihapus dari Line dan Part")),
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

  // Fungsi untuk mendapatkan key unik untuk sequence controller dan focus node
  String _getSequenceKey(String line, String contractName, String processName) {
    return '${line}_${contractName}_${processName}';
  }

  // Fungsi untuk inisialisasi controller dan focus node jika belum ada
  void _initializeSequenceController(String line, String contractName, String processName, int sequence) {
    String key = _getSequenceKey(line, contractName, processName);
    
    if (!_sequenceControllers.containsKey(key)) {
      _sequenceControllers[key] = TextEditingController(text: sequence > 0 ? sequence.toString() : '');
    }
    
    if (!_sequenceFocusNodes.containsKey(key)) {
      _sequenceFocusNodes[key] = FocusNode();
      
      // Tambahkan listener untuk focus node
      _sequenceFocusNodes[key]!.addListener(() {
        if (!_sequenceFocusNodes[key]!.hasFocus) {
          // Ketika kehilangan fokus, update sequence
          _updateProcessSequenceFromController(line, contractName, processName);
        }
      });
    }
  }

  // Fungsi untuk update sequence dari controller ketika kehilangan fokus
  void _updateProcessSequenceFromController(String line, String contractName, String processName) {
    String key = _getSequenceKey(line, contractName, processName);
    String sequenceText = _sequenceControllers[key]?.text ?? '';
    int sequence = int.tryParse(sequenceText) ?? 0;
    
    _updateProcessSequence(line, contractName, processName, sequence);
  }

  // Fungsi untuk update sequence (versi baru dengan processName)
  void _updateProcessSequence(String line, String contractName, String processName, int sequence) {
    // Hanya untuk Kumitate, Part tidak bisa edit sequence
    if (_currentMode == 'Part') return;
    
    setState(() {
      if (_contractProcessData[line] != null && 
          _contractProcessData[line]![contractName] != null) {
        
        int originalIndex = _contractProcessData[line]![contractName]!
            .indexWhere((process) => process['name'] == processName);
        
        if (originalIndex >= 0) {
          _contractProcessData[line]![contractName]![originalIndex]['sequence'] = sequence;
        }
      }
    });
  }

  // Fungsi untuk handle onEditingComplete (ketika menekan Enter/Submit)
  void _onSequenceEditingComplete(String line, String contractName, String processName, int currentIndex, List<Map<String, dynamic>> sortedProcesses) {
    // Update sequence dari controller
    _updateProcessSequenceFromController(line, contractName, processName);
    
    // Pindah fokus ke proses berikutnya jika ada
    if (currentIndex + 1 < sortedProcesses.length) {
      String nextProcessName = sortedProcesses[currentIndex + 1]['name'];
      String nextKey = _getSequenceKey(line, contractName, nextProcessName);
      
      // Pastikan controller dan focus node untuk proses berikutnya sudah diinisialisasi
      int nextSequence = sortedProcesses[currentIndex + 1]['sequence'] ?? 0;
      _initializeSequenceController(line, contractName, nextProcessName, nextSequence);
      
      FocusNode? nextFocus = _sequenceFocusNodes[nextKey];
      if (nextFocus != null) {
        FocusScope.of(context).requestFocus(nextFocus);
      }
    } else {
      // Jika sudah di proses terakhir, unfocus
      FocusScope.of(context).unfocus();
    }
  }

  // Fungsi untuk handle onFieldSubmitted (ketika menekan Enter)
  void _onSequenceFieldSubmitted(String line, String contractName, String processName, int currentIndex, List<Map<String, dynamic>> sortedProcesses) {
    _onSequenceEditingComplete(line, contractName, processName, currentIndex, sortedProcesses);
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
        
        // Clear semua controllers dan focus nodes ketika tanggal berubah
        for (var controller in _sequenceControllers.values) {
          controller.dispose();
        }
        for (var focusNode in _sequenceFocusNodes.values) {
          focusNode.dispose();
        }
        _sequenceControllers.clear();
        _sequenceFocusNodes.clear();
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
              child: _currentMode == 'Part' 
                  ? _buildPartContent(line, selectedContract, sortedProcesses)
                  : _buildKumitateContent(line, selectedContract, sortedProcesses),
            ),
          ),
        ],
      ),
    );
  }

  // Widget untuk konten Part (tampilkan proses dengan warna hitam)
  Widget _buildPartContent(String line, String selectedContract, List<Map<String, dynamic>> sortedProcesses) {
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
                        
                        return Container(
                          margin: EdgeInsets.only(bottom: 6),
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            border: Border.all(color: Colors.blue.shade200),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade500,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    (index + 1).toString(),
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
                                  _formatProcessName(process['name']),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black,
                                  ),
                                  overflow: TextOverflow.ellipsis,
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

  // Widget untuk konten Kumitate (dengan edit sequence)
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
          selectedContract,
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
                        
                        // Inisialisasi controller dan focus node untuk proses ini
                        _initializeSequenceController(line, selectedContract, processName, sequence);
                        String key = _getSequenceKey(line, selectedContract, processName);
                        
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
                              
                              Container(
                                width: 60,
                                child: TextFormField(
                                  controller: _sequenceControllers[key],
                                  focusNode: _sequenceFocusNodes[key],
                                  keyboardType: TextInputType.number,
                                  textInputAction: index < sortedProcesses.length - 1 
                                      ? TextInputAction.next 
                                      : TextInputAction.done,
                                  onEditingComplete: () => _onSequenceEditingComplete(
                                    line, selectedContract, processName, index, sortedProcesses),
                                  onFieldSubmitted: (_) => _onSequenceFieldSubmitted(
                                    line, selectedContract, processName, index, sortedProcesses),
                                  decoration: InputDecoration(
                                    labelText: "Seq",
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    labelStyle: TextStyle(fontSize: 12),
                                    isDense: true,
                                  ),
                                  style: TextStyle(fontSize: 14),
                                  textAlign: TextAlign.center,
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