import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'line_a_page.dart';
import 'line_b_page.dart';
import 'line_c_page.dart';
import 'line_d_page.dart';
import 'line_e_page.dart';

class TargetPage extends StatefulWidget {
  @override
  _TargetPageState createState() => _TargetPageState();
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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _initializeData();
  }

  Future<void> _initializeData() async {
    setState(() => _isLoading = true);
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
        }
      });
    } catch (e) {
      print('Error loading targets: $e');
      _clearInputs();
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
          'last_updated': FieldValue.serverTimestamp(), 
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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menyimpan target: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _navigateToLinePage(String line) {
    switch (line) {
      case 'A':
        Navigator.push(context, MaterialPageRoute(builder: (context) => LineAPage(date: _selectedDate)));
        break;
      case 'B':
        Navigator.push(context, MaterialPageRoute(builder: (context) => LineBPage(date: _selectedDate)));
        break;
      case 'C':
        Navigator.push(context, MaterialPageRoute(builder: (context) => LineCPage(date: _selectedDate)));
        break;
      case 'D':
        Navigator.push(context, MaterialPageRoute(builder: (context) => LineDPage(date: _selectedDate)));
        break;
      case 'E':
        Navigator.push(context, MaterialPageRoute(builder: (context) => LineEPage(date: _selectedDate)));
        break;
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
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
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text('Simpan'),
                        ),
                ),
                SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => _navigateToLinePage(line),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade600,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text('Actual'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}