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
  bool _showLeftArrow = false;
  bool _showRightArrow = false;
  bool _isSlideshowRunning = true;
  String? _pausedLine;
  Map<String, double> _dailyTargets = {};
  Map<String, Map<String, double>> _hourlyTargets = {};
  Map<String, StreamSubscription> _streamSubscriptions = {};

  // Updated time slots to match counter_table_screen.dart
  final List<String> timeSlots = [
    "08:30", "09:30", "10:30", "11:30", "13:30", 
    "14:30", "15:30", "16:30", "17:55", "18:55", "19:55",
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
    if (!_isSlideshowRunning || !_pageController.hasClients || lineData.isEmpty) return;
    
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
          bool processExists = newData.any((p) => p['process_name'] == currentProcessName);
          selectedProcesses[currentLine] = processExists ? currentProcessName : newData.last['process_name'];
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
      final docRef = FirebaseFirestore.instance.collection('counter_sistem').doc(date);
      final doc = await docRef.get();
      
      if (doc.exists) {
        final data = doc.data()!;
        final targetMap = data['target_map_$line'] as Map<String, dynamic>? ?? {};

        // Inisialisasi hourly targets
        Map<String, double> calculatedHourlyTargets = {
          '08:30': 0.0,
          '09:30': 0.0,
          '10:30': 0.0,
          '11:30': 0.0,
          '13:30': 0.0,
          '14:30': 0.0,
          '15:30': 0.0,
          '16:30': 0.0,
          '17:55': 0.0,
          '18:55': 0.0,
          '19:55': 0.0,
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
                'time_perpcs': (value['time_perpcs'] as num?)?.toDouble() ?? 0.0,
              });
            }
          });

          // Urutkan styles berdasarkan key (style1, style2, dll)
          styles.sort((a, b) => a['key'].compareTo(b['key']));

          // Hitung target per jam untuk style normal (08:30 - 16:30)
          // Alokasi berbasis detik per slot sehingga sisa waktu di slot dapat dipakai oleh style berikutnya
          List<String> normalTimeSlots = ['08:30', '09:30', '10:30', '11:30', '13:30', '14:30', '15:30', '16:30'];
          int currentTimeSlotIndex = 0;

          final Map<String, double> slotRemainingSeconds = { for (var s in normalTimeSlots) s: 3600.0 };

          for (var style in styles) {
            double remainingQuantity = style['quantity'];
            double timePerPcs = style['time_perpcs'];

            if (timePerPcs <= 0) continue;

            while (remainingQuantity > 0 && currentTimeSlotIndex < normalTimeSlots.length) {
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

              final allocated = possiblePieces >= remainingQuantity ? remainingQuantity : possiblePieces;

              calculatedHourlyTargets[currentTimeSlot] = (calculatedHourlyTargets[currentTimeSlot] ?? 0.0) + allocated;
              remainingQuantity -= allocated;
              totalDailyTarget += allocated;

              slotSec -= allocated * timePerPcs;
              slotRemainingSeconds[currentTimeSlot] = slotSec;

              if (slotSec <= 1e-9) currentTimeSlotIndex++;
            }

            if (remainingQuantity > 0 && currentTimeSlotIndex >= normalTimeSlots.length) {
              break;
            }
          }

          // Hitung overtime (sama: gunakan sisa detik per slot overtime)
          if (targetMap.containsKey('overtime')) {
            final overtimeData = targetMap['overtime'] as Map<String, dynamic>;
            double overtimeQuantity = (overtimeData['quantity'] as num?)?.toDouble() ?? 0.0;
            double overtimeTimePerPcs = (overtimeData['time_perpcs'] as num?)?.toDouble() ?? 0.0;

            if (overtimeTimePerPcs > 0 && overtimeQuantity > 0) {
              List<String> overtimeTimeSlots = ['17:55', '18:55', '19:55'];
              double remainingOvertime = overtimeQuantity;
              final Map<String, double> overtimeSlotSec = { for (var s in overtimeTimeSlots) s: 3600.0 };
              int otIndex = 0;
              while (remainingOvertime > 0 && otIndex < overtimeTimeSlots.length) {
                final slot = overtimeTimeSlots[otIndex];
                double slotSec = overtimeSlotSec[slot] ?? 3600.0;
                if (slotSec <= 1e-9) { otIndex++; continue; }

                final possiblePieces = slotSec / overtimeTimePerPcs;
                if (possiblePieces <= 1e-9) { otIndex++; continue; }

                final allocated = possiblePieces >= remainingOvertime ? remainingOvertime : possiblePieces;
                calculatedHourlyTargets[slot] = (calculatedHourlyTargets[slot] ?? 0.0) + allocated;
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
            double targetPerHour = totalDailyTarget / 8;
            
            calculatedHourlyTargets = {
              '08:30': targetPerHour,
              '09:30': targetPerHour,
              '10:30': targetPerHour,
              '11:30': targetPerHour,
              '13:30': targetPerHour,
              '14:30': targetPerHour,
              '15:30': targetPerHour,
              '16:30': targetPerHour,
              '17:55': 0.0,
              '18:55': 0.0,
              '19:55': 0.0,
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

  void _goToPreviousPage() {
    if (!_pageController.hasClients) return;
    
    if (_currentPage > 0) {
      _currentPage--;
    } else {
      _currentPage = lineData.length - 1;
    }
    _pageController.animateToPage(
      _currentPage,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    _resetTimer();
  }

  void _goToNextPage() {
    if (!_pageController.hasClients) return;
    
    if (_currentPage < lineData.length - 1) {
      _currentPage++;
    } else {
      _currentPage = 0;
    }
    _pageController.animateToPage(
      _currentPage,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    _resetTimer();
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

  Future<List<Map<String, dynamic>>> fetchLineData(String line, String date) async {
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
      final contractCollections = kontrakArray.isEmpty ? ['Process'] : kontrakArray.map((e) => e.toString()).toList();

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
            if (key != 'sequence' && key != 'belumKensa' && key != 'stock_20min' && key != 'stock_pagi' && key != 'part' && value is Map<String, dynamic>) {
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
                cumulativeData[mappedTime] = (cumulativeData[mappedTime] ?? 0) + slotTotal;
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
      processList.sort((a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int));
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
        final contractCollections = kontrakArray.isEmpty ? ['Process'] : kontrakArray.map((e) => e.toString()).toList();

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
              print('Error updating data from stream for $line/$contractName: $e');
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

    final currentLineBeforeRefresh = _pausedLine ?? (_currentPage < lineData.length ? lineData.keys.elementAt(_currentPage) : null);
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
          bool processExists = data.any((p) => p['process_name'] == selectedProcesses[line]);
          newSelectedProcesses[line] = processExists
              ? selectedProcesses[line]
              : lastName;
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
          if (currentLineBeforeRefresh != null && lineData.containsKey(currentLineBeforeRefresh)) {
            _currentPage = lineData.keys.toList().indexOf(currentLineBeforeRefresh);
          } 
          else if (currentPageBeforeRefresh < lineData.length) {
            _currentPage = currentPageBeforeRefresh;
          } 
          else {
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

    final displayValue = (currentProcess != null && names.contains(currentProcess))
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
                tooltip: _isSlideshowRunning ? 'Pause Slideshow' : 'Resume Slideshow',
              ),
              SizedBox(width: 8),
              TextButton(
                onPressed: () => _selectDate(context),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, size: 16, color: Colors.blue.shade700),
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
    // slotTotals holds total (non-cumulative) per time slot
    final Map<String, int> slotTotals = { for (var t in timeSlots) t: 0 };
    // rawDataAggregated maps originalTimeKey -> aggregated machine map { '1': sum, '2': sum, ... }
    final Map<String, Map<String, int>> rawDataAggregated = {};

    for (var p in processes) {
      if (p['process_name'] != currentProcessName) continue;
      final raw = p['raw_data'] as Map<String, dynamic>? ?? {};

      raw.forEach((key, value) {
        if (key == 'sequence' || key == 'belumKensa' || key == 'stock_20min' || key == 'stock_pagi' || key == 'part') return;
        if (value is! Map<String, dynamic>) return;
        final mapped = timeRangeMap[key];
        if (mapped == null) return;

        int slotSum = 0;
        for (int i = 1; i <= 5; i++) {
          final cnt = value['$i'];
          final int c = cnt is num ? cnt.toInt() : int.tryParse(cnt.toString()) ?? 0;
          slotSum += c;

          rawDataAggregated.putIfAbsent(key, () => {});
          rawDataAggregated[key]![ '$i' ] = (rawDataAggregated[key]![ '$i' ] ?? 0) + c;
        }

        slotTotals[mapped] = (slotTotals[mapped] ?? 0) + slotSum;
      });
    }

    // Build cumulative data from slotTotals
    Map<String, int> cumulative = {};
    int running = 0;
    for (var t in timeSlots) {
      running += (slotTotals[t] ?? 0);
      cumulative[t] = running;
    }

    double? dailyTarget = _dailyTargets[line];
    Map<String, double>? hourlyTargets = _hourlyTargets[line];

    List<FlSpot> spots = [];
    List<FlSpot> targetSpots = [];
    double maxY = 0;

    // Add initial spot at 0
    spots.add(FlSpot(0, 0));
    if (dailyTarget != null) {
      targetSpots.add(FlSpot(0, 0));
    }

    // Calculate cumulative target for each time slot
    double cumulativeTarget = 0.0;
    
    if (dailyTarget != null && hourlyTargets != null) {
      // Add spots for target line
      for (int i = 0; i < timeSlots.length; i++) {
        String time = timeSlots[i];
        cumulativeTarget += (hourlyTargets[time] ?? 0.0);
        targetSpots.add(FlSpot((i+1).toDouble(), cumulativeTarget));
      }
    }

    // Add spots for each time slot (use cumulative values)
    for (int i = 0; i < timeSlots.length; i++) {
      String time = timeSlots[i];
      int value = cumulative[time] ?? 0;
      spots.add(FlSpot((i+1).toDouble(), value.toDouble()));
      
      if (value > maxY) maxY = value.toDouble();
      if (dailyTarget != null && cumulativeTarget > maxY) maxY = cumulativeTarget;
    }

    if (maxY == 0) maxY = 10;

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
              padding: const EdgeInsets.only(bottom: 24.0, left: 24.0, right: 24.0),
              child: MouseRegion(
                onEnter: (_) => setState(() {
                  _showLeftArrow = true;
                  _showRightArrow = true;
                }),
                onExit: (_) => setState(() {
                  _showLeftArrow = false;
                  _showRightArrow = false;
                }),
                child: Stack(
                  children: [
                    LineChart(
                      LineChartData(
                        lineTouchData: LineTouchData(
                          enabled: true,
                          touchTooltipData: LineTouchTooltipData(
                            tooltipPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                            tooltipRoundedRadius: 6,
                            getTooltipItems: (List<LineBarSpot> touchedSpots) {
                              // Build a tooltip text for each distinct x, then return
                              // one LineTooltipItem per touched spot (mapping to its x's text).
                              final Map<double, String> tooltipByX = {};

                              // Prepare grouped data per x
                              final Map<double, List<LineBarSpot>> groups = {};
                              for (final spot in touchedSpots) {
                                groups.putIfAbsent(spot.x, () => []).add(spot);
                              }

                              groups.forEach((x, spotsAtX) {
                                final timeIndex = x.toInt() - 1;
                                final timeSlot = timeIndex >= 0 && timeIndex < timeSlots.length
                                    ? timeSlots[timeIndex]
                                    : 'Start';

                                // We only want to show: Time, Target (if any), and a single
                                // Total line. Do not show per-machine ('Mesin') lines.
                                String tooltipText = '$timeSlot\n';

                                // Add Target line(s) first
                                for (final spot in spotsAtX) {
                                  final isTarget = spot.barIndex == 1;
                                  if (isTarget) {
                                    tooltipText += 'Target: ${spot.y.toInt()}\n';
                                  }
                                }

                                // Compute a single Total value: take the maximum y among
                                // non-target spots (if none, show 0)
                                int totalVal = 0;
                                for (final spot in spotsAtX) {
                                  final isTarget = spot.barIndex == 1;
                                  if (!isTarget) {
                                    final int val = spot.y.toInt();
                                    if (val > totalVal) totalVal = val;
                                  }
                                }
                                tooltipText += 'Total: $totalVal\n';

                                tooltipByX[x] = tooltipText.trim();
                              });

                              // Map back to touchedSpots so the returned list length matches
                              // touchedSpots (this is expected by fl_chart). Only the
                              // first spot for a given x will contain the tooltip text;
                              // subsequent spots at the same x return an invisible item
                              // to avoid duplicate blocks.
                              final seenX = <double>{};
                              return touchedSpots.map((spot) {
                                final isFirstForX = !seenX.contains(spot.x);
                                if (isFirstForX) seenX.add(spot.x);

                                if (isFirstForX) {
                                  final text = tooltipByX[spot.x] ?? '';
                                  return LineTooltipItem(
                                    text,
                                    TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  );
                                } else {
                                  // Return a zero-height transparent item so it doesn't
                                  // increase the tooltip card height.
                                  return LineTooltipItem(
                                    '',
                                    TextStyle(
                                      color: Colors.transparent,
                                      fontSize: 0,
                                      height: 0,
                                    ),
                                  );
                                }
                              }).toList();
                            },
                          ),
                        ),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: true,
                          horizontalInterval: maxY > 10 ? (maxY / 5) : 2,
                          verticalInterval: 1,
                        ),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, _) {
                                if (value != value.toInt()) return SizedBox();
                                if (value.toInt() < 1 || value.toInt() > timeSlots.length) return SizedBox();
                                String timeLabel = timeSlots[value.toInt() - 1];
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    timeLabel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              },
                              interval: 1,
                              reservedSize: 30,
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              interval: maxY > 10 ? (maxY / 5) : 2,
                              getTitlesWidget: (value, _) => Text(
                                value.toInt().toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(
                          show: true,
                          border: Border.all(
                            color: Colors.blue.shade200,
                            width: 1,
                          ),
                        ),
                        minX: 0,
                        maxX: timeSlots.length.toDouble(),
                        minY: 0,
                        maxY: maxY * 1.1,
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: false,
                            color: Colors.blueAccent,
                            barWidth: 4,
                            isStrokeCapRound: true,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (spot, percent, barData, index) =>
                                FlDotCirclePainter(
                                  radius: 4,
                                  color: Colors.blue.shade700,
                                  strokeWidth: 2,
                                  strokeColor: Colors.white,
                                ),
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                colors: [
                                  Colors.blueAccent.withOpacity(0.3),
                                  Colors.blueAccent.withOpacity(0.1),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                          if (dailyTarget != null)
                            LineChartBarData(
                              spots: targetSpots,
                              isCurved: false,
                              color: Colors.red,
                              barWidth: 2,
                              isStrokeCapRound: true,
                              dotData: FlDotData(show: false),
                              dashArray: [5, 5],
                            ),
                        ],
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: _showLeftArrow ? 1.0 : 0.0,
                      duration: Duration(milliseconds: 200),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          margin: EdgeInsets.only(left: 8),
                          child: IconButton(
                            icon: Icon(Icons.chevron_left, size: 36),
                            onPressed: _goToPreviousPage,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: _showRightArrow ? 1.0 : 0.0,
                      duration: Duration(milliseconds: 200),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          margin: EdgeInsets.only(right: 8),
                          child: IconButton(
                            icon: Icon(Icons.chevron_right, size: 36),
                            onPressed: _goToNextPage,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                    ),
                  ],
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
    return Scaffold(
      backgroundColor: Colors.blue.shade50,
      appBar: AppBar(
        title: Text(
          "Home",
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
            onPressed: () {
              if (_isSlideshowRunning) {
                loadData();
              } else {
                _refreshCurrentLineData();
              }
            },
            splashRadius: 24,
          ),
        ],
      ),
      body: isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    "Loading Production Data...",
                    style: TextStyle(
                      color: Colors.blue.shade800,
                      fontSize: 16,
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
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List<Widget>.generate(lineData.length, (int index) {
                        return GestureDetector(
                          onTap: () => _goToPage(index),
                          child: Container(
                            width: 12.0,
                            height: 12.0,
                            margin: EdgeInsets.symmetric(horizontal: 4.0),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _currentPage == index 
                                  ? Colors.blue.shade700 
                                  : Colors.grey.shade400,
                            ),
                          ),
                        );
                      }),
                    ),
                    SizedBox(height: 16),
                  ],
                ),
    );
  }
}