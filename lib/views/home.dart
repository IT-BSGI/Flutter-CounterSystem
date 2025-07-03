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
  Map<String, String> selectedProcesses = {};
  late PageController _pageController;
  int _currentPage = 0;
  Timer? _slideshowTimer;
  bool _showLeftArrow = false;
  bool _showRightArrow = false;
  bool _isSlideshowRunning = true;
  String? _pausedLine;
  Map<String, int> _targets = {};
  Map<String, StreamSubscription> _streamSubscriptions = {};

  final List<String> timeSlots = [
    "00:00",
    "07:30 - 08:29",
    "08:30 - 09:29",
    "09:30 - 10:29",
    "10:30 - 11:29",
    "12:30 - 13:29",
    "13:30 - 14:29",
    "14:30 - 15:29",
    "15:30 - 16:29",
    "16:30~"
  ];

  final Map<String, String> timeRangeMap = {
    "07:30": "07:30 - 08:29",
    "08:30": "08:30 - 09:29",
    "09:30": "09:30 - 10:29",
    "10:30": "10:30 - 11:29",
    "12:30": "12:30 - 13:29",
    "13:30": "13:30 - 14:29",
    "14:30": "14:30 - 15:29",
    "15:30": "15:30 - 16:29",
    "16:30": "16:30~",
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
    String currentProcess = selectedProcesses[currentLine] ?? '';

    try {
      var newData = await fetchLineData(currentLine, formattedDate);
      await _fetchTarget(currentLine, formattedDate);
      
      if (mounted && newData.isNotEmpty) {
        setState(() {
          lineData[currentLine] = newData;
          bool processExists = newData.any((p) => p['process_name'] == currentProcess);
          selectedProcesses[currentLine] = processExists ? currentProcess : newData.last['process_name'];
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
      DocumentSnapshot snapshot = await FirebaseFirestore.instance
          .collection('counter_sistem')
          .doc(date)
          .get();

      if (snapshot.exists) {
        Map<String, dynamic>? data = snapshot.data() as Map<String, dynamic>?;
        int target = data?['target_$line'] as int? ?? 0;
        
        setState(() {
          _targets[line] = target;
        });
      }
    } catch (e) {
      print("Error fetching target for Line $line: $e");
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
      FirebaseFirestore firestore = FirebaseFirestore.instance;
      DocumentReference kumitateRef = firestore
          .collection('counter_sistem')
          .doc(date)
          .collection(line)
          .doc('Kumitate');

      DocumentSnapshot snapshot = await kumitateRef.get();

      if (!snapshot.exists) {
        print("No Kumitate document found for Line $line on $date");
        return [];
      }

      Map<String, dynamic>? data = snapshot.data() as Map<String, dynamic>?;
      if (data == null) return [];

      List<Map<String, dynamic>> processList = [];

      data.forEach((processName, processData) {
        if (processData is Map) {
          Map<String, int> cumulativeData = {};

          // Initialize all time slots to 0
          for (String timeSlot in timeSlots) {
            cumulativeData[timeSlot] = 0;
          }

          processData.forEach((key, value) {
            if (key != 'sequence' && value is Map) {
              String? mappedTime = timeRangeMap[key];
              if (mappedTime != null) {
                int slotTotal = 0;
                for (int i = 1; i <= 5; i++) {
                  slotTotal += ((value["$i"] ?? 0) as num).toInt();
                }
                cumulativeData[mappedTime] = (cumulativeData[mappedTime] ?? 0) + slotTotal;
              }
            }
          });

          // Create final cumulative data
          Map<String, int> finalCumulative = {};
          int currentCumulative = 0;
          
          for (String time in timeSlots) {
            if (time != "00:00") {
              currentCumulative += (cumulativeData[time] ?? 0);
            }
            finalCumulative[time] = time == "00:00" ? 0 : currentCumulative;
          }

          processList.add({
            'process_name': processName.replaceAll('_', ' '),
            'sequence': (processData['sequence'] ?? 0) as int,
            'cumulative': finalCumulative,
            'raw_data': processData,
          });
        }
      });

      // Sort by sequence
      processList.sort((a, b) => (a['sequence'] ?? 0).compareTo(b['sequence'] ?? 0));

      return processList;
    } catch (e) {
      print("Error fetching data for Line $line: $e");
      return [];
    }
  }

  void _setupStreamListeners(String date) {
    _streamSubscriptions.forEach((_, subscription) => subscription.cancel());
    _streamSubscriptions.clear();

    for (String line in ['A', 'B', 'C', 'D', 'E']) {
      final stream = FirebaseFirestore.instance
          .collection('counter_sistem')
          .doc(date)
          .collection(line)
          .doc('Kumitate')
          .snapshots();

      _streamSubscriptions[line] = stream.listen((snapshot) async {
        if (snapshot.exists && mounted) {
          String currentLine = _pausedLine ?? lineData.keys.elementAt(_currentPage);
          
          if (line == currentLine || _isSlideshowRunning) {
            var newData = await _processSnapshot(snapshot);
            
            if (mounted && newData.isNotEmpty) {
              setState(() {
                lineData[line] = newData;
              });
            }
          }
        }
      });
    }
  }

  Future<List<Map<String, dynamic>>> _processSnapshot(DocumentSnapshot snapshot) async {
    Map<String, dynamic>? data = snapshot.data() as Map<String, dynamic>?;
    if (data == null) return [];

    List<Map<String, dynamic>> processList = [];

    data.forEach((processName, processData) {
      if (processData is Map) {
        Map<String, int> cumulativeData = {};

        for (String timeSlot in timeSlots) {
          cumulativeData[timeSlot] = 0;
        }

        processData.forEach((key, value) {
          if (key != 'sequence' && value is Map) {
            String? mappedTime = timeRangeMap[key];
            if (mappedTime != null) {
              int slotTotal = 0;
              for (int i = 1; i <= 5; i++) {
                slotTotal += ((value["$i"] ?? 0) as num).toInt();
              }
              cumulativeData[mappedTime] = (cumulativeData[mappedTime] ?? 0) + slotTotal;
            }
          }
        });

        // Create final cumulative data
        Map<String, int> finalCumulative = {};
        int currentCumulative = 0;
        
        for (String time in timeSlots) {
          if (time != "00:00") {
            currentCumulative += (cumulativeData[time] ?? 0);
          }
          finalCumulative[time] = time == "00:00" ? 0 : currentCumulative;
        }

        processList.add({
          'process_name': processName.replaceAll('_', ' '),
          'sequence': (processData['sequence'] ?? 0) as int,
          'cumulative': finalCumulative,
          'raw_data': processData,
        });
      }
    });

    processList.sort((a, b) => (a['sequence'] ?? 0).compareTo(b['sequence'] ?? 0));
    return processList;
  }

  Future<void> loadData() async {
    setState(() => isLoading = true);
    
    String formattedDate = DateFormat("yyyy-MM-dd").format(selectedDate);
    Map<String, List<Map<String, dynamic>>> newData = {};
    Map<String, String> newSelectedProcesses = {};

    final currentLineBeforeRefresh = _pausedLine ?? (_currentPage < lineData.length ? lineData.keys.elementAt(_currentPage) : null);
    final currentPageBeforeRefresh = _currentPage;
    
    for (String line in ['A', 'B', 'C', 'D', 'E']) {
      var data = await fetchLineData(line, formattedDate);
      await _fetchTarget(line, formattedDate);
      if (data.isNotEmpty) {
        newData[line] = data;
        if (!selectedProcesses.containsKey(line)) {
          newSelectedProcesses[line] = data.last['process_name'];
        } else {
          bool processExists = data.any((p) => p['process_name'] == selectedProcesses[line]);
          newSelectedProcesses[line] = processExists 
              ? selectedProcesses[line]! 
              : data.last['process_name'];
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
    String currentProcess = selectedProcesses[line] ?? '';
    int? target = _targets[line];

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
                value: currentProcess,
                items: processes.map((process) {
                  return DropdownMenuItem<String>(
                    value: process['process_name'],
                    child: Text(
                      process['process_name'],
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
              if (target != null) ...[
                SizedBox(width: 16),
                Text(
                  'Target: $target',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.blue.shade800,
                  ),
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
    String currentProcess = selectedProcesses[line] ?? '';
    var processData = processes.firstWhere(
      (p) => p['process_name'] == currentProcess,
      orElse: () => processes.first,
    );
    
    Map<String, int> data = processData['cumulative'];
    int? target = _targets[line];
    Map<String, dynamic> rawData = processData['raw_data'];

    List<FlSpot> spots = [];
    List<FlSpot> targetSpots = [];
    int index = 0;
    double maxY = 0;

    // Hanya tambahkan titik 00:00 jika tidak ada data lain di index 0
    if (timeSlots.isNotEmpty) {
      spots.add(FlSpot(0, 0)); // Titik awal di 00:00 dengan nilai 0
      if (target != null) {
        targetSpots.add(FlSpot(0, 0));
      }
      index++; // Langsung ke index berikutnya
    }

    // Hitung jumlah time slot yang valid (hingga 15:30-16:29)
    int validTimeSlotsCount = timeSlots.indexWhere((slot) => slot == "15:30 - 16:29") + 1;
    if (validTimeSlotsCount <= 0) validTimeSlotsCount = timeSlots.length;

    // Mulai dari index 1 untuk melewati 00:00
    for (String time in timeSlots.skip(1)) {
      int value = data[time] ?? 0;
      spots.add(FlSpot(index.toDouble(), value.toDouble()));
      
      if (target != null) {
        // Hanya tambahkan target spot jika masih dalam range waktu yang valid
        if (index < validTimeSlotsCount) {
          double targetValue = (target * index / (validTimeSlotsCount - 1));
          targetSpots.add(FlSpot(index.toDouble(), targetValue));
        }
      }
      
      if (value > maxY) maxY = value.toDouble();
      if (target != null && target > maxY) maxY = target.toDouble();
      index++;
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
                            getTooltipItems: (List<LineBarSpot> touchedSpots) {
                              return touchedSpots.map((spot) {
                                final isTarget = spot.barIndex == 1;
                                final timeSlot = timeSlots[spot.x.toInt()];
                                
                                String? originalTimeKey;
                                timeRangeMap.forEach((key, value) {
                                  if (value == timeSlot) {
                                    originalTimeKey = key;
                                  }
                                });
                                
                                Map<String, dynamic>? machineData;
                                if (originalTimeKey != null && rawData.containsKey(originalTimeKey)) {
                                  machineData = rawData[originalTimeKey];
                                }
                                
                                String tooltipText = '$timeSlot\n';
                                
                                if (isTarget) {
                                  tooltipText += 'Target: ${spot.y.toInt()}\n';
                                } else {
                                  tooltipText += 'Total: ${spot.y.toInt()}\n';
                                  
                                  if (machineData != null) {
                                    for (int i = 1; i <= 5; i++) {
                                      if (machineData.containsKey('$i') && machineData['$i'] != 0) {
                                        tooltipText += 'Mesin $i: ${machineData['$i']}\n';
                                      }
                                    }
                                  }
                                }
                                
                                return LineTooltipItem(
                                  tooltipText.trim(),
                                  TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
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
                                if (value.toInt() >= timeSlots.length) return SizedBox();
                                String timeLabel = value.toInt() == 0 
                                    ? "00:00" 
                                    : timeSlots[value.toInt()].split(' ')[0];
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    timeLabel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                );
                              },
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
                        maxX: (timeSlots.length - 1).toDouble(),
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
                          if (target != null)
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