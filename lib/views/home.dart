import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DateTime selectedDate = DateTime.now();
  bool isLoading = true;
  Map<String, List<Map<String, dynamic>>> lineData = {};
  Map<String, String?> selectedProcesses = {};
  late PageController _pageController;
  int _currentPage = 0;
  Timer? _slideshowTimer;
  bool _isSlideshowRunning = true;
  String? _pausedLine;
  Map<String, double> _dailyTargets = {};
  Map<String, Map<String, double>> _hourlyTargets = {};
  Map<String, StreamSubscription> _streamSubscriptions = {};

  // Updated time slots to match counter_table_screen.dart
  final List<String> timeSlots = [
    "08:30", "09:30", "10:30", "11:30",
    "13:30", "14:30", "15:30", "16:30",
    // Overtime slots (start at 16:55, per jam)
    "17:55", "18:55", "19:55",
  ];

  final Map<String, String> timeRangeMap = {
    "06:30": "08:30",
    "06:45": "08:30",
    "07:00": "08:30",
    "07:15": "08:30",
    "07:30": "08:30",
    "07:45": "08:30",
    "08:00": "08:30",
    "08:15": "08:30",

    "08:30": "09:30",
    "08:45": "09:30",
    "09:00": "09:30",
    "09:15": "09:30",

    "09:30": "10:30",
    "09:45": "10:30",
    "10:00": "10:30",
    "10:15": "10:30",

    "10:30": "11:30",
    "10:45": "11:30",
    "11:00": "11:30",
    "11:15": "11:30",

    "11:30": "13:30",
    "11:45": "13:30",
    "12:00": "13:30",
    "12:15": "13:30",

    "12:30": "13:30",
    "12:45": "13:30",
    "13:00": "13:30",
    "13:15": "13:30",

    "13:30": "14:30",
    "13:45": "14:30",
    "14:00": "14:30",
    "14:15": "14:30",

    "14:30": "15:30",
    "14:45": "15:30",
    "15:00": "15:30",
    "15:15": "15:30",

    "15:30": "16:30",
    "15:45": "16:30",
    "16:00": "16:30",
    "16:15": "16:30",
    "16:30": "16:30",

    // Map post-16:30 minutes into overtime slots (start: 16:55, per jam)
    "16:45": "17:55",
    "17:00": "17:55",
    "17:15": "17:55",
    "17:30": "17:55",
    "17:45": "17:55",

    "18:00": "18:55",
    "18:15": "18:55",
    "18:30": "18:55",
    "18:45": "18:55",

    "19:00": "19:55",
    "19:15": "19:55",
    "19:30": "19:55",
    "19:45": "19:55",
    "20:00": "19:55",
  };

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadInitialData();
  }

  void _loadInitialData() async {
    await loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSlideshowTimer();
    });
  }

  @override
  void dispose() {
    _slideshowTimer?.cancel();
    _pageController.dispose();
    _streamSubscriptions.forEach((_, subscription) => subscription.cancel());
    super.dispose();
  }

  void _startSlideshowTimer() {
    _slideshowTimer?.cancel();
    if (!_isSlideshowRunning || !_pageController.hasClients || lineData.isEmpty)
      return;

    _slideshowTimer = Timer.periodic(Duration(seconds: 10), (Timer timer) {
      if (!_pageController.hasClients) return;

      if (_currentPage < lineData.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }
      _pageController.animateToPage(
        _currentPage,
        duration: Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _refreshCurrentLineData() async {
    if (isLoading) return;

    setState(() => isLoading = true);

    String formattedDate = DateFormat("yyyy-MM-dd").format(selectedDate);
    String currentLine = _pausedLine ?? lineData.keys.elementAt(_currentPage);
    String? currentProcessName = selectedProcesses[currentLine];

    try {
      var newData = await fetchLineData(currentLine, formattedDate);
      await _fetchTarget(currentLine, formattedDate);

      if (mounted && newData.isNotEmpty) {
        setState(() {
          lineData[currentLine] = newData;
          bool processExists =
              newData.any((p) => p['process_name'] == currentProcessName);
          selectedProcesses[currentLine] =
              processExists ? currentProcessName : newData.last['process_name'];
          isLoading = false;
        });

        if (!_isSlideshowRunning && _pageController.hasClients) {
          _pageController.jumpToPage(_currentPage);
        }
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      print("Error refreshing data for Line $currentLine: $e");
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _fetchTarget(String line, String date) async {
    try {
      final docRef =
          FirebaseFirestore.instance.collection('counter_sistem').doc(date);
      final doc = await docRef.get();

      if (doc.exists) {
        final data = doc.data()!;
        final targetMap =
            data['target_map_$line'] as Map<String, dynamic>? ?? {};

        // Inisialisasi hourly targets menggunakan label yang sama dengan `timeSlots`
        Map<String, double> calculatedHourlyTargets = {
          for (var s in timeSlots) s: 0.0,
        };

        double totalDailyTarget = 0.0;

        if (targetMap.isNotEmpty) {
          // Ekstrak style data (kecuali overtime)
          List<Map<String, dynamic>> styles = [];
          targetMap.forEach((key, value) {
            if (key != 'overtime' && value is Map) {
              styles.add({
                'key': key,
                'quantity': (value['quantity'] as num?)?.toDouble() ?? 0.0,
                'time_perpcs':
                    (value['time_perpcs'] as num?)?.toDouble() ?? 0.0,
              });
            }
          });

          // Urutkan styles berdasarkan key (style1, style2, dll)
          styles.sort((a, b) => a['key'].compareTo(b['key']));

          // Hitung target per slot untuk jam kerja normal.
          // Gunakan label `timeSlots` untuk kunci, dan alokasikan total productive seconds (8 jam = 28800s)
          // secara merata ke semua normal slots (non-overtime) agar perubahan timeslot tetap sinkron.
          // Overtime slots are now 17:55, 18:55, 19:55 (per jam)
          List<String> overtimeTimeSlots = ['17:55', '18:55', '19:55'];
          List<String> normalTimeSlots =
              timeSlots.where((s) => !overtimeTimeSlots.contains(s)).toList();
          int currentTimeSlotIndex = 0;

          // Compute actual available seconds per normal slot by intersecting slot interval
          // with productive periods (07:30-11:30 and 13:30-17:30). This ensures slots
          // that are 30-min are handled correctly and allocation by time_perpcs is accurate.
          DateTime parseTime(String t) {
            final parts = t.split(':');
            return DateTime(
                2000, 1, 1, int.parse(parts[0]), int.parse(parts[1]));
          }

          DateTime morningStart = DateTime(2000, 1, 1, 7, 30);
          DateTime morningEnd = DateTime(2000, 1, 1, 11, 30);
          DateTime afternoonStart = DateTime(2000, 1, 1, 12, 30);
          DateTime afternoonEnd = DateTime(2000, 1, 1, 16, 31);

          final Map<String, double> slotRemainingSeconds = {};
          for (int idx = 0; idx < normalTimeSlots.length; idx++) {
            final endLabel = normalTimeSlots[idx];
            final DateTime end = parseTime(endLabel);
            final DateTime start;
            if (idx > 0) {
              start = parseTime(normalTimeSlots[idx - 1]);
            } else {
              start = DateTime(2000, 1, 1, 7, 30);
            }

            double avail = 0.0;
            // overlap with morning
            final overlapStart1 =
                start.isAfter(morningStart) ? start : morningStart;
            final overlapEnd1 = end.isBefore(morningEnd) ? end : morningEnd;
            if (overlapEnd1.isAfter(overlapStart1)) {
              avail +=
                  overlapEnd1.difference(overlapStart1).inSeconds.toDouble();
            }
            // overlap with afternoon
            final overlapStart2 =
                start.isAfter(afternoonStart) ? start : afternoonStart;
            final overlapEnd2 = end.isBefore(afternoonEnd) ? end : afternoonEnd;
            if (overlapEnd2.isAfter(overlapStart2)) {
              avail +=
                  overlapEnd2.difference(overlapStart2).inSeconds.toDouble();
            }

            slotRemainingSeconds[endLabel] = avail;
          }

          for (var style in styles) {
            double remainingQuantity = style['quantity'];
            double timePerPcs = style['time_perpcs'];

            if (timePerPcs <= 0) continue;

            while (remainingQuantity > 0 &&
                currentTimeSlotIndex < normalTimeSlots.length) {
              final currentTimeSlot = normalTimeSlots[currentTimeSlotIndex];
              double slotSec = slotRemainingSeconds[currentTimeSlot] ?? 3600.0;

              if (slotSec <= 1e-9) {
                currentTimeSlotIndex++;
                continue;
              }

              final possiblePieces = slotSec / timePerPcs;
              if (possiblePieces <= 1e-9) {
                currentTimeSlotIndex++;
                continue;
              }

              final allocated = possiblePieces >= remainingQuantity
                  ? remainingQuantity
                  : possiblePieces;

              calculatedHourlyTargets[currentTimeSlot] =
                  (calculatedHourlyTargets[currentTimeSlot] ?? 0.0) + allocated;
              remainingQuantity -= allocated;
              totalDailyTarget += allocated;

              slotSec -= allocated * timePerPcs;
              slotRemainingSeconds[currentTimeSlot] = slotSec;

              if (slotSec <= 1e-9) currentTimeSlotIndex++;
            }

            if (remainingQuantity > 0 &&
                currentTimeSlotIndex >= normalTimeSlots.length) {
              break;
            }
          }

          // Hitung overtime (sama: gunakan sisa detik per slot overtime)
          if (targetMap.containsKey('overtime')) {
            final overtimeData = targetMap['overtime'] as Map<String, dynamic>;
            double overtimeQuantity =
                (overtimeData['quantity'] as num?)?.toDouble() ?? 0.0;
            double overtimeTimePerPcs =
                (overtimeData['time_perpcs'] as num?)?.toDouble() ?? 0.0;

            if (overtimeTimePerPcs > 0 && overtimeQuantity > 0) {
              List<String> overtimeTimeSlots = ['17:55', '18:55', '19:55'];
              double remainingOvertime = overtimeQuantity;
              final Map<String, double> overtimeSlotSec = {
                for (var s in overtimeTimeSlots) s: 1800.0
              };
              int otIndex = 0;
              while (
                  remainingOvertime > 0 && otIndex < overtimeTimeSlots.length) {
                final slot = overtimeTimeSlots[otIndex];
                double slotSec = overtimeSlotSec[slot] ?? 3600.0;
                if (slotSec <= 1e-9) {
                  otIndex++;
                  continue;
                }

                final possiblePieces = slotSec / overtimeTimePerPcs;
                if (possiblePieces <= 1e-9) {
                  otIndex++;
                  continue;
                }

                final allocated = possiblePieces >= remainingOvertime
                    ? remainingOvertime
                    : possiblePieces;
                calculatedHourlyTargets[slot] =
                    (calculatedHourlyTargets[slot] ?? 0.0) + allocated;
                remainingOvertime -= allocated;
                totalDailyTarget += allocated;

                slotSec -= allocated * overtimeTimePerPcs;
                overtimeSlotSec[slot] = slotSec;

                if (slotSec <= 1e-9) otIndex++;
              }
            }
          }
        } else {
          // Fallback ke target lama jika tidak ada mapping
          final target = data['target_$line'];
          if (target is num) {
            totalDailyTarget = target.toDouble();
            // Distribusikan total daily target ke normal slots (non-overtime)
            List<String> overtimeTimeSlots = ['17:55', '18:55', '19:55'];
            final normalSlots =
                timeSlots.where((s) => !overtimeTimeSlots.contains(s)).toList();
            final perSlot = normalSlots.isNotEmpty
                ? totalDailyTarget / normalSlots.length
                : 0.0;
            calculatedHourlyTargets = {
              for (var s in timeSlots)
                s: (normalSlots.contains(s) ? perSlot : 0.0)
            };
          }
        }

        setState(() {
          _dailyTargets[line] = totalDailyTarget;
          _hourlyTargets[line] = calculatedHourlyTargets;
        });
      } else {
        setState(() {
          _dailyTargets[line] = 0.0;
          _hourlyTargets[line] = {};
        });
      }
    } catch (e) {
      print('Error loading targets for line $line: $e');
      setState(() {
        _dailyTargets[line] = 0.0;
        _hourlyTargets[line] = {};
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(Duration(days: 365)),
    );
    if (picked != null && picked != selectedDate) {
      _streamSubscriptions.forEach((_, subscription) => subscription.cancel());
      _streamSubscriptions.clear();

      setState(() {
        selectedDate = picked;
        _pausedLine = null;
      });
      await loadData();
    }
  }

  void _toggleSlideshow() {
    setState(() {
      _isSlideshowRunning = !_isSlideshowRunning;
      if (!_isSlideshowRunning) {
        _pausedLine = lineData.keys.elementAt(_currentPage);
      } else {
        _pausedLine = null;
      }
    });

    if (_isSlideshowRunning) {
      _startSlideshowTimer();
    } else {
      _slideshowTimer?.cancel();
    }
  }

  void _goToPage(int page) {
    if (!_pageController.hasClients) return;

    _currentPage = page;
    _pageController.animateToPage(
      _currentPage,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    _resetTimer();
  }

  void _resetTimer() {
    if (_isSlideshowRunning) {
      _slideshowTimer?.cancel();
      _startSlideshowTimer();
    } else {
      _pausedLine = lineData.keys.elementAt(_currentPage);
    }
  }

  Future<List<Map<String, dynamic>>> fetchLineData(
      String line, String date) async {
    try {
      // The database structure now stores dynamic contract collections under the
      // 'Kumitate' document (field 'Kontrak' contains the list of collection names).
      // Fallback to the legacy 'Process' collection when 'Kontrak' is missing.
      final kumitateDocRef = FirebaseFirestore.instance
          .collection('counter_sistem')
          .doc(date)
          .collection(line)
          .doc('Kumitate');

      final kumitateDoc = await kumitateDocRef.get();
      if (!kumitateDoc.exists) {
        print('No Kumitate document found for Line $line on $date');
        return [];
      }

      final data = kumitateDoc.data();
      final kontrakArray = (data != null && data['Kontrak'] is List)
          ? List<dynamic>.from(data['Kontrak'])
          : <dynamic>[];

      // If no kontrak list found, keep compatibility with older structure using 'Process'
      final contractCollections = kontrakArray.isEmpty
          ? ['Process']
          : kontrakArray.map((e) => e.toString()).toList();

      List<Map<String, dynamic>> processList = [];

      for (final contractName in contractCollections) {
        final collectionRef = kumitateDocRef.collection(contractName);
        final snapshot = await collectionRef.get();

        for (var doc in snapshot.docs) {
          final processData = doc.data();
          final processMap = <String, dynamic>{
            "process_name": doc.id.replaceAll('_', ' '),
            "sequence": (processData['sequence'] as num?)?.toInt() ?? 0,
            "raw_data": processData,
            // keep contract name and document id so entries are uniquely identifiable
            "contract": contractName,
            "id": doc.id,
          };

          // Initialize all time slots with 0
          Map<String, int> cumulativeData = {};
          for (final time in timeSlots) {
            cumulativeData[time] = 0;
          }

          // Process each time entry in the document
          processData.forEach((key, value) {
            if (key != 'sequence' &&
                key != 'belumKensa' &&
                key != 'stock_20min' &&
                key != 'stock_pagi' &&
                key != 'part' &&
                value is Map<String, dynamic>) {
              final mappedTime = timeRangeMap[key];
              if (mappedTime != null) {
                int slotTotal = 0;
                // Kumitate on Home uses up to 5 lines per process
                for (int i = 1; i <= 5; i++) {
                  final dynamic countValue = value['$i'];
                  final int count = countValue is num
                      ? countValue.toInt()
                      : int.tryParse(countValue.toString()) ?? 0;
                  slotTotal += count;
                }
                cumulativeData[mappedTime] =
                    (cumulativeData[mappedTime] ?? 0) + slotTotal;
              }
            }
          });

          // Create final cumulative data
          Map<String, int> finalCumulative = {};
          int currentCumulative = 0;
          for (String time in timeSlots) {
            currentCumulative += (cumulativeData[time] ?? 0);
            finalCumulative[time] = currentCumulative;
          }

          processMap['cumulative'] = finalCumulative;
          processList.add(processMap);
        }
      }

      // Sort by sequence number
      processList.sort(
          (a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int));
      return processList;
    } catch (e) {
      print('Error fetching counter data: $e');
      return [];
    }
  }

  void _setupStreamListeners(String date) {
    // Cancel previous subscriptions
    _streamSubscriptions.forEach((_, subscription) => subscription.cancel());
    _streamSubscriptions.clear();

    for (String line in ['A', 'B', 'C', 'D', 'E']) {
      final kumitateDocRef = FirebaseFirestore.instance
          .collection('counter_sistem')
          .doc(date)
          .collection(line)
          .doc('Kumitate');

      // Read contract list (Kontrak) to know which subcollections to listen to.
      kumitateDocRef.get().then((docSnap) {
        if (!docSnap.exists) return;
        final data = docSnap.data();
        final kontrakArray = (data != null && data['Kontrak'] is List)
            ? List<dynamic>.from(data['Kontrak'])
            : <dynamic>[];
        final contractCollections = kontrakArray.isEmpty
            ? ['Process']
            : kontrakArray.map((e) => e.toString()).toList();

        for (final contractName in contractCollections) {
          final stream = kumitateDocRef.collection(contractName).snapshots();
          final key = '$line|$contractName';
          _streamSubscriptions[key] = stream.listen((_) async {
            // On any change in any contract collection, refetch the whole line data
            try {
              final newData = await fetchLineData(line, date);
              if (mounted && newData.isNotEmpty) {
                setState(() {
                  lineData[line] = newData;
                });
              }
            } catch (e) {
              print(
                  'Error updating data from stream for $line/$contractName: $e');
            }
          });
        }
      }).catchError((e) {
        print('Error reading Kontrak for line $line on $date: $e');
      });
    }
  }

  Future<void> loadData() async {
    setState(() => isLoading = true);

    String formattedDate = DateFormat("yyyy-MM-dd").format(selectedDate);
    Map<String, List<Map<String, dynamic>>> newData = {};
    Map<String, String?> newSelectedProcesses = {};

    final currentLineBeforeRefresh = _pausedLine ??
        (_currentPage < lineData.length
            ? lineData.keys.elementAt(_currentPage)
            : null);
    final currentPageBeforeRefresh = _currentPage;

    for (String line in ['A', 'B', 'C', 'D', 'E']) {
      var data = await fetchLineData(line, formattedDate);
      await _fetchTarget(line, formattedDate);
      if (data.isNotEmpty) {
        newData[line] = data;
        final last = data.last;
        final lastName = last['process_name'];
        if (!selectedProcesses.containsKey(line)) {
          newSelectedProcesses[line] = lastName;
        } else {
          bool processExists =
              data.any((p) => p['process_name'] == selectedProcesses[line]);
          newSelectedProcesses[line] =
              processExists ? selectedProcesses[line] : lastName;
        }
      } else {
        print("No data or invalid format for Line $line");
      }
    }

    _setupStreamListeners(formattedDate);

    if (mounted) {
      setState(() {
        lineData = newData;
        selectedProcesses = newSelectedProcesses;
        isLoading = false;

        if (lineData.isNotEmpty) {
          if (currentLineBeforeRefresh != null &&
              lineData.containsKey(currentLineBeforeRefresh)) {
            _currentPage =
                lineData.keys.toList().indexOf(currentLineBeforeRefresh);
          } else if (currentPageBeforeRefresh < lineData.length) {
            _currentPage = currentPageBeforeRefresh;
          } else {
            _currentPage = 0;
          }

          if (!_isSlideshowRunning) {
            _pausedLine = lineData.keys.elementAt(_currentPage);
          }
        }
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients && lineData.isNotEmpty) {
          _pageController.jumpToPage(_currentPage);
        }
      });
    }
  }

  Widget _buildHeader(String line, List<Map<String, dynamic>> processes) {
    String? currentProcess = selectedProcesses[line];
    double? dailyTarget = _dailyTargets[line];
    Map<String, double>? hourlyTargets = _hourlyTargets[line];

    // Build deduplicated list of process names (labels). Selecting a name
    // will aggregate data across all contracts that have the same name.
    final seen = <String>{};
    final names = <String>[];
    for (var p in processes) {
      final name = (p['process_name'] ?? '').toString();
      if (name.isEmpty) continue;
      if (!seen.contains(name)) {
        seen.add(name);
        names.add(name);
      }
    }

    final displayValue =
        (currentProcess != null && names.contains(currentProcess))
            ? currentProcess
            : (names.isNotEmpty ? names.last : null);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                'Line $line - ',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
              ),
              DropdownButton<String>(
                value: displayValue,
                items: names.map((name) {
                  return DropdownMenuItem<String>(
                    value: name,
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      selectedProcesses[line] = newValue;
                    });
                  }
                },
                underline: Container(),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
              ),
              if (dailyTarget != null && dailyTarget > 0) ...[
                SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Target: ${dailyTarget.round()}',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    if (hourlyTargets != null && hourlyTargets.isNotEmpty)
                      Text(
                        'Per Jam: ${hourlyTargets.values.first.round()}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blue.shade600,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _isSlideshowRunning ? Icons.pause : Icons.play_arrow,
                  color: Colors.blue.shade700,
                ),
                onPressed: _toggleSlideshow,
                tooltip: _isSlideshowRunning
                    ? 'Pause Slideshow'
                    : 'Resume Slideshow',
              ),
              SizedBox(width: 8),
              TextButton(
                onPressed: () => _selectDate(context),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today,
                        size: 16, color: Colors.blue.shade700),
                    SizedBox(width: 4),
                    Text(
                      DateFormat('yyyy-MM-dd').format(selectedDate),
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
        ],
      ),
    );
  }

  Widget buildLineChart(String line, List<Map<String, dynamic>> processes) {
    String? currentProcessName = selectedProcesses[line];

    // Aggregate data for the selected process name across all contracts
    final Map<String, int> slotTotals = {for (var t in timeSlots) t: 0};
    final Map<String, Map<String, int>> rawDataAggregated = {};

    for (var p in processes) {
      if (p['process_name'] != currentProcessName) continue;
      final raw = p['raw_data'] as Map<String, dynamic>? ?? {};

      raw.forEach((key, value) {
        if (key == 'sequence' ||
            key == 'belumKensa' ||
            key == 'stock_20min' ||
            key == 'stock_pagi' ||
            key == 'part') return;
        if (value is! Map<String, dynamic>) return;
        final mapped = timeRangeMap[key];
        if (mapped == null) return;

        int slotSum = 0;
        for (int i = 1; i <= 5; i++) {
          final cnt = value['$i'];
          final int c =
              cnt is num ? cnt.toInt() : int.tryParse(cnt.toString()) ?? 0;
          slotSum += c;

          rawDataAggregated.putIfAbsent(key, () => {});
          rawDataAggregated[key]!['$i'] =
              (rawDataAggregated[key]!['$i'] ?? 0) + c;
        }

        slotTotals[mapped] = (slotTotals[mapped] ?? 0) + slotSum;
      });
    }

    // Build cumulative and hourly data
    Map<String, int> cumulativeActual = {};
    Map<String, double> hourlyTargets = _hourlyTargets[line] ?? {};

    int running = 0;
    for (var t in timeSlots) {
      running += (slotTotals[t] ?? 0);
      cumulativeActual[t] = running;
    }

    // Calculate cumulative target
    Map<String, double> cumulativeTarget = {};
    double cumTarget = 0.0;
    for (var t in timeSlots) {
      cumTarget += (hourlyTargets[t] ?? 0.0);
      cumulativeTarget[t] = cumTarget;
    }

    // Calculate hourly actual (non-cumulative)
    Map<String, int> hourlyActual = {
      for (var t in timeSlots) t: slotTotals[t] ?? 0
    };

    // Calculate target per bar (non-cumulative)
    Map<String, double> targetPerHour = {};
    double prevCumTargetRounded = 0.0;
    for (var slot in timeSlots) {
      final cumTargetRounded = (cumulativeTarget[slot] ?? 0.0).round();
      targetPerHour[slot] =
          (cumTargetRounded - prevCumTargetRounded).toDouble();
      prevCumTargetRounded = cumTargetRounded.toDouble();
    }

    // Calculate max values for charts
    final double barMax = [
      hourlyActual.values
          .fold<double>(0.0, (prev, v) => v > prev ? v.toDouble() : prev),
      targetPerHour.values.fold<double>(0.0, (prev, v) => v > prev ? v : prev),
    ].fold<double>(0.0, (prev, v) => v > prev ? v : prev);

    final double cumulativeTargetMax = cumulativeTarget.values
        .fold<double>(0.0, (prev, v) => v > prev ? v : prev);
    final double cumulativeActualMax = cumulativeActual.values
        .fold<double>(0.0, (prev, v) => v > prev ? v.toDouble() : prev);
    final double lineChartMax = (cumulativeTargetMax > cumulativeActualMax
            ? cumulativeTargetMax
            : cumulativeActualMax)
        .clamp(10.0, double.infinity);

    final double chartMax = (barMax * 1.2).clamp(10.0, double.infinity);
    const double barWidth = 26.0;
    const double barsSpace = 4.5;
    const double labelFontSize = 13.0;

    // Build bar groups
    final barGroups = timeSlots.asMap().entries.map((e) {
      final slot = e.value;
      return BarChartGroupData(
        x: e.key + 1,
        barsSpace: barsSpace,
        barRods: [
          BarChartRodData(
            toY: targetPerHour[slot] ?? 0.0,
            color: Colors.red,
            width: barWidth,
            borderRadius: BorderRadius.circular(2),
          ),
          BarChartRodData(
            toY: hourlyActual[slot]?.toDouble() ?? 0.0,
            color: Colors.blue,
            width: barWidth,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      );
    }).toList();

    // Build line chart spots
    final lineSpots = [
      FlSpot(-0.5, 0),
      ...timeSlots.asMap().entries.map((entry) {
        return FlSpot(entry.key.toDouble(),
            cumulativeActual[entry.value]?.toDouble() ?? 0.0);
      }),
    ];

    final targetLineSpots = [
      FlSpot(-0.5, 0),
      ...timeSlots.asMap().entries.map((entry) {
        return FlSpot(
            entry.key.toDouble(), cumulativeTarget[entry.value] ?? 0.0);
      }),
    ];

    return Card(
      elevation: 4,
      margin: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(line, processes),
          SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Legend
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildLegendDot(Colors.blue, 'Aktual per jam'),
                      const SizedBox(width: 8),
                      _buildLegendDot(Colors.red, 'Target per jam'),
                      const SizedBox(width: 8),
                      _buildLegendDot(Colors.black, 'Aktual Akumulatif',
                          isLine: true),
                      const SizedBox(width: 8),
                      _buildLegendDot(Colors.black, 'Target Akumulatif',
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
                      final int n = timeSlots.length;
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
                                    if (idx < 0 || idx >= timeSlots.length)
                                      return const SizedBox();
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: SizedBox(
                                        width: slotWidth,
                                        child: Text(
                                          timeSlots[idx],
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: Colors.blue.shade700,
                                              fontSize: 13),
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
                                    style: TextStyle(
                                        color: Colors.blue.shade700,
                                        fontSize: 13),
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
                                        ((value / chartMax) * lineChartMax)
                                            .round();
                                    return Text(cv.toString(),
                                        style: TextStyle(
                                            color: Colors.blue.shade700,
                                            fontSize: 13));
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

                        // Line overlay
                        Positioned(
                          top: topPadding,
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LineChart(
                            LineChartData(
                              minX: -0.5,
                              maxX: (timeSlots.length - 1).toDouble() + 0.5,
                              minY: -(lineChartMax * 0.06),
                              maxY: lineChartMax,
                              lineBarsData: [
                                LineChartBarData(
                                  spots: lineSpots,
                                  isCurved: false,
                                  barWidth: 2,
                                  color: Colors.black,
                                  dotData: FlDotData(show: true),
                                ),
                                LineChartBarData(
                                  spots: targetLineSpots,
                                  isCurved: false,
                                  barWidth: 2,
                                  color: Colors.black,
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
                        ...(timeSlots.asMap().entries.expand((entry) {
                          final index = entry.key;
                          final slot = entry.value;
                          final actualValue =
                              hourlyActual[slot]?.toDouble() ?? 0.0;
                          final targetValue = targetPerHour[slot] ?? 0.0;
                          final double rawCumulativeValue =
                              cumulativeActual[slot]?.toDouble() ?? 0.0;
                          final double rawCumulativeTargetValue =
                              cumulativeTarget[slot] ?? 0.0;

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
                              targetBarTop + targetBarPx - labelFontSize - 3;
                          final double actualLabelTop =
                              actualBarTop + actualBarPx - labelFontSize - 3;

                          final double actualLabelTopClamped = actualLabelTop
                              .clamp(actualBarTop, totalHeight - 20.0);

                          const double selisihLabelHeight =
                              labelFontSize - 2 + 3;
                          double selisihTop =
                              actualLabelTopClamped - selisihLabelHeight - 1.0;
                          if (selisihTop < topPadding) selisihTop = topPadding;
                          final double selisihBottom =
                              selisihTop + selisihLabelHeight;

                          const double cumulativeLabelCardHeight =
                              labelFontSize * 3 + 12;
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
                                      (rawCumulativeValue - lineMinY) /
                                          lineRangeY);

                          final double highestLinePx =
                              targetLinePx < actualLinePx
                                  ? targetLinePx
                                  : actualLinePx;

                          double cumulativeLabelTop =
                              highestLinePx - cumulativeLabelCardHeight - 6;
                          cumulativeLabelTop = cumulativeLabelTop.clamp(
                              0.0, totalHeight - cumulativeLabelCardHeight);

                          final double cardBottom =
                              cumulativeLabelTop + cumulativeLabelCardHeight;
                          if (cumulativeLabelTop < selisihBottom &&
                              cardBottom > selisihTop) {
                            final double candidateTop =
                                selisihTop - cumulativeLabelCardHeight - 4;
                            if (candidateTop >= 0) {
                              cumulativeLabelTop = candidateTop;
                            } else {
                              final double belowCandidate = highestLinePx + 4;
                              final double maxTop =
                                  totalHeight - cumulativeLabelCardHeight;
                              cumulativeLabelTop =
                                  belowCandidate.clamp(0.0, maxTop);
                            }
                          }

                          return [
                            // Label TARGET
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

                            // Label ACTUAL
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

                            // Label SELISIH
                            if (actualValue > 0 || targetValue > 0)
                              Positioned(
                                left: actualBarCenterX - barWidth / 2 - 3,
                                top: selisihTop,
                                width: barWidth + 6,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 2, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: (actualValue.toInt() -
                                                  targetValue.round()) >=
                                              0
                                          ? Colors.green.withOpacity(0.85)
                                          : Colors.red.withOpacity(0.85),
                                      borderRadius: BorderRadius.circular(3),
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
                                        fontSize: labelFontSize - 2,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            // Card AKUMULATIF
                            Positioned(
                              left: groupCenterX - 28,
                              top: cumulativeLabelTop,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5.0, vertical: 2.0),
                                decoration: BoxDecoration(
                                  color: Colors.yellow.withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(5.0),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'T:${rawCumulativeTargetValue.round()}',
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: labelFontSize - 1,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'A:${(cumulativeActual[slot] ?? 0)}',
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: labelFontSize - 1,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      () {
                                        final diff = (cumulativeActual[slot] ??
                                                0) -
                                            rawCumulativeTargetValue.round();
                                        return 'S:${diff >= 0 ? '+$diff' : '$diff'}';
                                      }(),
                                      style: TextStyle(
                                        color: (() {
                                          final diff =
                                              (cumulativeActual[slot] ?? 0) -
                                                  rawCumulativeTargetValue
                                                      .round();
                                          return diff >= 0
                                              ? const Color(0xFF00A000)
                                              : const Color(0xFFCC0000);
                                        })(),
                                        fontSize: labelFontSize - 1,
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
            ),
          ),
        ],
      ),
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
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(color: Colors.blue.shade700, fontSize: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        title: const Text('Home'),
        centerTitle: true,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
            ),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh, size: 22),
              tooltip: 'Refresh Data',
              onPressed: () {
                if (_isSlideshowRunning) {
                  loadData();
                } else {
                  _refreshCurrentLineData();
                }
              },
            ),
          ),
        ],
      ),
      body: isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.blue.shade100, blurRadius: 16)],
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Loading Production Data...',
                    style: TextStyle(
                      color: Colors.blue.shade800,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          : lineData.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.warning, size: 48, color: Colors.orange),
                      SizedBox(height: 16),
                      Text(
                        "No Data Available for Selected Date",
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _selectDate(context),
                        child: Text("Select Date"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: lineData.length,
                        onPageChanged: (int page) {
                          setState(() {
                            _currentPage = page;
                            if (!_isSlideshowRunning) {
                              _pausedLine = lineData.keys.elementAt(page);
                            }
                          });
                          _resetTimer();
                        },
                        itemBuilder: (context, index) {
                          String line = lineData.keys.elementAt(index);
                          return buildLineChart(
                            line,
                            lineData[line]!,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List<Widget>.generate(lineData.length, (int index) {
                          final isActive = _currentPage == index;
                          final line = lineData.keys.elementAt(index);
                          return GestureDetector(
                            onTap: () => _goToPage(index),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              width: isActive ? 40 : 28,
                              height: 28,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: isActive ? Colors.blue.shade700 : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Center(
                                child: Text(
                                  'L$line',
                                  style: TextStyle(
                                    color: isActive ? Colors.white : Colors.grey.shade600,
                                    fontSize: 11,
                                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
    );
  }
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
      canvas.drawLine(Offset(0, size.height / 2),
          Offset(size.width, size.height / 2), paint);
    } else {
      double x = 0;
      while (x < size.width) {
        canvas.drawLine(
            Offset(x, size.height / 2),
            Offset(x + 4 <= size.width ? x + 4 : size.width, size.height / 2),
            paint);
        x += 8;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}