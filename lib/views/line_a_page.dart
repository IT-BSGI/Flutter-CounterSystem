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
  StreamSubscription<DocumentSnapshot>? _kumitateSubscription;
  List<StreamSubscription<QuerySnapshot>> _contractSubscriptions = [];
  Map<String, int> _contractData = {};
  
  // New variables for clock and countdown
  String _currentTime = '';
  String _countdown = '';
  bool _shouldBlink = false;
  final List<TimeOfDay> _hourlyIntervals = [
    TimeOfDay(hour: 8, minute: 30),
    TimeOfDay(hour: 9, minute: 30),
    TimeOfDay(hour: 10, minute: 30),
    TimeOfDay(hour: 11, minute: 30),
    TimeOfDay(hour: 12, minute: 30),
    TimeOfDay(hour: 13, minute: 30),
    TimeOfDay(hour: 14, minute: 30),
    TimeOfDay(hour: 15, minute: 30),
    TimeOfDay(hour: 16, minute: 30),
  ];

  // Work hours configuration
  final _startWorkTime = TimeOfDay(hour: 7, minute: 30);
  final _endWorkTime = TimeOfDay(hour: 16, minute: 30);
  final _breakStart = TimeOfDay(hour: 11, minute: 30);
  final _breakEnd = TimeOfDay(hour: 12, minute: 30);

  @override
  void initState() {
    super.initState();
    _setupStreams();
    _updateTime(); // Initialize time
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isLoading) {
        _calculateCurrentTarget();
        _updateDisplayValues();
        _updateTime(); // Update time every second
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _planSubscription?.cancel();
    _kumitateSubscription?.cancel();
    for (var subscription in _contractSubscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _currentTime = DateFormat('HH:mm:ss').format(now);
      _updateCountdown(now);
    });
  }

  void _updateCountdown(DateTime now) {
  final currentTime = TimeOfDay.fromDateTime(now);
  
  // Find the next interval
  TimeOfDay? nextInterval;
  for (final interval in _hourlyIntervals) {
    if (interval.hour > currentTime.hour || 
        (interval.hour == currentTime.hour && interval.minute > currentTime.minute)) {
      nextInterval = interval;
      break;
    }
  }
  
  if (nextInterval == null) {
    _countdown = 'End of Day';
    _shouldBlink = false; // Tidak kedip di end of day
    return;
  }
  
  // Calculate time until next interval
  final nextDateTime = DateTime(
    now.year, 
    now.month, 
    now.day, 
    nextInterval.hour, 
    nextInterval.minute
  );
  
  final difference = nextDateTime.difference(now);
  
  if (difference.isNegative) {
    _countdown = '00:00';
    _shouldBlink = true; // Tetap kedip jika waktu habis
  } else {
    final minutes = (difference.inMinutes.remainder(60)).toString().padLeft(2, '0');
    final seconds = (difference.inSeconds.remainder(60)).toString().padLeft(2, '0');
    _countdown = '$minutes:$seconds';
    
    // Kembali ke kondisi normal: kedip hanya jika kurang dari 1 menit
    _shouldBlink = difference.inMinutes < 1;
  }
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

    // Setup Kumitate document stream to get contract list
    final kumitateDocRef = _firestore.collection('counter_sistem')
      .doc(dateStr)
      .collection('A')
      .doc('Kumitate');

    _kumitateSubscription = kumitateDocRef.snapshots().listen((DocumentSnapshot snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>?;
        List<String> contractCollections = [];
        
        if (data != null && data['Kontrak'] is List) {
          contractCollections = List<dynamic>.from(data['Kontrak']).map((e) => e.toString()).toList();
        }

        // Fallback to legacy structure if no contracts found
        if (contractCollections.isEmpty) {
          contractCollections = ['Process'];
        }

        _setupContractStreams(kumitateDocRef, contractCollections);
      } else {
        // If Kumitate document doesn't exist, fallback to legacy structure
        _setupContractStreams(kumitateDocRef, ['Process']);
      }
    }, onError: (error) {
      debugPrint('Error listening to kumitate stream: $error');
      // Fallback to legacy structure on error
      final kumitateDocRef = _firestore.collection('counter_sistem')
        .doc(dateStr)
        .collection('A')
        .doc('Kumitate');
      _setupContractStreams(kumitateDocRef, ['Process']);
    });

    setState(() => _isLoading = false);
  }

  void _setupContractStreams(DocumentReference kumitateDocRef, List<String> contractCollections) {
    // Cancel existing contract subscriptions
    for (var subscription in _contractSubscriptions) {
      subscription.cancel();
    }
    _contractSubscriptions.clear();
    _contractData.clear();

    // Setup stream for each contract
    for (final contractName in contractCollections) {
      final contractStream = kumitateDocRef
          .collection(contractName)
          .orderBy('sequence', descending: true)
          .limit(1)
          .snapshots()
          .listen((QuerySnapshot snapshot) {
            if (snapshot.docs.isNotEmpty) {
              final processData = snapshot.docs.first.data() as Map<String, dynamic>;
              int contractTotal = 0;
              
              // Sum up all line counts from the process data
              processData.forEach((key, value) {
                if (key != 'sequence' && 
                    key != 'belumKensa' && 
                    key != 'stock_20min' && 
                    key != 'stock_pagi' && 
                    key != 'part' && 
                    value is Map<String, dynamic>) {
                  value.forEach((lineKey, lineValue) {
                    contractTotal += (lineValue as int? ?? 0);
                  });
                }
              });
              
              _contractData[contractName] = contractTotal;
              _updateTotalActual();
            } else {
              _contractData[contractName] = 0;
              _updateTotalActual();
            }
          }, onError: (error) {
            debugPrint('Error listening to contract $contractName stream: $error');
            _contractData[contractName] = 0;
            _updateTotalActual();
          });

      _contractSubscriptions.add(contractStream);
    }
  }

  void _updateTotalActual() {
    int total = 0;
    for (final value in _contractData.values) {
      total += value;
    }
    setState(() {
      _actual = total;
    });
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
    
    final fontSize = screenHeight * 0.28;
    final clampedFontSize = fontSize.clamp(60.0, 220.0);

    final horizontalPadding = screenWidth * 0.04;
    final verticalItemPadding = screenHeight * 0.005; 
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 15, 15, 15),
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _currentTime,
              style: TextStyle(
                fontSize: screenWidth < 600 ? 50 : 55, 
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            Text(
              'LINE A',
              style: TextStyle(
                fontSize: screenWidth < 600 ? 50 : 55, 
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(right: 0.0),
              child: _shouldBlink
                  ? Animate(
                      effects: [
                        TintEffect(
                          duration: 500.ms,
                          color: const Color.fromARGB(255, 255, 0, 0),
                          curve: Curves.easeInOut,
                        ),
                      ],
                      onPlay: (controller) => controller.repeat(reverse: true),
                      child: Text(
                        _countdown,
                        style: TextStyle(
                          fontSize: screenWidth < 600 ? 50 : 55, 
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : Text(
                      _countdown,
                      style: TextStyle(
                        fontSize: screenWidth < 600 ? 50 : 55, 
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            )
          ],
        ),
        centerTitle: false,
        backgroundColor: const Color.fromARGB(255, 10, 10, 10),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_plan == null)
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Failed to load data', 
                          style: TextStyle(
                            fontSize: screenWidth < 600 ? 24 : 28,
                            color: Colors.white,
                          )),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () {
                          _planSubscription?.cancel();
                          _kumitateSubscription?.cancel();
                          for (var subscription in _contractSubscriptions) {
                            subscription.cancel();
                          }
                          _setupStreams();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: EdgeInsets.only( 
                    left: screenWidth * 0.01,
                    right: screenWidth * 0.01,
                    top: screenHeight * 0.005,
                    bottom: screenHeight * 0.001, 
                  ),
                  child: SizedBox(
                    height: screenHeight * 0.88, 
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 15, 15, 15),
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
    final labelFontSize = fontSize * 0.7;
    
    return SizedBox(
      height: fontSize, 
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '$label:', 
            style: TextStyle(
              fontSize: labelFontSize,
              color: const Color.fromARGB(255, 255, 255, 255),
              fontWeight: FontWeight.bold,
              height: 0.9,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900, 
              color: const Color.fromARGB(255, 255, 0, 0),
              height: 0.9,
            ),
          ),
        ],
      ),
    );
  }
}