import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:flutter_animate/flutter_animate.dart';

class LineCPage extends StatefulWidget {
  final DateTime date;
  const LineCPage({Key? key, required this.date}) : super(key: key);

  @override
  _LineCPageState createState() => _LineCPageState();
}

class _LineCPageState extends State<LineCPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  int? _plan;
  int? _actual;
  double _currentTarget = 0.0;
  int _displayedTarget = 0;
  bool _isLoading = true;
  late Timer _timer;
  int _lastStableTarget = 0;
  StreamSubscription<DocumentSnapshot>? _planSubscription;
  StreamSubscription<DocumentSnapshot>? _kumitateSubscription;

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
    _kumitateSubscription?.cancel();
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
            _plan = data?['target_C'] as int? ?? 0;
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

    _kumitateSubscription = _firestore.collection('counter_sistem')
      .doc(dateStr)
      .collection('C')
      .doc('Kumitate')
      .snapshots()
      .listen((DocumentSnapshot snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data() as Map<String, dynamic>?;
          if (data != null) {
            int maxSequence = 0;
            int lastProcessTotal = 0;
            
            data.forEach((key, value) {
              if (value is Map && value.containsKey('sequence')) {
                int sequence = value['sequence'] as int;
                if (sequence > maxSequence) {
                  maxSequence = sequence;
                  int total = 0;
                  value.forEach((timeKey, timeValue) {
                    if (timeValue is Map && timeKey != 'sequence') {
                      timeValue.forEach((lineKey, lineValue) {
                        total += (lineValue as int? ?? 0);
                      });
                    }
                  });
                  lastProcessTotal = total;
                }
              }
            });
            
            setState(() {
              _actual = lastProcessTotal;
            });
          }
        } else {
          setState(() {
            _actual = 0;
          });
        }
      }, onError: (error) {
        debugPrint('Error listening to kumitate stream: $error');
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
    final fontSize = screenWidth < 600 ? 60.0 : 
                    screenWidth < 900 ? 100.0 : 
                    175.0;
    final horizontalPadding = screenWidth < 600 ? 16.0 : 
                            screenWidth < 900 ? 50.0 : 
                            150.0;

    return Scaffold(
      backgroundColor: Colors.blue.shade100,
      appBar: AppBar(
        title: Text(
          'Line C Production - ${DateFormat('yyyy-MM-dd').format(widget.date)}',
          style: TextStyle(
            fontSize: screenWidth < 600 ? 16 : 20,
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
              _kumitateSubscription?.cancel();
              _setupStreams();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_plan == null || _actual == null)
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Failed to load data', 
                          style: TextStyle(fontSize: screenWidth < 600 ? 18 : 24)),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () {
                          _planSubscription?.cancel();
                          _kumitateSubscription?.cancel();
                          _setupStreams();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    elevation: 8,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 5,   
                        horizontal: horizontalPadding,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildMetricRow(
                            label: 'PLAN',
                            value: _plan?.toString() ?? '-',
                            fontSize: fontSize,
                          ),
                          const SizedBox(height: 0),
                          _buildMetricRow(
                            label: 'TARGET',
                            value: _displayedTarget.toString(),
                            fontSize: fontSize,
                          ).animate().fadeIn(duration: 300.ms),
                          const SizedBox(height: 0),
                          _buildMetricRow(
                            label: 'ACTUAL',
                            value: _actual?.toString() ?? '-',
                            fontSize: fontSize,
                          ),
                        ],
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
    return Container(
      padding: EdgeInsets.zero,
      margin: EdgeInsets.zero,
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
              height: 1.1,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: Colors.red,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}