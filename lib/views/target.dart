import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'line_a_page.dart';
import 'line_b_page.dart';
import 'line_c_page.dart';
import 'line_d_page.dart';
import 'line_e_page.dart';

class TargetPage extends StatefulWidget {
  @override
  _TargetPageState createState() => _TargetPageState();
}

// InputFormatter to restrict decimals to fixed number of places
class DecimalTextInputFormatter extends TextInputFormatter {
  DecimalTextInputFormatter({required this.decimalRange}) : assert(decimalRange >= 0);

  final int decimalRange;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String text = newValue.text;
    if (text == '') return newValue;

    // allow comma or dot as decimal separator, normalize to dot for validation
    final normalized = text.replaceAll(',', '.');

  // only allow digits and at most one dot
  if (!RegExp(r'^\d*\.?\d*$').hasMatch(normalized)) return oldValue;

    if (normalized.contains('.')) {
      final parts = normalized.split('.');
      if (parts.length > 2) return oldValue;
      if (parts[1].length > decimalRange) return oldValue;
    }

    return newValue;
  }
}

class _TargetPageState extends State<TargetPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late DateTime _selectedDate;
  final Map<String, TextEditingController> _controllers = {
    'A': TextEditingController(),
    'B': TextEditingController(),
    'C': TextEditingController(),
    'D': TextEditingController(),
    'E': TextEditingController(),
  };
  final Map<String, bool> _isSubmitted = {
    'A': false,
    'B': false,
    'C': false,
    'D': false,
    'E': false,
  };
  // Contracts per line for the selected date
  final Map<String, List<String>> _contractsPerLine = {
    'A': [],
    'B': [],
    'C': [],
    'D': [],
    'E': [],
  };

  // Controllers per contract: quantity and waktu(per pcs)
  final Map<String, Map<String, TextEditingController>> _qtyControllers = {};
  final Map<String, Map<String, TextEditingController>> _timeControllers = {};
  final Map<String, Map<String, bool>> _isSubmittedContract = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _initializeData();
  }

  Future<void> _initializeData() async {
    setState(() => _isLoading = true);
    // fetch contracts first so controllers for each contract are created
    await _fetchContractsForDate();
    await _loadExistingTargets();
    setState(() => _isLoading = false);
  }

  Future<void> _loadExistingTargets() async {
    final docRef = _firestore
        .collection('counter_sistem')
        .doc(DateFormat('yyyy-MM-dd').format(_selectedDate));

    try {
      final doc = await docRef.get();
      final data = doc.data();
      
      setState(() {
        for (var line in ['A', 'B', 'C', 'D', 'E']) {
          final fieldName = 'target_$line';
          if (data != null && data.containsKey(fieldName)) {
            _controllers[line]!.text = data[fieldName].toString();
            _isSubmitted[line] = true;
          } else {
            _controllers[line]!.clear();
            _isSubmitted[line] = false;
          }
          // Load detailed map if exists
          final mapField = 'target_map_$line';
          if (data != null && data.containsKey(mapField) && data[mapField] is Map) {
            Map<String, dynamic> m = Map<String, dynamic>.from(data[mapField]);
            // initialize controllers for each contract
            _ensureContractControllers(line);
            // ensure controllers exist for any contract names found in saved map
            for (var contractName in m.keys) {
              _qtyControllers[line]!.putIfAbsent(contractName, () => TextEditingController());
              _timeControllers[line]!.putIfAbsent(contractName, () => TextEditingController());
              _isSubmittedContract[line]!.putIfAbsent(contractName, () => false);
            }

            m.forEach((contract, vals) {
              try {
                if (vals is Map) {
                  final q = vals['quantity']?.toString() ?? '';
                  // normalize and format time_perpcs to 3 decimals
                  String tText = '';
                  final raw = vals['time_perpcs'];
                  if (raw != null) {
                    if (raw is num) {
                      tText = raw.toDouble().toStringAsFixed(3);
                    } else {
                      final parsed = double.tryParse(raw.toString().replaceAll(',', '.'));
                      if (parsed != null) tText = parsed.toStringAsFixed(3);
                    }
                  }

                  _qtyControllers[line]?[contract]?.text = q;
                  _timeControllers[line]?[contract]?.text = tText;
                  _isSubmittedContract[line]?[contract] = true;
                }
              } catch (_) {}
            });
          }
        }
      });
    } catch (e) {
      print('Error loading targets: $e');
      _clearInputs();
    }
  }

  // Ensure internal maps exist for a line
  void _ensureContractControllers(String line) {
    _qtyControllers.putIfAbsent(line, () => {});
    _timeControllers.putIfAbsent(line, () => {});
    _isSubmittedContract.putIfAbsent(line, () => {});
  }


  Future<void> _fetchContractsForDate() async {
    final String dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    try {
      for (var line in ['A', 'B', 'C', 'D', 'E']) {
        List<String> existingContracts = [];

        // Check Kumitate doc first
        try {
          final docRef = _firestore.collection('counter_sistem').doc(dateStr).collection(line).doc('Kumitate');
          final snapshot = await docRef.get();
          if (snapshot.exists) {
            final data = snapshot.data();
            if (data != null && data.containsKey('Kontrak') && data['Kontrak'] is List) {
              for (var c in data['Kontrak']) {
                if (c is String && c.isNotEmpty && !existingContracts.contains(c)) existingContracts.add(c);
              }
            } else if (data != null) {
              // fallback: keys
              Map<String, dynamic> dataMap = Map<String, dynamic>.from(data);
              dataMap.forEach((k, v) {
                if (k != 'created' && k != 'updated' && k != 'contract_name' && k.isNotEmpty && !existingContracts.contains(k)) existingContracts.add(k);
              });
            }
          }
        } catch (e) {
          print('Error reading Kumitate doc for $line: $e');
        }

        // Also check other docs under line (subcollections) to detect contracts
        try {
          final lineCol = _firestore.collection('counter_sistem').doc(dateStr).collection(line);
          final q = await lineCol.get();
          for (var doc in q.docs) {
            if (doc.id == 'Kumitate' || doc.id == 'Part') continue;
            // If subcollection named same as doc.id has docs, treat as contract
            try {
              final sub = await doc.reference.collection(doc.id).limit(1).get();
              if (sub.docs.isNotEmpty && !existingContracts.contains(doc.id)) existingContracts.add(doc.id);
            } catch (_) {}
          }
        } catch (e) {
          print('Error checking subcollections for $line: $e');
        }

        setState(() {
          _contractsPerLine[line] = existingContracts;
        });

        // Ensure controllers exist for found contracts
        _ensureContractControllers(line);
        for (var c in existingContracts) {
          _qtyControllers[line]!.putIfAbsent(c, () => TextEditingController());
          _timeControllers[line]!.putIfAbsent(c, () => TextEditingController());
          _isSubmittedContract[line]!.putIfAbsent(c, () => false);
        }
      }
    } catch (e) {
      print('Error fetching contracts for date $dateStr: $e');
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _isLoading = true;
      });
      await _loadExistingTargets();
  await _fetchContractsForDate();
      setState(() => _isLoading = false);
    }
  }

  void _clearInputs() {
    for (var line in ['A', 'B', 'C', 'D', 'E']) {
      _controllers[line]!.clear();
      _isSubmitted[line] = false;
    }
  }

  Future<void> _saveTarget(String line) async {
    // If there are contracts for this line, save per-contract targets instead
    if ((_contractsPerLine[line] ?? []).isNotEmpty) {
      return _saveTargetByContracts(line);
    }

    if (_controllers[line]!.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Harap masukkan target untuk Line $line')),
      );
      return;
    }

    final targetValue = int.tryParse(_controllers[line]!.text);
    if (targetValue == null || targetValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Target harus angka lebih besar dari 0')),
      );
      return;
    }

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    try {
      await _firestore.collection('counter_sistem').doc(dateStr).set(
        {
          'target_$line': targetValue,
          'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        },
        SetOptions(merge: true),
      );

      setState(() => _isSubmitted[line] = true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Target Line $line berhasil disimpan'),
          backgroundColor: Colors.green,
        ),
      );
      // reload local data to ensure saved values are reflected immediately
      await _initializeData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menyimpan target: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveTargetByContracts(String line) async {
    // validate and build map
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    _ensureContractControllers(line);
    Map<String, Map<String, dynamic>> detail = {};
    int total = 0;
    // helper: total productive seconds (07:30-11:30, break 1h, 12:30-16:30)
    int totalProductiveSeconds() {
      final morning = Duration(hours: 11, minutes: 30) - Duration(hours: 7, minutes: 30); // 4:00
      final afternoon = Duration(hours: 16, minutes: 30) - Duration(hours: 12, minutes: 30); // 4:00
      return (morning + afternoon).inSeconds; // 28800
    }

    final contracts = _contractsPerLine[line] ?? [];

    // Special handling when there is only 1 or 2 contracts
    if (contracts.length == 1) {
      final contract = contracts.first;
      final qCtrl = _qtyControllers[line]?[contract];
      final tCtrl = _timeControllers[line]?[contract];
      final qText = qCtrl?.text ?? '';
      final tText = tCtrl?.text ?? '';

      final tRaw = double.tryParse(tText.replaceAll(',', '.')) ?? 0.0;
      final t = ((tRaw * 1000).round()) / 1000.0;

      int q = int.tryParse(qText) ?? 0;

      if ((q <= 0) && t > 0) {
        final maxQ = (totalProductiveSeconds() / t).floor();
        q = maxQ;
        // update controller so user sees computed value
        _qtyControllers[line]?[contract]?.text = q.toString();
      }

      if (q <= 0 || t <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Harap masukkan waktu (>0) atau quantity untuk kontrak $contract')));
        return;
      }

      detail[contract] = {'quantity': q, 'time_perpcs': t};
      total = q;
    } else if (contracts.length == 2) {
      final c1 = contracts[0];
      final c2 = contracts[1];

      final q1Ctrl = _qtyControllers[line]?[c1];
      final t1Ctrl = _timeControllers[line]?[c1];
      final t2Ctrl = _timeControllers[line]?[c2];

      int q1 = int.tryParse(q1Ctrl?.text ?? '') ?? 0;
      final t1Raw = double.tryParse((t1Ctrl?.text ?? '').replaceAll(',', '.')) ?? 0.0;
      final t2Raw = double.tryParse((t2Ctrl?.text ?? '').replaceAll(',', '.')) ?? 0.0;
      final t1 = ((t1Raw * 1000).round()) / 1000.0;
      final t2 = ((t2Raw * 1000).round()) / 1000.0;

      if (t1 <= 0 || t2 <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Harap masukkan waktu untuk kedua kontrak (detik)')));
        return;
      }

      final totalSec = totalProductiveSeconds();

      // if q1 not provided, try to compute it from t1 (this will use full capacity)
      if (q1 <= 0) {
        q1 = (totalSec / t1).floor();
        _qtyControllers[line]?[c1]?.text = q1.toString();
        // then c2 will get 0
        detail[c1] = {'quantity': q1, 'time_perpcs': t1};
        detail[c2] = {'quantity': 0, 'time_perpcs': t2};
        total = q1;
      } else {
        final consumed = (q1 * t1);
        if (consumed >= totalSec) {
          // cap q1
          final maxQ1 = (totalSec / t1).floor();
          q1 = maxQ1;
          _qtyControllers[line]?[c1]?.text = q1.toString();
          detail[c1] = {'quantity': q1, 'time_perpcs': t1};
          detail[c2] = {'quantity': 0, 'time_perpcs': t2};
          total = q1;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kontrak $c1 melebihi kapasitas, di-adjust menjadi $q1 unit')));
        } else {
          final remainingSec = totalSec - consumed;
          final q2 = (remainingSec / t2).floor();
          // fill detail
          detail[c1] = {'quantity': q1, 'time_perpcs': t1};
          detail[c2] = {'quantity': q2, 'time_perpcs': t2};
          _qtyControllers[line]?[c2]?.text = q2.toString();
          total = q1 + q2;
        }
      }
    } else {
      // default behavior for >=3 contracts: require explicit quantity entries (existing logic)
      for (var contract in contracts) {
        final qCtrl = _qtyControllers[line]?[contract];
        final tCtrl = _timeControllers[line]?[contract];
        final qText = qCtrl?.text ?? '';
        final tText = tCtrl?.text ?? '';

        if (qText.trim().isEmpty && tText.trim().isEmpty) continue; // skip empty

        final q = int.tryParse(qText) ?? 0;
        final tRaw = double.tryParse(tText.replaceAll(',', '.')) ?? 0.0;
        final t = ((tRaw * 1000).round()) / 1000.0;

        if (q < 0 || t < 0) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nilai untuk $contract harus angka >= 0')));
          return;
        }

        detail[contract] = {'quantity': q, 'time_perpcs': t};
        total += q;
      }
    }

    if (detail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tidak ada input kontrak untuk disimpan')));
      return;
    }

    try {
      await _firestore.collection('counter_sistem').doc(dateStr).set({
        'target_$line': total,
        'target_map_$line': detail,
        'date': dateStr,
      }, SetOptions(merge: true));

      setState(() {
        _isSubmitted[line] = true;
        for (var c in detail.keys) {
          _isSubmittedContract[line]?[c] = true;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Target kontrak Line $line berhasil disimpan'), backgroundColor: Colors.green));
      // reload to pick up saved map and ensure UI shows persisted data
      await _initializeData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan target kontrak: $e'), backgroundColor: Colors.red));
    }
  }

  void _navigateToLinePage(String line) {
    // Navigate and refresh when returning so Target data stays up-to-date
    () async {
      switch (line) {
        case 'A':
          await Navigator.push(context, MaterialPageRoute(builder: (context) => LineAPage(date: _selectedDate)));
          break;
        case 'B':
          await Navigator.push(context, MaterialPageRoute(builder: (context) => LineBPage(date: _selectedDate)));
          break;
        case 'C':
          await Navigator.push(context, MaterialPageRoute(builder: (context) => LineCPage(date: _selectedDate)));
          break;
        case 'D':
          await Navigator.push(context, MaterialPageRoute(builder: (context) => LineDPage(date: _selectedDate)));
          break;
        case 'E':
          await Navigator.push(context, MaterialPageRoute(builder: (context) => LineEPage(date: _selectedDate)));
          break;
      }
      // when returning, refresh data
      await _initializeData();
    }();
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    // dispose contract controllers
    for (var map in _qtyControllers.values) {
      for (var c in map.values) {
        c.dispose();
      }
    }
    for (var map in _timeControllers.values) {
      for (var c in map.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade100,
      appBar: AppBar(
        title: Text(
          'Set Target Produksi',
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
            icon: Icon(Icons.refresh, size: 26, color: Colors.white),
            tooltip: "Refresh Data",
            onPressed: () => _initializeData(),
            splashRadius: 24,
          ),
          SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Date Picker Section
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    margin: EdgeInsets.all(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Tanggal:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                          TextButton(
                            onPressed: () => _selectDate(context),
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(color: Colors.blue.shade500),
                              ),
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today, size: 18, color: Colors.blue.shade700),
                                SizedBox(width: 4),
                                Text(
                                  DateFormat('yyyy-MM-dd').format(_selectedDate),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 8),

                  // Target Input Section
                  Expanded(
                    child: ListView(
                      children: ['A', 'B', 'C', 'D', 'E'].map((line) {
                        return _buildLineTargetCard(line);
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildLineTargetCard(String line) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.factory,
                    size: 24,
                    color: Colors.blue.shade800,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'LINE $line',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            // If there are contracts for this line, show per-contract inputs
            if ((_contractsPerLine[line] ?? []).isNotEmpty) ...[
              Column(
                children: _contractsPerLine[line]!.map((contract) {
                  _ensureContractControllers(line);
                  _qtyControllers[line]!.putIfAbsent(contract, () => TextEditingController());
                  _timeControllers[line]!.putIfAbsent(contract, () => TextEditingController());
                  _isSubmittedContract[line]!.putIfAbsent(contract, () => false);

                  return Container(
                    margin: EdgeInsets.only(bottom: 8),
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(contract, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                              SizedBox(height: 6),
                              Row(
                                children: [
                                  // make Quantity and Waktu fields equal width
                                  Expanded(
                                    child: TextField(
                                      controller: _qtyControllers[line]![contract],
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'Quantity',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _timeControllers[line]![contract],
                                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]')),
                                        DecimalTextInputFormatter(decimalRange: 3),
                                      ],
                                      decoration: InputDecoration(
                                        labelText: 'Waktu /pcs (det)',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 12),
                        // per-contract Save and Actual buttons removed — use the global actions below
                        SizedBox.shrink(),
                      ],
                    ),
                  );
                }).toList(),
              ),
              SizedBox(height: 8),
              // Save all contracts button
              Row(
                children: [
                  Expanded(child: SizedBox()),
                  ElevatedButton(
                    onPressed: () => _saveTargetByContracts(line),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      minimumSize: Size(160, 44),
                      padding: EdgeInsets.symmetric(horizontal: 14.0, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Simpan Semua Kontrak', style: TextStyle(color: Colors.white)),
                  ),
                  SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => _navigateToLinePage(line),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.yellow,
                      foregroundColor: Colors.black,
                      minimumSize: Size(160, 44),
                      padding: EdgeInsets.symmetric(horizontal: 14.0, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Actual', style: TextStyle(color: Colors.black)),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _controllers[line],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Target Produksi',
                        labelStyle: TextStyle(color: Colors.blue.shade800),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue.shade500),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue.shade700),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        suffixText: 'unit',
                        enabled: !_isSubmitted[line]!,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _isSubmitted[line]!
                        ? ElevatedButton(
                            onPressed: null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade100,
                              foregroundColor: Colors.green.shade800,
                              padding: EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle, size: 20),
                                SizedBox(width: 6),
                                Text('Tersimpan'),
                              ],
                            ),
                          )
                        : ElevatedButton(
                            onPressed: () => _saveTarget(line),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              minimumSize: Size(160, 44),
                              padding: EdgeInsets.symmetric(horizontal: 14.0, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text('Simpan', style: TextStyle(color: Colors.white)),
                          ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => _navigateToLinePage(line),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.yellow,
                        foregroundColor: Colors.black,
                        minimumSize: Size(160, 44),
                        padding: EdgeInsets.symmetric(horizontal: 14.0, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text('Actual', style: TextStyle(color: Colors.black)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}