import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:flutter_animate/flutter_animate.dart';

class LineAPage extends StatefulWidget {
  final DateTime date;
  const LineAPage({Key? key, required this.date}) : super(key: key);

  @override
  _LineAPageState createState() => _LineAPageState();
}

class _LineAPageState extends State<LineAPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  int? _plan;
  int _actual = 0;
  double _currentTarget = 0.0;
  int _displayedTarget = 0;
  bool _isLoading = true;
  late Timer _timer;
  int _lastStableTarget = 0;
  StreamSubscription<DocumentSnapshot>? _planSubscription;
  StreamSubscription<QuerySnapshot>? _processSubscription;

  // Work hours configuration
  final _startWorkTime = TimeOfDay(hour: 7, minute: 30);
  final _endWorkTime = TimeOfDay(hour: 16, minute: 30);
  final _breakStart = TimeOfDay(hour: 11, minute: 30);
  final _breakEnd = TimeOfDay(hour: 12, minute: 30);

  @override
  void initState() {
    super.initState();
    _setupStreams();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isLoading) {
        _calculateCurrentTarget();
        _updateDisplayValues();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _planSubscription?.cancel();
    _processSubscription?.cancel();
    super.dispose();
  }

  void _setupStreams() {
    final dateStr = DateFormat('yyyy-MM-dd').format(widget.date);
    
    _planSubscription = _firestore.collection('counter_sistem')
      .doc(dateStr)
      .snapshots()
      .listen((DocumentSnapshot snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data() as Map<String, dynamic>?;
          setState(() {
            _plan = data?['target_A'] as int? ?? 0;
            _calculateCurrentTarget();
          });
        } else {
          setState(() {
            _plan = 0;
          });
        }
      }, onError: (error) {
        debugPrint('Error listening to plan stream: $error');
        setState(() {
          _plan = 0;
        });
      });

    _processSubscription = _firestore.collection('counter_sistem')
      .doc(dateStr)
      .collection('A')
      .doc('Kumitate')
      .collection('Process')
      .orderBy('sequence', descending: true)
      .limit(1)
      .snapshots()
      .listen((QuerySnapshot snapshot) {
        if (snapshot.docs.isNotEmpty) {
          final processData = snapshot.docs.first.data() as Map<String, dynamic>;
          int totalCount = 0;
          
          // Sum up all line counts from the process data
          processData.forEach((key, value) {
            if (key != 'sequence' && 
                key != 'belumKensa' && 
                key != 'stock_20min' && 
                key != 'stock_pagi' && 
                key != 'part' && 
                value is Map<String, dynamic>) {
              value.forEach((lineKey, lineValue) {
                totalCount += (lineValue as int? ?? 0);
              });
            }
          });
          
          setState(() {
            _actual = totalCount;
          });
        } else {
          setState(() {
            _actual = 0;
          });
        }
      }, onError: (error) {
        debugPrint('Error listening to process stream: $error');
        setState(() {
          _actual = 0;
        });
      });

    setState(() => _isLoading = false);
  }

  void _calculateCurrentTarget() {
    if (_plan == null) {
      _currentTarget = 0.0;
      return;
    }

    final now = DateTime.now();
    final startOfWork = DateTime(
      now.year, 
      now.month, 
      now.day, 
      _startWorkTime.hour, 
      _startWorkTime.minute
    );
    final endOfWork = DateTime(
      now.year, 
      now.month, 
      now.day, 
      _endWorkTime.hour, 
      _endWorkTime.minute
    );
    
    if (now.isBefore(startOfWork)) {
      _currentTarget = 0.0;
      return;
    }
    
    if (now.isAfter(endOfWork)) {
      _currentTarget = _plan!.toDouble();
      return;
    }

    final breakStart = DateTime(
      now.year, 
      now.month, 
      now.day, 
      _breakStart.hour, 
      _breakStart.minute
    );
    final breakEnd = DateTime(
      now.year, 
      now.month, 
      now.day, 
      _breakEnd.hour, 
      _breakEnd.minute
    );
    
    double workingSeconds;
    
    if (now.isBefore(breakStart)) {
      workingSeconds = now.difference(startOfWork).inSeconds.toDouble();
    } else if (now.isBefore(breakEnd)) {
      workingSeconds = breakStart.difference(startOfWork).inSeconds.toDouble();
    } else {
      workingSeconds = breakStart.difference(startOfWork).inSeconds.toDouble() +
          now.difference(breakEnd).inSeconds.toDouble();
    }
    
    _currentTarget = (_plan! * workingSeconds / 28800);
  }

  void _updateDisplayValues() {
    final currentTargetInt = _currentTarget.floor();
    
    setState(() {
      if (currentTargetInt > _lastStableTarget) {
        _lastStableTarget = currentTargetInt;
        _displayedTarget = _lastStableTarget;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    // Ukuran font sangat besar (25% dari tinggi layar)
    final fontSize = screenHeight * 0.25;
    final clampedFontSize = fontSize.clamp(60.0, 220.0);

    // Padding minimal
    final horizontalPadding = screenWidth * 0.04;
    final verticalItemPadding = screenHeight * 0.005; // Jarak sangat rapat

    return Scaffold(
      backgroundColor: Colors.blue.shade100,
      appBar: AppBar(
        title: Text(
          'Line A Production - ${DateFormat('yyyy-MM-dd').format(widget.date)}',
          style: TextStyle(
            fontSize: screenWidth < 600 ? 22 : 26,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.blue.shade700,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              _planSubscription?.cancel();
              _processSubscription?.cancel();
              _setupStreams();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_plan == null)
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Failed to load data', 
                          style: TextStyle(fontSize: screenWidth < 600 ? 24 : 28)),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () {
                          _planSubscription?.cancel();
                          _processSubscription?.cancel();
                          _setupStreams();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: screenWidth * 0.01,
                    vertical: screenHeight * 0.005,
                  ),
                  child: SizedBox(
                    height: screenHeight * 0.88, // Hampir memenuhi layar
                    child: Card(
                      elevation: 12,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                          vertical: screenHeight * 0.01,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildMetricRow(
                              label: 'PLAN',
                              value: _plan?.toString() ?? '-',
                              fontSize: clampedFontSize,
                            ),
                            SizedBox(height: verticalItemPadding),
                            _buildMetricRow(
                              label: 'TARGET',
                              value: _displayedTarget.toString(),
                              fontSize: clampedFontSize,
                            ).animate().fadeIn(duration: 300.ms),
                            SizedBox(height: verticalItemPadding),
                            _buildMetricRow(
                              label: 'ACTUAL',
                              value: _actual.toString(),
                              fontSize: clampedFontSize,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildMetricRow({
    required String label,
    required String value,
    required double fontSize,
  }) {
    return SizedBox(
      height: fontSize * 1.05, // Tinggi baris sangat ketat
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '$label:', 
            style: TextStyle(
              fontSize: fontSize,
              color: Colors.black,
              fontWeight: FontWeight.bold,
              height: 0.9, // Line height sangat ketat
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: Colors.red,
              height: 0.9,
            ),
          ),
        ],
      ),
    );
  }
}