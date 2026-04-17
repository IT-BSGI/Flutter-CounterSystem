import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
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
  Map<String, Map<String, dynamic>> _latestProcessPerContract = {};
  Map<String, dynamic>? _latestProcessDocument;

  final List<String> _chartTimeSlots = [
    '08:30',
    '09:30',
    '10:30',
    '11:30',
    '13:30',
    '14:30',
    '15:30',
    '16:30',
    '17:55',
    '18:55',
    '19:55',
  ];

  // Clock and countdown
  String _currentTime = '';
  String _countdown = '';
  bool _shouldBlink = false;
  final List<TimeOfDay> _hourlyIntervals = [
    TimeOfDay(hour: 8, minute: 30),
    TimeOfDay(hour: 9, minute: 30),
    TimeOfDay(hour: 10, minute: 30),
    TimeOfDay(hour: 11, minute: 30),
    TimeOfDay(hour: 13, minute: 30),
    TimeOfDay(hour: 14, minute: 30),
    TimeOfDay(hour: 15, minute: 30),
    TimeOfDay(hour: 16, minute: 30),
    TimeOfDay(hour: 17, minute: 55),
    TimeOfDay(hour: 18, minute: 55),
    TimeOfDay(hour: 19, minute: 55),
  ];

  double _totalDailyTarget = 0.0;
  List<Map<String, dynamic>> _styles = [];
  Map<String, dynamic>? _overtimeData;
  Map<String, double> _hourlyTargetBySlot = {};

  final TimeOfDay _startWorkTime = TimeOfDay(hour: 7, minute: 30);
  final TimeOfDay _endWorkTime = TimeOfDay(hour: 20, minute: 0);

  @override
  void initState() {
    super.initState();
    _setupStreams();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isLoading) {
        _calculateCurrentTarget();
        _updateDisplayValues();
        _updateTime();
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
    TimeOfDay? nextInterval;
    for (final interval in _hourlyIntervals) {
      if (interval.hour > currentTime.hour ||
          (interval.hour == currentTime.hour &&
              interval.minute > currentTime.minute)) {
        nextInterval = interval;
        break;
      }
    }
    if (nextInterval == null) {
      _countdown = 'End of Day';
      _shouldBlink = false;
      return;
    }
    final nextDateTime = DateTime(
        now.year, now.month, now.day, nextInterval.hour, nextInterval.minute);
    final difference = nextDateTime.difference(now);
    if (difference.isNegative) {
      _countdown = '00:00';
      _shouldBlink = true;
    } else {
      final minutes =
          (difference.inMinutes.remainder(60)).toString().padLeft(2, '0');
      final seconds =
          (difference.inSeconds.remainder(60)).toString().padLeft(2, '0');
      _countdown = '$minutes:$seconds';
      _shouldBlink = difference.inMinutes < 1;
    }
  }

  void _processTargetMap(Map<String, dynamic>? targetMap) {
    _styles = [];
    _overtimeData = null;
    _totalDailyTarget = 0.0;

    if (targetMap != null && targetMap.isNotEmpty) {
      targetMap.forEach((key, value) {
        if (key != 'overtime' && value is Map) {
          _styles.add({
            'key': key,
            'quantity': (value['quantity'] as num?)?.toDouble() ?? 0.0,
            'time_perpcs': (value['time_perpcs'] as num?)?.toDouble() ?? 0.0,
          });
        }
      });
      _styles.sort((a, b) => a['key'].compareTo(b['key']));
      for (var style in _styles) {
        _totalDailyTarget += style['quantity'] ?? 0.0;
      }

      _hourlyTargetBySlot = {for (var slot in _chartTimeSlots) slot: 0.0};
      final normalSlots = _chartTimeSlots.sublist(0, 8);
      final overtimeSlots = _chartTimeSlots.sublist(8);
      const double slotSeconds = 3600.0;

      for (var style in _styles) {
        final double quantity = style['quantity'] ?? 0.0;
        final double timePerPcs = style['time_perpcs'] ?? 0.0;
        if (quantity <= 0 || timePerPcs <= 0) continue;
        double remainingPieces = quantity;
        for (var slot in normalSlots) {
          if (remainingPieces <= 0) break;
          final possiblePieces = slotSeconds / timePerPcs;
          if (possiblePieces <= 0) continue;
          final allocated = remainingPieces <= possiblePieces
              ? remainingPieces
              : possiblePieces;
          _hourlyTargetBySlot[slot] =
              (_hourlyTargetBySlot[slot] ?? 0.0) + allocated;
          remainingPieces -= allocated;
        }
        if (remainingPieces > 0) {
          for (var slot in overtimeSlots) {
            if (remainingPieces <= 0) break;
            final possiblePieces = slotSeconds / timePerPcs;
            if (possiblePieces <= 0) continue;
            final allocated = remainingPieces <= possiblePieces
                ? remainingPieces
                : possiblePieces;
            _hourlyTargetBySlot[slot] =
                (_hourlyTargetBySlot[slot] ?? 0.0) + allocated;
            remainingPieces -= allocated;
          }
        }
      }

      if (targetMap.containsKey('overtime')) {
        _overtimeData = targetMap['overtime'] as Map<String, dynamic>;
        double overtimeQuantity =
            (_overtimeData?['quantity'] as num?)?.toDouble() ?? 0.0;
        double overtimeTimePerPcs =
            (_overtimeData?['time_perpcs'] as num?)?.toDouble() ?? 0.0;
        _totalDailyTarget += overtimeQuantity;
        if (overtimeQuantity > 0 && overtimeTimePerPcs > 0) {
          double remainingPieces = overtimeQuantity;
          for (var slot in overtimeSlots) {
            if (remainingPieces <= 0) break;
            final possiblePieces = slotSeconds / overtimeTimePerPcs;
            if (possiblePieces <= 0) continue;
            final allocated = remainingPieces <= possiblePieces
                ? remainingPieces
                : possiblePieces;
            _hourlyTargetBySlot[slot] =
                (_hourlyTargetBySlot[slot] ?? 0.0) + allocated;
            remainingPieces -= allocated;
          }
        }
      }
    } else {
      if (_plan != null) {
        _totalDailyTarget = _plan!.toDouble();
        final normalSlots = _chartTimeSlots.sublist(0, 8);
        final average = _totalDailyTarget / normalSlots.length;
        _hourlyTargetBySlot = {
          for (var slot in _chartTimeSlots)
            slot: normalSlots.contains(slot) ? average : 0.0,
        };
      } else {
        _hourlyTargetBySlot = {for (var slot in _chartTimeSlots) slot: 0.0};
      }
    }
  }

  void _calculateCurrentTarget() {
    final now = DateTime.now();
    final currentTime = TimeOfDay.fromDateTime(now);
    if (_isBeforeWorkTime(currentTime)) {
      _currentTarget = 0.0;
      return;
    }
    if (_isAfterWorkTime(currentTime)) {
      _currentTarget = _totalDailyTarget;
      return;
    }
    double elapsedSeconds = _getElapsedSeconds(now);
    _currentTarget = _calculateRealTimeTarget(elapsedSeconds);
  }

  bool _isBeforeWorkTime(TimeOfDay currentTime) {
    return currentTime.hour < _startWorkTime.hour ||
        (currentTime.hour == _startWorkTime.hour &&
            currentTime.minute < _startWorkTime.minute);
  }

  bool _isAfterWorkTime(TimeOfDay currentTime) {
    return currentTime.hour > _endWorkTime.hour ||
        (currentTime.hour == _endWorkTime.hour &&
            currentTime.minute > _endWorkTime.minute);
  }

  double _getElapsedSeconds(DateTime now) {
    final startTime = DateTime(now.year, now.month, now.day,
        _startWorkTime.hour, _startWorkTime.minute);
    final breakStart = DateTime(now.year, now.month, now.day, 11, 30);
    final breakEnd = DateTime(now.year, now.month, now.day, 12, 30);
    final overtimeBreakStart = DateTime(now.year, now.month, now.day, 16, 30);
    final overtimeBreakEnd = DateTime(now.year, now.month, now.day, 16, 55);

    double elapsedSeconds = now.difference(startTime).inSeconds.toDouble();
    if (now.isAfter(breakStart)) {
      if (now.isBefore(breakEnd)) {
        elapsedSeconds = breakStart.difference(startTime).inSeconds.toDouble();
      } else {
        elapsedSeconds -= breakEnd.difference(breakStart).inSeconds.toDouble();
      }
    }
    if (now.isAfter(overtimeBreakStart)) {
      if (now.isBefore(overtimeBreakEnd)) {
        final regularWorkEnd =
            DateTime(now.year, now.month, now.day, 16, 30);
        elapsedSeconds =
            regularWorkEnd.difference(startTime).inSeconds.toDouble() -
                breakEnd.difference(breakStart).inSeconds.toDouble();
      } else {
        elapsedSeconds -= overtimeBreakEnd
            .difference(overtimeBreakStart)
            .inSeconds
            .toDouble();
      }
    }
    return elapsedSeconds > 0 ? elapsedSeconds : 0.0;
  }

  // Versi _getElapsedSeconds yang menerima DateTime arbitrary (bukan DateTime.now()),
  // digunakan untuk menghitung target kumulatif di akhir setiap slot chart.
  double _getElapsedSecondsAt(DateTime at) {
    final startTime = DateTime(at.year, at.month, at.day,
        _startWorkTime.hour, _startWorkTime.minute);
    final breakStart = DateTime(at.year, at.month, at.day, 11, 30);
    final breakEnd = DateTime(at.year, at.month, at.day, 12, 30);
    final overtimeBreakStart = DateTime(at.year, at.month, at.day, 16, 30);
    final overtimeBreakEnd = DateTime(at.year, at.month, at.day, 16, 55);
    double elapsedSeconds = at.difference(startTime).inSeconds.toDouble();
    if (at.isAfter(breakStart)) {
      if (at.isBefore(breakEnd)) {
        elapsedSeconds = breakStart.difference(startTime).inSeconds.toDouble();
      } else {
        elapsedSeconds -= breakEnd.difference(breakStart).inSeconds.toDouble();
      }
    }
    if (at.isAfter(overtimeBreakStart)) {
      if (at.isBefore(overtimeBreakEnd)) {
        final regularWorkEnd = DateTime(at.year, at.month, at.day, 16, 30);
        elapsedSeconds = regularWorkEnd.difference(startTime).inSeconds.toDouble() -
            breakEnd.difference(breakStart).inSeconds.toDouble();
      } else {
        elapsedSeconds -= overtimeBreakEnd.difference(overtimeBreakStart).inSeconds.toDouble();
      }
    }
    return elapsedSeconds > 0 ? elapsedSeconds : 0.0;
  }

  double _calculateRealTimeTarget(double elapsedSeconds) {
    if (_styles.isEmpty && _plan == null) return 0.0;
    if (_styles.isNotEmpty) return _calculateTargetFromStyles(elapsedSeconds);
    if (_plan != null) return _calculateLinearTarget(elapsedSeconds);
    return 0.0;
  }

  double _calculateTargetFromStyles(double elapsedSeconds) {
    double target = 0.0;
    double remainingTime = elapsedSeconds;
    for (var style in _styles) {
      double quantity = style['quantity'] ?? 0.0;
      double timePerPcs = style['time_perpcs'] ?? 0.0;
      if (timePerPcs <= 0 || quantity <= 0) continue;
      double styleTimeRequired = quantity * timePerPcs;
      if (remainingTime >= styleTimeRequired) {
        target += quantity;
        remainingTime -= styleTimeRequired;
      } else {
        target += remainingTime / timePerPcs;
        remainingTime = 0;
        break;
      }
    }
    if (remainingTime > 0 && _overtimeData != null) {
      double overtimeQuantity =
          (_overtimeData?['quantity'] as num?)?.toDouble() ?? 0.0;
      double overtimeTimePerPcs =
          (_overtimeData?['time_perpcs'] as num?)?.toDouble() ?? 0.0;
      if (overtimeTimePerPcs > 0 && overtimeQuantity > 0) {
        double overtimeTimeRequired = overtimeQuantity * overtimeTimePerPcs;
        if (remainingTime >= overtimeTimeRequired) {
          target += overtimeQuantity;
        } else {
          target += remainingTime / overtimeTimePerPcs;
        }
      }
    }
    return target > _totalDailyTarget ? _totalDailyTarget : target;
  }

  double _calculateLinearTarget(double elapsedSeconds) {
    const totalWorkSeconds = 28800.0;
    if (elapsedSeconds >= totalWorkSeconds) return _totalDailyTarget;
    return (_totalDailyTarget * elapsedSeconds) / totalWorkSeconds;
  }

  void _setupStreams() {
    final dateStr = DateFormat('yyyy-MM-dd').format(widget.date);

    _planSubscription = _firestore
        .collection('counter_sistem')
        .doc(dateStr)
        .snapshots()
        .listen((DocumentSnapshot snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>?;
        final plan = data?['target_A'] as int? ?? 0;
        setState(() {
          _plan = plan;
        });
        final targetMap = data?['target_map_A'] as Map<String, dynamic>?;
        _processTargetMap(targetMap);
      } else {
        setState(() {
          _plan = 0;
        });
        _processTargetMap(null);
      }
    }, onError: (error) {
      debugPrint('Error listening to plan stream: $error');
      setState(() {
        _plan = 0;
      });
      _processTargetMap(null);
    });

    final kumitateDocRef = _firestore
        .collection('counter_sistem')
        .doc(dateStr)
        .collection('A')
        .doc('Kumitate');

    _kumitateSubscription =
        kumitateDocRef.snapshots().listen((DocumentSnapshot snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>?;
        List<String> contractCollections = [];
        if (data != null && data['Kontrak'] is List) {
          contractCollections = List<dynamic>.from(data['Kontrak'])
              .map((e) => e.toString())
              .toList();
        }
        if (contractCollections.isEmpty) contractCollections = ['Process'];
        _setupContractStreams(kumitateDocRef, contractCollections);
      } else {
        _setupContractStreams(kumitateDocRef, ['Process']);
      }
    }, onError: (error) {
      debugPrint('Error listening to kumitate stream: $error');
      final kumitateDocRef = _firestore
          .collection('counter_sistem')
          .doc(dateStr)
          .collection('A')
          .doc('Kumitate');
      _setupContractStreams(kumitateDocRef, ['Process']);
    });

    setState(() => _isLoading = false);
  }

  void _setupContractStreams(
      DocumentReference kumitateDocRef, List<String> contractCollections) {
    for (var subscription in _contractSubscriptions) {
      subscription.cancel();
    }
    _contractSubscriptions.clear();
    _contractData.clear();
    _latestProcessPerContract.clear();
    _latestProcessDocument = null;

    for (final contractName in contractCollections) {
      final contractStream = kumitateDocRef
          .collection(contractName)
          .orderBy('sequence', descending: true)
          .limit(1)
          .snapshots()
          .listen((QuerySnapshot snapshot) {
        if (snapshot.docs.isNotEmpty) {
          final processData =
              snapshot.docs.first.data() as Map<String, dynamic>;
          int contractTotal = 0;
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
          _latestProcessPerContract[contractName] = {
            'sequence': processData['sequence'] as int? ?? 0,
            'raw_data': processData,
            'contract': contractName,
          };
          _updateLatestProcessDocument();
          _updateTotalActual();
        } else {
          _contractData[contractName] = 0;
          _latestProcessPerContract[contractName] = {
            'sequence': 0,
            'raw_data': <String, dynamic>{},
            'contract': contractName,
          };
          _updateLatestProcessDocument();
          _updateTotalActual();
        }
      }, onError: (error) {
        debugPrint('Error listening to contract $contractName stream: $error');
        _contractData[contractName] = 0;
        _latestProcessPerContract[contractName] = {
          'sequence': 0,
          'raw_data': <String, dynamic>{},
          'contract': contractName,
        };
        _updateLatestProcessDocument();
        _updateTotalActual();
      });
      _contractSubscriptions.add(contractStream);
    }
  }

  void _updateLatestProcessDocument() {
    Map<String, dynamic>? latest;
    int maxSequence = -1;
    _latestProcessPerContract.forEach((_, processEntry) {
      final int sequence = processEntry['sequence'] as int? ?? 0;
      if (sequence >= maxSequence) {
        maxSequence = sequence;
        latest = processEntry;
      }
    });
    setState(() {
      _latestProcessDocument = latest;
    });
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

  void _updateDisplayValues() {
    final currentTargetInt = _currentTarget.floor();
    setState(() {
      if (currentTargetInt > _lastStableTarget) {
        _lastStableTarget = currentTargetInt;
        _displayedTarget = _lastStableTarget;
      }
    });
  }

  String? _mapRawKeyToSlot(String rawKey) {
    final mapping = {
      '06:30': '08:30', '06:45': '08:30', '07:00': '08:30',
      '07:15': '08:30', '07:30': '08:30', '07:45': '08:30',
      '08:00': '08:30', '08:15': '08:30', '08:30': '09:30',
      '08:45': '09:30', '09:00': '09:30', '09:15': '09:30',
      '09:30': '10:30', '09:45': '10:30', '10:00': '10:30',
      '10:15': '10:30', '10:30': '11:30', '10:45': '11:30',
      '11:00': '11:30', '11:15': '11:30', '11:30': '13:30',
      '11:45': '13:30', '12:00': '13:30', '12:15': '13:30',
      '12:30': '13:30', '12:45': '13:30', '13:00': '13:30',
      '13:15': '13:30', '13:30': '14:30', '13:45': '14:30',
      '14:00': '14:30', '14:15': '14:30', '14:30': '15:30',
      '14:45': '15:30', '15:00': '15:30', '15:15': '15:30',
      '15:30': '16:30', '15:45': '16:30', '16:00': '16:30',
      '16:15': '16:30', '16:30': '16:30', '16:45': '17:55',
      '17:00': '17:55', '17:15': '17:55', '17:30': '17:55',
      '17:45': '17:55', '18:00': '18:55', '18:15': '18:55',
      '18:30': '18:55', '18:45': '18:55', '19:00': '19:55',
      '19:15': '19:55', '19:30': '19:55', '19:45': '19:55',
      '20:00': '19:55',
    };
    return mapping[rawKey];
  }

  // ─── Gauge painter ─────────────────────────────────────────────────────────
  Widget _buildGauge({
    required String title,
    required int value,
    required int maxValue,
    required Color arcColor,
    required double size,
  }) {
    final pct = maxValue > 0 ? (value / maxValue).clamp(0.0, 2.0) : 0.0;
    final pctDisplay = maxValue > 0 ? (value / maxValue * 100) : 0.0;

    return Container(
      width: size,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Plan value shown above the gauge arc
          Text(
            'PLAN: $maxValue',
            style: TextStyle(
              color: const Color(0xFFFF0000),
              fontSize: size * 0.155,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: size * 0.75,
            height: size * 0.45,
            child: CustomPaint(
              painter: _GaugePainter(
                fraction: pct.clamp(0.0, 1.0),
                arcColor: arcColor,
                bgColor: const Color(0xFF2A2A2A),
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        '${pctDisplay.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: arcColor,
                          fontSize: size * 0.11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$value / $maxValue',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: size * 0.08,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
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
            _shouldBlink
                ? Animate(
                    effects: [
                      TintEffect(
                        duration: 500.ms,
                        color: Colors.red,
                        curve: Curves.easeInOut,
                      ),
                    ],
                    onPlay: (c) => c.repeat(reverse: true),
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
          ],
        ),
        centerTitle: false,
        backgroundColor: const Color(0xFF0A0A0A),
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
                          for (var s in _contractSubscriptions) {
                            s.cancel();
                          }
                          _setupStreams();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _buildMainLayout(screenWidth, screenHeight),
    );
  }

  Widget _buildMainLayout(double sw, double sh) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          // ── TOP: ACTUAL gauge | chart ────────────────────────────────────────
          SizedBox(
            height: sh * 0.46,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Actual gauge (left)
                SizedBox(
                  width: sw * 0.27,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: _buildGauge(
                      title: 'ACTUAL',
                      value: _actual,
                      maxValue: _plan ?? 1,
                      arcColor: const Color(0xFF00E5CC),
                      size: sw * 0.27,
                    ),
                  ),
                ),
                // Chart (takes remaining space)
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _buildChartSection(sw * 0.73, sh * 0.46),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ── BOTTOM: TARGET | ACTUAL ──────────────────────────────────────────
          Expanded(
            child: _buildBottomSection(sw),
          ),
        ],
      ),
    );
  }

  // ─── Chart section (bar + line overlay) ────────────────────────────────────
  Widget _buildChartSection(double screenWidth, double sectionHeight) {
    final rawData =
        _latestProcessDocument?['raw_data'] as Map<String, dynamic>?;
    final hasData = rawData != null && rawData.isNotEmpty;

    if (!hasData) {
      return Center(
        child: Text(
          'No data available for the latest process',
          style: TextStyle(color: Colors.white, fontSize: 18),
          textAlign: TextAlign.center,
        ),
      );
    }

    final Map<String, int> hourlyCounts = {
      for (var slot in _chartTimeSlots) slot: 0
    };
    final Map<String, double> targetHourlyCounts = {};

    rawData.forEach((key, value) {
      if (key != 'sequence' &&
          key != 'belumKensa' &&
          key != 'stock_20min' &&
          key != 'stock_pagi' &&
          key != 'part' &&
          value is Map<String, dynamic>) {
        final mappedSlot = _mapRawKeyToSlot(key);
        if (mappedSlot == null) return;
        int slotTotal = 0;
        for (int i = 1; i <= 5; i++) {
          final count = value['$i'];
          final int countInt = count is num
              ? count.toInt()
              : int.tryParse(count.toString()) ?? 0;
          slotTotal += countInt;
        }
        hourlyCounts[mappedSlot] = (hourlyCounts[mappedSlot] ?? 0) + slotTotal;
      }
    });

    final Map<String, int> cumulativeCounts = {};
    final Map<String, double> cumulativeTargetCounts = {};
    int runningTotal = 0;
    for (var slot in _chartTimeSlots) {
      runningTotal += hourlyCounts[slot] ?? 0;
      cumulativeCounts[slot] = runningTotal;
    }

    // Hitung target kumulatif per slot menggunakan logika elapsed seconds
    // yang memperhitungkan break makan siang & break overtime.
    final now = DateTime.now();
    for (var i = 0; i < _chartTimeSlots.length; i++) {
      final slot = _chartTimeSlots[i];
      final interval = _hourlyIntervals[i];
      final slotDateTime = DateTime(
          now.year, now.month, now.day, interval.hour, interval.minute);
      final elapsedAtSlot = _getElapsedSecondsAt(slotDateTime);
      cumulativeTargetCounts[slot] = _calculateRealTimeTarget(elapsedAtSlot);
    }

    // Target bar = selisih kumulatif rounded antar slot
    int prevCumTargetRounded = 0;
    for (var slot in _chartTimeSlots) {
      final cumTargetRounded = (cumulativeTargetCounts[slot] ?? 0.0).round();
      targetHourlyCounts[slot] = (cumTargetRounded - prevCumTargetRounded).toDouble();
      prevCumTargetRounded = cumTargetRounded;
    }

    final double barMax = [
      hourlyCounts.values.fold<double>(
          0.0, (prev, v) => v > prev ? v.toDouble() : prev),
      targetHourlyCounts.values
          .fold<double>(0.0, (prev, v) => v > prev ? v : prev),
    ].fold<double>(0.0, (prev, v) => v > prev ? v : prev);

    final double cumulativeTargetMax = cumulativeTargetCounts.values
        .fold<double>(0.0, (prev, v) => v > prev ? v : prev);
    final double cumulativeActualMax = cumulativeCounts.values.fold<double>(
        0.0, (prev, v) => v > prev ? v.toDouble() : prev);
    final double lineChartMax = (cumulativeTargetMax > cumulativeActualMax
            ? cumulativeTargetMax
            : cumulativeActualMax)
        .clamp(10.0, double.infinity);

    final double chartMax = (barMax * 1.2).clamp(10.0, double.infinity);
    const double barWidth = 28.0;
    const double barsSpace = 5.0;
    const double labelFontSize = 13.0;

    final lineSpots = [
      FlSpot(-0.5, 0),
      ..._chartTimeSlots.asMap().entries.map((entry) {
        return FlSpot(entry.key.toDouble(),
            cumulativeCounts[entry.value]?.toDouble() ?? 0.0);
      }),
    ];

    final targetLineSpots = [
      FlSpot(-0.5, 0),
      ..._chartTimeSlots.asMap().entries.map((entry) {
        return FlSpot(entry.key.toDouble(),
            cumulativeTargetCounts[entry.value] ?? 0.0);
      }),
    ];

    final barGroups = _chartTimeSlots.asMap().entries.map((e) {
      final slot = e.value;
      return BarChartGroupData(
        x: e.key + 1,
        barsSpace: barsSpace,
        barRods: [
          BarChartRodData(
            toY: targetHourlyCounts[slot] ?? 0.0,
            color: Colors.red,
            width: barWidth,
            borderRadius: BorderRadius.circular(3),
          ),
          BarChartRodData(
            toY: hourlyCounts[slot]?.toDouble() ?? 0.0,
            color: Colors.blue,
            width: barWidth,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header: total target + legend ──────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildLegendDot(Colors.blue, 'Aktual per jam'),
              const SizedBox(width: 8),
              _buildLegendDot(Colors.red, 'Target per jam'),
              const SizedBox(width: 8),
              _buildLegendDot(Colors.white, 'Aktual Akumulatif', isLine: true),
              const SizedBox(width: 8),
              _buildLegendDot(Colors.white, 'Target Akumulatif',
                  isLine: true, isDashed: true),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;
              final totalHeight = constraints.maxHeight;
              const double leftTitleWidth = 36.0;
              const double rightTitleWidth = 40.0;
              const double bottomTitleHeight = 36.0;
              const double topPadding = 28.0;
              final double chartAreaWidth =
                  totalWidth - leftTitleWidth - rightTitleWidth;
              final double chartAreaHeight =
                  totalHeight - bottomTitleHeight - topPadding;
              final int n = _chartTimeSlots.length;
              final double slotWidth = chartAreaWidth / n;

              return Stack(children: [
                // BarChart
                Positioned(
                  top: topPadding,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: BarChart(BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: chartMax,
                    barGroups: barGroups,
                    gridData: FlGridData(
                      show: true,
                      drawHorizontalLine: true,
                      horizontalInterval: chartMax / 5,
                      getDrawingHorizontalLine: (_) =>
                          FlLine(color: Colors.white12, strokeWidth: 1),
                    ),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 1,
                          reservedSize: bottomTitleHeight,
                          getTitlesWidget: (value, _) {
                            final idx = value.toInt() - 1;
                            if (idx < 0 || idx >= _chartTimeSlots.length)
                              return const SizedBox();
                            return Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: SizedBox(
                                width: slotWidth,
                                child: Text(
                                  _chartTimeSlots[idx],
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 11),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: leftTitleWidth,
                          interval: chartMax / 5,
                          getTitlesWidget: (value, _) => Text(
                            value.toInt().toString(),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11),
                          ),
                        ),
                      ),
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: rightTitleWidth,
                          interval: chartMax / 5,
                          getTitlesWidget: (value, _) {
                            final cv =
                                ((value / chartMax) * lineChartMax).round();
                            return Text(cv.toString(),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 11));
                          },
                        ),
                      ),
                      topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    barTouchData: BarTouchData(enabled: false),
                  )),
                ),

                // Line overlay (akumulatif actual + target) via fl_chart LineChart
                Positioned(
                  top: topPadding,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LineChart(
                    LineChartData(
                      minX: -0.5,
                      maxX: (_chartTimeSlots.length - 1).toDouble() + 0.5,
                      minY: -(lineChartMax * 0.06),
                      maxY: lineChartMax,
                      lineBarsData: [
                        LineChartBarData(
                          spots: lineSpots,
                          isCurved: false,
                          barWidth: 2,
                          color: Colors.white,
                          dotData: FlDotData(show: true),
                        ),
                        LineChartBarData(
                          spots: targetLineSpots,
                          isCurved: false,
                          barWidth: 2,
                          color: Colors.white,
                          dotData: FlDotData(show: false),
                          dashArray: [5, 5],
                        ),
                      ],
                      gridData: FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(show: false),
                      lineTouchData: LineTouchData(enabled: false),
                    ),
                  ),
                ),

                // Labels per slot
                ...(_chartTimeSlots.asMap().entries.expand((entry) {
                  final index = entry.key;
                  final slot = entry.value;
                  final actualValue = hourlyCounts[slot]?.toDouble() ?? 0.0;
                  final targetValue = targetHourlyCounts[slot] ?? 0.0;
                  final double rawCumulativeValue =
                      cumulativeCounts[slot]?.toDouble() ?? 0.0;
                  final double rawCumulativeTargetValue =
                      cumulativeTargetCounts[slot] ?? 0.0;

                  final double groupCenterX = n > 0
                      ? leftTitleWidth +
                          ((2 * index + 1) / (2 * n)) * chartAreaWidth
                      : leftTitleWidth + chartAreaWidth / 2;

                  final double targetBarCenterX =
                      groupCenterX - barsSpace / 2 - barWidth / 2;
                  final double actualBarCenterX =
                      groupCenterX + barsSpace / 2 + barWidth / 2;

                  final double targetBarPx =
                      (targetValue / chartMax) * chartAreaHeight;
                  final double actualBarPx =
                      (actualValue / chartMax) * chartAreaHeight;

                  final double targetBarTop =
                      topPadding + chartAreaHeight - targetBarPx;
                  final double actualBarTop =
                      topPadding + chartAreaHeight - actualBarPx;

                  final double targetLabelTop =
                      targetBarTop + targetBarPx - labelFontSize - 4;
                  final double actualLabelTop =
                      actualBarTop + actualBarPx - labelFontSize - 4;

                  final double actualLabelTopClamped =
                      actualLabelTop.clamp(actualBarTop, totalHeight - 20.0);

                  const double selisihLabelHeight = labelFontSize - 3 + 4;
                  double selisihTop =
                      actualLabelTopClamped - selisihLabelHeight - 2.0;
                  if (selisihTop < topPadding) selisihTop = topPadding;
                  final double selisihBottom = selisihTop + selisihLabelHeight;

                  const double cumulativeLabelCardHeight = labelFontSize * 3 + 16;
                  final double lineMinY = -(lineChartMax * 0.06);
                  final double lineRangeY = lineChartMax - lineMinY;

                  final double targetLinePx = topPadding +
                      chartAreaHeight *
                          (1.0 -
                              (rawCumulativeTargetValue - lineMinY) /
                                  lineRangeY);
                  final double actualLinePx = topPadding +
                      chartAreaHeight *
                          (1.0 -
                              (rawCumulativeValue - lineMinY) / lineRangeY);

                  final double highestLinePx =
                      targetLinePx < actualLinePx ? targetLinePx : actualLinePx;

                  double cumulativeLabelTop =
                      highestLinePx - cumulativeLabelCardHeight - 8;
                  cumulativeLabelTop = cumulativeLabelTop.clamp(
                      0.0, totalHeight - cumulativeLabelCardHeight);

                  final double cardBottom =
                      cumulativeLabelTop + cumulativeLabelCardHeight;
                  if (cumulativeLabelTop < selisihBottom &&
                      cardBottom > selisihTop) {
                    final double candidateTop =
                        selisihTop - cumulativeLabelCardHeight - 6;
                    if (candidateTop >= 0) {
                      cumulativeLabelTop = candidateTop;
                    } else {
                      final double belowCandidate = highestLinePx + 6;
                      final double maxTop =
                          totalHeight - cumulativeLabelCardHeight;
                      cumulativeLabelTop =
                          belowCandidate.clamp(0.0, maxTop);
                    }
                  }

                  return [
                    // Label TARGET (putih, di dalam batang merah)
                    if (targetValue > 0)
                      Positioned(
                        left: targetBarCenterX - barWidth / 2,
                        top: targetLabelTop.clamp(
                            targetBarTop, totalHeight - 20.0),
                        width: barWidth,
                        child: Text(
                          targetValue.round().toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: labelFontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                    // Label ACTUAL (putih, di dalam batang biru)
                    if (actualValue > 0)
                      Positioned(
                        left: actualBarCenterX - barWidth / 2,
                        top: actualLabelTop.clamp(
                            actualBarTop, totalHeight - 20.0),
                        width: barWidth,
                        child: Text(
                          actualValue.toInt().toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: labelFontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                    // Label SELISIH — tepat di atas batang actual
                    if (actualValue > 0 || targetValue > 0)
                      Positioned(
                        left: actualBarCenterX - barWidth / 2 - 4,
                        top: selisihTop,
                        width: barWidth + 8,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 3, vertical: 1),
                            decoration: BoxDecoration(
                              color: (actualValue.toInt() -
                                          targetValue.round()) >=
                                      0
                                  ? Colors.green.withOpacity(0.85)
                                  : Colors.red.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              () {
                                final diff = actualValue.toInt() -
                                    targetValue.round();
                                return diff >= 0 ? '+$diff' : '$diff';
                              }(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: labelFontSize - 3,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Card AKUMULATIF (kuning dengan opacity)
                    Positioned(
                      left: groupCenterX - 30,
                      top: cumulativeLabelTop,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6.0, vertical: 3.0),
                        decoration: BoxDecoration(
                          color: Colors.yellow.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(6.0),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'T:${(cumulativeTargetCounts[slot]?.round() ?? 0)}',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'A:${(cumulativeCounts[slot] ?? 0)}',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              () {
                                final diff = (cumulativeCounts[slot] ?? 0) -
                                    (cumulativeTargetCounts[slot]?.round() ?? 0);
                                return 'S:${diff >= 0 ? '+$diff' : '$diff'}';
                              }(),
                              style: TextStyle(
                                color: (() {
                                  final diff = (cumulativeCounts[slot] ?? 0) -
                                      (cumulativeTargetCounts[slot]?.round() ?? 0);
                                  return diff >= 0
                                      ? const Color(0xFF00A000)
                                      : const Color(0xFFCC0000);
                                })(),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ];
                }).toList()),
              ]);
            }),
          ),
        ],
      ),
    );
  }

  // ─── Bottom section: TARGET | ACTUAL side by side ───────────────────────────
  Widget _buildBottomSection(double sw) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;
          final valueFontSize = (availableHeight * 0.72).clamp(50.0, 240.0);
          final labelFontSize = (availableHeight * 0.20).clamp(16.0, 60.0);
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: _buildMetricColumn(
                    label: 'TARGET',
                    value: _displayedTarget.toString(),
                    valueFontSize: valueFontSize,
                    labelFontSize: labelFontSize,
                  ),
                ),
                Container(
                  width: 2,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  color: Colors.white24,
                ),
                Expanded(
                  child: _buildMetricColumn(
                    label: 'ACTUAL',
                    value: _actual.toString(),
                    valueFontSize: valueFontSize,
                    labelFontSize: labelFontSize,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetricColumn({
    required String label,
    required String value,
    required double valueFontSize,
    required double labelFontSize,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: labelFontSize * 0.75,
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 2),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: valueFontSize * 1.15,
                fontWeight: FontWeight.w900,
                color: const Color(0xFFFF0000),
                height: 0.95,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegendDot(Color color, String label,
      {bool isLine = false, bool isDashed = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        isLine
            ? SizedBox(
                width: 20,
                height: 3,
                child: CustomPaint(
                  painter: _DashedLinePainter(color: color, dashed: isDashed),
                ),
              )
            : Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 10)),
      ],
    );
  }
}

// ─── Gauge CustomPainter ──────────────────────────────────────────────────────
class _GaugePainter extends CustomPainter {
  final double fraction; // 0.0 to 1.0
  final Color arcColor;
  final Color bgColor;

  const _GaugePainter({
    required this.fraction,
    required this.arcColor,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.92;
    final radius = math.min(cx, cy) * 0.95;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);
    const startAngle = math.pi;
    const sweepAngle = math.pi;

    // Background arc
    final bgPaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.18
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, startAngle, sweepAngle, false, bgPaint);

    // Foreground arc
    final fgPaint = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.18
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
        rect, startAngle, sweepAngle * fraction.clamp(0.0, 1.0), false, fgPaint);

    // Tick marks at 0, 25, 50, 75, 100%
    final tickPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.5;
    for (int i = 0; i <= 4; i++) {
      final angle = math.pi + (math.pi * i / 4);
      final innerR = radius * 0.72;
      final outerR = radius * 0.88;
      final dx1 = cx + innerR * math.cos(angle);
      final dy1 = cy + innerR * math.sin(angle);
      final dx2 = cx + outerR * math.cos(angle);
      final dy2 = cy + outerR * math.sin(angle);
      canvas.drawLine(Offset(dx1, dy1), Offset(dx2, dy2), tickPaint);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction || old.arcColor != arcColor;
}

// ─── Dashed line painter for legend ──────────────────────────────────────────
class _DashedLinePainter extends CustomPainter {
  final Color color;
  final bool dashed;
  const _DashedLinePainter({required this.color, required this.dashed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    if (!dashed) {
      canvas.drawLine(
          Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint);
    } else {
      double x = 0;
      while (x < size.width) {
        canvas.drawLine(Offset(x, size.height / 2),
            Offset(math.min(x + 4, size.width), size.height / 2), paint);
        x += 8;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}