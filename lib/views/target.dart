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
  
  // Maps untuk menyimpan controllers dan submitted status untuk setiap style
  final Map<String, List<TextEditingController>> _qtyStyleControllers = {};
  final Map<String, List<TextEditingController>> _timeStyleControllers = {};
  final Map<String, List<bool>> _isSubmittedStyle = {};
  final Map<String, bool> _lineHasData = {
    'A': false,
    'B': false,
    'C': false,
    'D': false,
    'E': false,
  };
  
  // Overtime state
  final Map<String, bool> _showOvertime = {
    'A': false,
    'B': false,
    'C': false,
    'D': false,
    'E': false,
  };
  final Map<String, Map<String, String>> _selectedOvertime = {
    'A': {'start': '', 'end': ''},
    'B': {'start': '', 'end': ''},
    'C': {'start': '', 'end': ''},
    'D': {'start': '', 'end': ''},
    'E': {'start': '', 'end': ''},
  };
  final Map<String, TextEditingController> _overtimeTimeControllers = {};
  final Map<String, TextEditingController> _overtimeQtyControllers = {};
  // Track whether overtime has been saved once for each line (then lock editing)
  final Map<String, bool> _overtimeSaved = {
    'A': false,
    'B': false,
    'C': false,
    'D': false,
    'E': false,
  };
  
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    // Initialize overtime controllers
    for (var line in ['A', 'B', 'C', 'D', 'E']) {
      _overtimeTimeControllers[line] = TextEditingController();
      _overtimeQtyControllers[line] = TextEditingController();
      _overtimeSaved[line] = false;
    }
    _initializeData();
  }

  // Inisialisasi controllers untuk setiap line dengan 1 style default
  void _initializeStyleControllers() {
    for (var line in ['A', 'B', 'C', 'D', 'E']) {
      _qtyStyleControllers[line] = [TextEditingController()];
      _timeStyleControllers[line] = [TextEditingController()];
      _isSubmittedStyle[line] = [false];
    }
  }

  Future<void> _initializeData() async {
    setState(() => _isLoading = true);
    _initializeStyleControllers();
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
          final mapField = 'target_map_$line';
          if (data != null && data.containsKey(mapField) && data[mapField] is Map) {
            Map<String, dynamic> m = Map<String, dynamic>.from(data[mapField]);
            
            // Set line memiliki data
            _lineHasData[line] = true;
            
            // Clear existing controllers
            _qtyStyleControllers[line]?.forEach((controller) => controller.dispose());
            _timeStyleControllers[line]?.forEach((controller) => controller.dispose());
            
            _qtyStyleControllers[line] = [];
            _timeStyleControllers[line] = [];
            _isSubmittedStyle[line] = [];
            
            // Create controllers for each style
            int styleIndex = 0;
            m.forEach((styleKey, vals) {
              if (vals is Map && !styleKey.startsWith('overtime')) {
                _qtyStyleControllers[line]!.add(TextEditingController());
                _timeStyleControllers[line]!.add(TextEditingController());
                _isSubmittedStyle[line]!.add(true); // Set to true karena data sudah ada
                
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

                _qtyStyleControllers[line]![styleIndex].text = q;
                _timeStyleControllers[line]![styleIndex].text = tText;
                styleIndex++;
              }
            });

            // Load overtime data if exists
            if (m.containsKey('overtime')) {
              final overtimeData = m['overtime'];
              if (overtimeData is Map) {
                _showOvertime[line] = true;
                _selectedOvertime[line]!['start'] = overtimeData['start'] ?? '16:55';
                _selectedOvertime[line]!['end'] = overtimeData['end'] ?? '';
                _overtimeTimeControllers[line]!.text = overtimeData['time_perpcs']?.toString() ?? '';
                _overtimeQtyControllers[line]!.text = overtimeData['quantity']?.toString() ?? '';
                // If overtime exists in Firestore, consider it as already saved -> lock further edits
                _overtimeSaved[line] = true;
              }
            }
          } else {
            // Jika tidak ada data tersimpan, pastikan minimal ada 1 style
            if (_qtyStyleControllers[line]!.isEmpty) {
              _qtyStyleControllers[line] = [TextEditingController()];
              _timeStyleControllers[line] = [TextEditingController()];
              _isSubmittedStyle[line] = [false];
            }
            _lineHasData[line] = false;
            _showOvertime[line] = false;
            _selectedOvertime[line] = {'start': '16:55', 'end': ''};
            _overtimeTimeControllers[line]!.clear();
            _overtimeQtyControllers[line]!.clear();
          }
        }
      });
    } catch (e) {
      print('Error loading targets: $e');
      // Pastikan setiap line memiliki minimal 1 style
      _initializeStyleControllers();
      // Reset semua lineHasData ke false
      for (var line in ['A', 'B', 'C', 'D', 'E']) {
        _lineHasData[line] = false;
        _showOvertime[line] = false;
        _selectedOvertime[line] = {'start': '16:55', 'end': ''};
        _overtimeTimeControllers[line]!.clear();
        _overtimeQtyControllers[line]!.clear();
      }
    }
  }

  // Tambah style baru untuk line tertentu
  void _addStyle(String line) {
    // Cek apakah line sudah memiliki data
    if (_lineHasData[line]!) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tidak bisa menambah style, data sudah tersimpan')),
      );
      return;
    }
    
    setState(() {
      _qtyStyleControllers[line]!.add(TextEditingController());
      _timeStyleControllers[line]!.add(TextEditingController());
      _isSubmittedStyle[line]!.add(false);
    });
  }

  // Hapus style untuk line tertentu
  void _removeStyle(String line, int index) {
    // Cek apakah line sudah memiliki data
    if (_lineHasData[line]!) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tidak bisa menghapus style, data sudah tersimpan')),
      );
      return;
    }
    
    if (_qtyStyleControllers[line]!.length > 1) {
      setState(() {
        _qtyStyleControllers[line]![index].dispose();
        _timeStyleControllers[line]![index].dispose();
        _qtyStyleControllers[line]!.removeAt(index);
        _timeStyleControllers[line]!.removeAt(index);
        _isSubmittedStyle[line]!.removeAt(index);
      });
    }
  }

  // Toggle overtime visibility
  void _toggleOvertime(String line) {
    // Allow toggling overtime even if styles are saved. Only styles should be locked.
    setState(() {
      _showOvertime[line] = !_showOvertime[line]!;
      if (!_showOvertime[line]!) {
        _selectedOvertime[line] = {'start': '16:55', 'end': ''};
        _overtimeTimeControllers[line]!.clear();
        _overtimeQtyControllers[line]!.clear();
      }
    });
  }

  // Select overtime duration
  void _selectOvertimeDuration(String line, String endTime) {
    setState(() {
      _selectedOvertime[line]!['start'] = '16:55';
      _selectedOvertime[line]!['end'] = endTime;
      _calculateOvertimeQuantity(line);
    });
  }

  // Calculate overtime quantity based on duration and time per pcs
  void _calculateOvertimeQuantity(String line) {
    if (_selectedOvertime[line]!['end']!.isEmpty || _overtimeTimeControllers[line]!.text.isEmpty) {
      return;
    }

    final timeText = _overtimeTimeControllers[line]!.text.replaceAll(',', '.');
    final timePerPcs = double.tryParse(timeText) ?? 0.0;
    
    if (timePerPcs <= 0) {
      return;
    }

    // Calculate duration in seconds based on selection
    int overtimeSeconds = 0;
    switch (_selectedOvertime[line]!['end']) {
      case '17:25':
        overtimeSeconds = 30 * 60; // 30 minutes
        break;
      case '17:55':
        overtimeSeconds = 60 * 60; // 60 minutes
        break;
      case '18:25':
        overtimeSeconds = 90 * 60; // 90 minutes
        break;
      case '18:55':
        overtimeSeconds = 120 * 60; // 120 minutes
        break;
      case '19:25':
        overtimeSeconds = 150 * 60; // 150 minutes
        break;
      case '19:55':
        overtimeSeconds = 180 * 60; // 180 minutes
        break;
    }

    final quantity = (overtimeSeconds / timePerPcs).floor();
    setState(() {
      _overtimeQtyControllers[line]!.text = quantity.toString();
    });
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
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveTargetByStyles(String line) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    Map<String, Map<String, dynamic>> detail = {};
    int total = 0;
    
    // helper: total productive seconds (07:30-11:30, break 1h, 12:30-16:30)
    int totalProductiveSeconds() {
      final morning = Duration(hours: 11, minutes: 30) - Duration(hours: 7, minutes: 30); // 4:00
      final afternoon = Duration(hours: 16, minutes: 30) - Duration(hours: 12, minutes: 30); // 4:00
      return (morning + afternoon).inSeconds; // 28800
    }

    final styles = _qtyStyleControllers[line] ?? [];
    final timeControllers = _timeStyleControllers[line] ?? [];

    // Special handling when there is only 1 or 2 styles
    if (styles.length == 1) {
      final qCtrl = styles[0];
      final tCtrl = timeControllers[0];
      final qText = qCtrl.text;
      final tText = tCtrl.text;

      final tRaw = double.tryParse(tText.replaceAll(',', '.')) ?? 0.0;
      final t = ((tRaw * 1000).round()) / 1000.0;

      int q = int.tryParse(qText) ?? 0;

      if ((q <= 0) && t > 0) {
        final maxQ = (totalProductiveSeconds() / t).floor();
        q = maxQ;
        // update controller so user sees computed value
        qCtrl.text = q.toString();
      }

      if (q <= 0 || t <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Harap masukkan waktu (>0) atau quantity untuk style 1')));
        return;
      }

      detail['style1'] = {'quantity': q, 'time_perpcs': t};
      total = q;
    } else if (styles.length == 2) {
      final q1Ctrl = styles[0];
      final t1Ctrl = timeControllers[0];
      final t2Ctrl = timeControllers[1];

      int q1 = int.tryParse(q1Ctrl.text) ?? 0;
      final t1Raw = double.tryParse(t1Ctrl.text.replaceAll(',', '.')) ?? 0.0;
      final t2Raw = double.tryParse(t2Ctrl.text.replaceAll(',', '.')) ?? 0.0;
      final t1 = ((t1Raw * 1000).round()) / 1000.0;
      final t2 = ((t2Raw * 1000).round()) / 1000.0;

      if (t1 <= 0 || t2 <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Harap masukkan waktu untuk kedua style (detik)')));
        return;
      }

      final totalSec = totalProductiveSeconds();

      // if q1 not provided, try to compute it from t1 (this will use full capacity)
      if (q1 <= 0) {
        q1 = (totalSec / t1).floor();
        q1Ctrl.text = q1.toString();
        // then style2 will get 0
        detail['style1'] = {'quantity': q1, 'time_perpcs': t1};
        detail['style2'] = {'quantity': 0, 'time_perpcs': t2};
        total = q1;
      } else {
        final consumed = (q1 * t1);
        if (consumed >= totalSec) {
          // cap q1
          final maxQ1 = (totalSec / t1).floor();
          q1 = maxQ1;
          q1Ctrl.text = q1.toString();
          detail['style1'] = {'quantity': q1, 'time_perpcs': t1};
          detail['style2'] = {'quantity': 0, 'time_perpcs': t2};
          total = q1;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Style 1 melebihi kapasitas, di-adjust menjadi $q1 unit')));
        } else {
          final remainingSec = totalSec - consumed;
          final q2 = (remainingSec / t2).floor();
          // fill detail
          detail['style1'] = {'quantity': q1, 'time_perpcs': t1};
          detail['style2'] = {'quantity': q2, 'time_perpcs': t2};
          styles[1].text = q2.toString();
          total = q1 + q2;
        }
      }
    } else {
      // default behavior for >=3 styles: require explicit quantity entries
      for (int i = 0; i < styles.length; i++) {
        final qCtrl = styles[i];
        final tCtrl = timeControllers[i];
        final qText = qCtrl.text;
        final tText = tCtrl.text;

        if (qText.trim().isEmpty && tText.trim().isEmpty) continue; // skip empty

        final q = int.tryParse(qText) ?? 0;
        final tRaw = double.tryParse(tText.replaceAll(',', '.')) ?? 0.0;
        final t = ((tRaw * 1000).round()) / 1000.0;

        if (q < 0 || t < 0) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nilai untuk style ${i+1} harus angka >= 0')));
          return;
        }

        detail['style${i+1}'] = {'quantity': q, 'time_perpcs': t};
        total += q;
      }
    }

    // Add overtime data if exists
      if (_showOvertime[line]! && _selectedOvertime[line]!['end']!.isNotEmpty) {
      final overtimeTimeText = _overtimeTimeControllers[line]!.text.replaceAll(',', '.');
      final overtimeTime = double.tryParse(overtimeTimeText) ?? 0.0;
      final overtimeQty = int.tryParse(_overtimeQtyControllers[line]!.text) ?? 0;

      if (overtimeTime > 0 && overtimeQty > 0) {
        detail['overtime'] = {
          'quantity': overtimeQty,
          'time_perpcs': overtimeTime,
          'start': _selectedOvertime[line]!['start'],
          'end': _selectedOvertime[line]!['end'],
        };
        total += overtimeQty;
      }
    }

    if (detail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tidak ada input style untuk disimpan')));
      return;
    }

    try {
      await _firestore.collection('counter_sistem').doc(dateStr).set({
        'target_$line': total,
        'target_map_$line': detail,
        'date': dateStr,
      }, SetOptions(merge: true));

      setState(() {
        _lineHasData[line] = true;
        for (int i = 0; i < _isSubmittedStyle[line]!.length; i++) {
          _isSubmittedStyle[line]![i] = true;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Target style Line $line berhasil disimpan'), backgroundColor: Colors.green));
      await _initializeData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan target style: $e'), backgroundColor: Colors.red));
    }
  }

  // Save only overtime data for a line (allow saving even if styles are locked)
  Future<void> _saveOvertime(String line) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final overtimeEnd = _selectedOvertime[line]!['end'] ?? '';
    final timeText = _overtimeTimeControllers[line]!.text.replaceAll(',', '.');
    final overtimeTime = double.tryParse(timeText) ?? 0.0;

    if (overtimeEnd.isEmpty || overtimeTime <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Harap pilih durasi dan masukkan waktu overtime (>0)')));
      return;
    }

    final overtimeQty = int.tryParse(_overtimeQtyControllers[line]!.text) ?? 0;

    try {
      final docRef = _firestore.collection('counter_sistem').doc(dateStr);
      final doc = await docRef.get();
      Map<String, dynamic> map = {};
      final mapField = 'target_map_$line';
      final data = doc.data();
      if (data != null && data.containsKey(mapField) && data[mapField] is Map) {
        map = Map<String, dynamic>.from(data[mapField]);
      }

      map['overtime'] = {
        'quantity': overtimeQty,
        'time_perpcs': overtimeTime,
        'start': _selectedOvertime[line]!['start'],
        'end': overtimeEnd,
      };

      // Recompute total from style quantities + overtime
      int total = 0;
      map.forEach((k, v) {
        if (v is Map && k != 'overtime') {
          final q = int.tryParse(v['quantity']?.toString() ?? '') ?? 0;
          total += q;
        }
      });
      total += overtimeQty;

      await docRef.set({
        'target_map_$line': map,
        'target_$line': total,
        'date': dateStr,
      }, SetOptions(merge: true));

      setState(() {
        _lineHasData[line] = true;
        // Mark overtime as saved when user saves overtime via UI
        _overtimeSaved[line] = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Overtime Line $line berhasil disimpan'), backgroundColor: Colors.green));
      await _initializeData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan overtime: $e'), backgroundColor: Colors.red));
    }
  }

  void _navigateToLinePage(String line) {
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
      await _initializeData();
    }();
  }

  @override
  void dispose() {
    // Dispose semua controllers
    for (var line in ['A', 'B', 'C', 'D', 'E']) {
      for (var controller in _qtyStyleControllers[line] ?? []) {
        controller.dispose();
      }
      for (var controller in _timeStyleControllers[line] ?? []) {
        controller.dispose();
      }
      _overtimeTimeControllers[line]?.dispose();
      _overtimeQtyControllers[line]?.dispose();
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
    final qtyControllers = _qtyStyleControllers[line] ?? [];
    final timeControllers = _timeStyleControllers[line] ?? [];
    final submittedStatus = _isSubmittedStyle[line] ?? [];
    final hasData = _lineHasData[line]!;
    final showOvertime = _showOvertime[line]!;
    final selectedOvertime = _selectedOvertime[line]!;

    // Overtime duration options
    final overtimeOptions = [
      '17:25',
      '17:55',
      '18:25',
      '18:55',
      '19:25',
      '19:55',
    ];

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
                if (hasData) ...[
                  SizedBox(width: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock, size: 14, color: Colors.green.shade800),
                        SizedBox(width: 4),
                        Text(
                          'Terkunci',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: 16),
            
            // Style inputs section
            Column(
              children: List.generate(qtyControllers.length, (index) {
                return Container(
                  margin: EdgeInsets.only(bottom: 12),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: hasData ? Colors.grey.shade100 : Colors.white,
                    border: Border.all(
                      color: hasData ? Colors.grey.shade300 : Colors.grey.shade300,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Style ${index + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold, 
                              color: hasData ? Colors.grey.shade600 : Colors.blue.shade800,
                              fontSize: 16
                            ),
                          ),
                          if (qtyControllers.length > 1 && !hasData)
                            IconButton(
                              icon: Icon(Icons.remove_circle, color: Colors.red),
                              onPressed: () => _removeStyle(line, index),
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(),
                            ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: qtyControllers[index],
                              keyboardType: TextInputType.number,
                              enabled: !hasData, // Nonaktifkan jika sudah ada data
                              decoration: InputDecoration(
                                labelText: 'Quantity',
                                border: OutlineInputBorder(),
                                isDense: true,
                                enabled: !hasData,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: timeControllers[index],
                              keyboardType: TextInputType.numberWithOptions(decimal: true),
                              enabled: !hasData, // Nonaktifkan jika sudah ada data
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]')),
                                DecimalTextInputFormatter(decimalRange: 3),
                              ],
                              decoration: InputDecoration(
                                labelText: 'Waktu /pcs (det)',
                                border: OutlineInputBorder(),
                                isDense: true,
                                enabled: !hasData,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (submittedStatus[index] || hasData)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 16),
                              SizedBox(width: 4),
                              Text(
                                'Tersimpan',
                                style: TextStyle(color: Colors.green, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ),
            
            SizedBox(height: 8),
            
            // Add Style Button - hanya tampil jika belum ada data
            if (!hasData)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _addStyle(line),
                      icon: Icon(Icons.add, color: Colors.blue.shade700),
                      label: Text('+ Style', style: TextStyle(color: Colors.blue.shade700)),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: Colors.blue.shade700),
                      ),
                    ),
                  ),
                ],
              ),
            
            // Overtime Section
            if (showOvertime) ...[
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border.all(color: Colors.orange.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Overtime', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                        IconButton(icon: Icon(Icons.close, color: Colors.red), onPressed: () => _toggleOvertime(line), padding: EdgeInsets.zero, constraints: BoxConstraints()),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text('Pilih Durasi Overtime:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.orange.shade700)),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: overtimeOptions.map((option) {
                        return FilterChip(
                          label: Text('16:55 - $option'),
                          selected: selectedOvertime['end'] == option,
                          onSelected: (_overtimeSaved[line] ?? false) ? null : (selected) { if (selected) _selectOvertimeDuration(line, option); },
                          selectedColor: Colors.orange.shade300,
                          checkmarkColor: Colors.white,
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 12),
                    if (selectedOvertime['end']!.isNotEmpty) ...[
                      Row(
                        children: [
                          Expanded(
                child: TextField(
                  controller: _overtimeTimeControllers[line],
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  enabled: !(_overtimeSaved[line] ?? false),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]')), DecimalTextInputFormatter(decimalRange: 3)],
                              onChanged: (value) => _calculateOvertimeQuantity(line),
                              decoration: InputDecoration(labelText: 'Waktu /pcs (det)', border: OutlineInputBorder(), isDense: true),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _overtimeQtyControllers[line],
                              keyboardType: TextInputType.number,
                              enabled: false,
                              decoration: InputDecoration(labelText: 'Quantity', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.grey.shade200),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      if (!(_overtimeSaved[line] ?? false))
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _saveOvertime(line),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade700,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                child: Text('Simpan Overtime', style: TextStyle(color: Colors.white)),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
              ),
            ] else ...[
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _toggleOvertime(line),
                      icon: Icon(Icons.access_time, color: Colors.orange.shade700),
                      label: Text('Overtime', style: TextStyle(color: Colors.orange.shade700)),
                      style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 12), side: BorderSide(color: Colors.orange.shade700)),
                    ),
                  ),
                ],
              ),
            ],
            
            SizedBox(height: 16),
            
            // Save and Actual buttons
            Row(
              children: [
                Expanded(child: SizedBox()),
                // Tombol Simpan - hanya tampil jika belum ada data
                if (!hasData)
                  ElevatedButton(
                    onPressed: () => _saveTargetByStyles(line),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      minimumSize: Size(160, 44),
                      padding: EdgeInsets.symmetric(horizontal: 14.0, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Simpan Semua Style', style: TextStyle(color: Colors.white)),
                  ),
                if (!hasData) SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => _navigateToLinePage(line),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    minimumSize: Size(160, 44),
                    padding: EdgeInsets.symmetric(horizontal: 14.0, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Actual', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}