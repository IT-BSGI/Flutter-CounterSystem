import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';

class CounterTableScreen extends StatefulWidget {
  @override
  _CounterTableScreenState createState() => _CounterTableScreenState();
}

class _CounterTableScreenState extends State<CounterTableScreen> {
  List<PlutoColumn> kumitateColumns = [];
  List<PlutoRow> kumitateRows = [];
  List<PlutoColumnGroup> kumitateColumnGroups = [];
  
  List<PlutoColumn> partColumns = [];
  List<PlutoRow> partRows = [];
  
  bool isLoading = true;
  String selectedLine = "A";
  DateTime selectedDate = DateTime.now();
  List<Map<String, dynamic>> kumitateData = [];
  List<Map<String, dynamic>> partData = [];
  int? dailyTarget;
  Map<String, int> hourlyTargets = {};
  bool isTargetLoading = true;
  bool isSaving = false;
  bool noDataAvailable = false;

  PlutoGridStateManager? _kumitateStateManager;
  PlutoGridStateManager? _partStateManager;

  final List<String> timeSlots = [
    "08:30", "09:30", "10:30", "11:30", "13:30", 
    "14:30", "15:30", "16:30", "OT"
  ];

  final Map<String, String> timeRangeMap = {
    "06:30": "08:30", "07:30": "08:30", "08:30": "09:30",
    "09:30": "10:30", "10:30": "11:30", "11:30": "13:30",
    "12:30": "13:30", "13:30": "14:30", "14:30": "15:30",
    "15:30": "16:30", "16:30": "OT", "17:30": "OT",
    "18:30": "OT", "19:30": "OT",
  };

  final List<String> partProcessOrder = [
    "Maemi IN", "Maemi OUT", "Ushiro IN", "Ushiro OUT",
    "Eri IN", "Eri OUT", "Sode IN", "Sode OUT",
    "Cuff IN", "Cuff OUT",
  ];

  // List of processes that should be divided by 2 (for hourly data only)
  final List<String> dividedByTwoProcesses = [
    "Cuff IN", "Cuff OUT", "Sode IN", "Sode OUT"
  ];

  @override
  void initState() {
    super.initState();
    loadData();
    _loadTargets();
  }

  Future<void> _loadTargets() async {
    setState(() => isTargetLoading = true);
    
    final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
    final docRef = FirebaseFirestore.instance.collection('counter_sistem').doc(dateStr);

    try {
      final doc = await docRef.get();
      if (doc.exists) {
        setState(() {
          final target = doc.data()?['target_$selectedLine'];
          dailyTarget = target is int ? target : target?.toInt();
          if (dailyTarget != null) {
            hourlyTargets = {
              '08:30': (dailyTarget! ~/ 8), '09:30': (dailyTarget! ~/ 8),
              '10:30': (dailyTarget! ~/ 8), '11:30': (dailyTarget! ~/ 8),
              '13:30': (dailyTarget! ~/ 8), '14:30': (dailyTarget! ~/ 8),
              '15:30': (dailyTarget! ~/ 8), '16:30': (dailyTarget! ~/ 8),
              'OT': 0,
            };
          }
        });
      } else {
        setState(() {
          dailyTarget = null;
          hourlyTargets = {};
        });
      }
    } catch (e) {
      print('Error loading targets: $e');
    } finally {
      setState(() => isTargetLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> fetchCounterData(String date, String line, String type) async {
    try {
      final processRef = FirebaseFirestore.instance
          .collection('counter_sistem')
          .doc(date)
          .collection(line)
          .doc(type)
          .collection('Process');

      final snapshot = await processRef.get();

      if (snapshot.docs.isEmpty) {
        print('No process documents found for Line $line $type on $date');
        return [];
      }

      List<Map<String, dynamic>> processList = [];
      final maxLines = type == 'Part' ? 2 : 5;

      for (var doc in snapshot.docs) {
        final processData = doc.data();
        final processMap = <String, dynamic>{
          "process_name": doc.id.replaceAll('_', ' '),
          "sequence": (processData['sequence'] as num?)?.toInt() ?? 0,
          "belumKensa": processData['belumKensa'] is String 
              ? int.tryParse(processData['belumKensa'] as String) ?? 0
              : (processData['belumKensa'] as num?)?.toInt() ?? 0,
          "stock_15min": processData['stock_15min'] is String 
              ? int.tryParse(processData['stock_15min'] as String) ?? 0
              : (processData['stock_15min'] as num?)?.toInt() ?? 0,
          "stock_pagi": processData['stock_pagi'] ?? {
            '1': 0, '2': 0, '3': 0, '4': 0, 'total': 0
          },
          "type": type,
          "raw_data": processData,
        };

        Map<String, int> cumulativeData = {};
        for (final time in timeSlots) {
          cumulativeData[time] = 0;
        }

        processData.forEach((key, value) {
          if (key != 'sequence' && key != 'belumKensa' && key != 'stock_15min' && key != 'stock_pagi' && value is Map<String, dynamic>) {
            final timeKey = key;
            final mappedTime = timeRangeMap[timeKey];
            
            if (mappedTime != null) {
              int slotTotal = 0;
              for (int i = 1; i <= maxLines; i++) {
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

        Map<String, int> finalCumulative = {};
        int currentCumulative = 0;
        
        for (String time in timeSlots) {
          currentCumulative += (cumulativeData[time] ?? 0);
          finalCumulative[time] = currentCumulative;
          processMap["${time}_cumulative"] = currentCumulative;
        }

        for (final time in timeSlots) {
          for (int i = 1; i <= maxLines; i++) {
            processMap["${time}_$i"] = 0;
          }
        }

        processData.forEach((key, value) {
          if (key != 'sequence' && key != 'belumKensa' && key != 'stock_15min' && key != 'stock_pagi' && value is Map<String, dynamic>) {
            final timeKey = key;
            final mappedTime = timeRangeMap[timeKey];
            
            if (mappedTime != null) {
              for (int i = 1; i <= maxLines; i++) {
                final dynamic countValue = value['$i'];
                final int count = countValue is num 
                    ? countValue.toInt() 
                    : int.tryParse(countValue.toString()) ?? 0;
                processMap["${mappedTime}_$i"] = (processMap["${mappedTime}_$i"] as int) + count;
              }
            }
          }
        });

        processList.add(processMap);
      }

      if (type == 'Part') {
        processList.sort((a, b) {
          final aIndex = partProcessOrder.indexOf(a['process_name']);
          final bIndex = partProcessOrder.indexOf(b['process_name']);
          return aIndex.compareTo(bIndex);
        });
      } else {
        processList.sort((a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int));
      }

      return processList;
    } catch (e) {
      print('Error fetching $type counter data: $e');
      return [];
    }
  }

  void _buildKumitateColumnsAndRows() {
    kumitateColumns = [
      PlutoColumn(
        title: "PROCESS",
        field: "process_name",
        type: PlutoColumnType.text(),
        width: 230,
        titleTextAlign: PlutoColumnTextAlign.center,
        backgroundColor: Colors.blue.shade300,
        enableColumnDrag: false,
        enableContextMenu: false,
        enableSorting: false,
        enableEditingMode: false,
        renderer: (ctx) {
          final processName = ctx.cell.value.toString();
          return Row(
            children: [
              Expanded(child: Text(processName)),
              IconButton(
                icon: Icon(Icons.bar_chart, size: 18, color: Colors.blue),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text('Grafik $processName (Kumitate)'),
                    content: Container(
                      width: 1100,
                      height: 900,
                      child: buildChart(processName, 'Kumitate'),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text("Tutup"),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      PlutoColumn(
        title: "Stock 15 menit",
        field: "stock_15min",
        type: PlutoColumnType.text(),
        width: 130,
        titleTextAlign: PlutoColumnTextAlign.center,
        textAlign: PlutoColumnTextAlign.center,
        backgroundColor: Colors.blue.shade300,
        enableColumnDrag: false,
        enableDropToResize: false,
        enableContextMenu: false,
        enableEditingMode: true,
        enableSorting: false,
        applyFormatterInEditing: true,
        formatter: (value) {
          if (value == null) return '0';
          final strValue = value is String ? value : value.toString();
          final numericOnly = strValue.replaceAll(RegExp(r'[^0-9]'), '');
          return numericOnly.isEmpty ? '0' : numericOnly;
        },
        renderer: (rendererContext) {
          if (rendererContext.stateManager.isEditing && 
              rendererContext.stateManager.currentCell == rendererContext.cell) {
            return Padding(
              padding: EdgeInsets.all(2),
              child: TextField(
                controller: TextEditingController(
                  text: rendererContext.cell.value.toString()
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8),
                ),
                onChanged: (value) {
                  final intValue = int.tryParse(value) ?? 0;
                  rendererContext.stateManager.changeCellValue(
                    rendererContext.cell,
                    intValue,
                    notify: false,
                  );
                },
                onEditingComplete: () {
                  if (mounted) setState(() {});
                  rendererContext.stateManager.notifyListeners();
                },
              ),
            );
          }
          return Container(
            padding: EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            child: Text(
              rendererContext.cell.value.toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        },
      ),
      // Stock Pagi Columns
      for (int i = 1; i <= 4; i++)
        PlutoColumn(
          title: "$i",
          field: "stock_pagi_$i",
          type: PlutoColumnType.number(),
          width: 40,
          titleTextAlign: PlutoColumnTextAlign.center,
          textAlign: PlutoColumnTextAlign.center,
          backgroundColor: Colors.blue.shade200,
          enableColumnDrag: false,
          enableContextMenu: false,
          enableDropToResize: false,
          enableSorting: false,
          enableEditingMode: true,
          cellPadding: EdgeInsets.zero,
          renderer: (rendererContext) {
            final value = rendererContext.cell.value as int;
            return Container(
              height: 30,
              alignment: Alignment.center,
              child: Text(
                value.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          },
        ),
      PlutoColumn(
        title: "Total",
        field: "stock_pagi_total",
        type: PlutoColumnType.number(),
        width: 60,
        titleTextAlign: PlutoColumnTextAlign.center,
        textAlign: PlutoColumnTextAlign.center,
        backgroundColor: Colors.yellow.shade200,
        enableColumnDrag: false,
        enableContextMenu: false,
        enableDropToResize: false,
        enableSorting: false,
        enableEditingMode: false,
        cellPadding: EdgeInsets.zero,
        renderer: (rendererContext) {
          final total = rendererContext.cell.value as int;
          return Container(
            height: 30,
            color: Colors.yellow.shade100,
            alignment: Alignment.center,
            child: Text(
              total.toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        },
      ),
    ];

    kumitateColumnGroups = [
      PlutoColumnGroup(
        title: "Stock Pagi",
        backgroundColor: Colors.blue.shade300,
        fields: ["stock_pagi_1", "stock_pagi_2", "stock_pagi_3", "stock_pagi_4", "stock_pagi_total"],
      ),
    ];

    for (final time in timeSlots) {
      for (int i = 1; i <= 5; i++) {
        kumitateColumns.add(PlutoColumn(
          title: "$i",
          field: "${time}_$i",
          type: PlutoColumnType.number(),
          width: 40,
          titleTextAlign: PlutoColumnTextAlign.center,
          textAlign: PlutoColumnTextAlign.center,
          backgroundColor: Colors.blue.shade200,
          enableColumnDrag: false,
          enableContextMenu: false,
          enableDropToResize: false,
          enableSorting: false,
          enableEditingMode: false,
          cellPadding: EdgeInsets.zero,
          renderer: (rendererContext) {
            final value = rendererContext.cell.value as int;
            return Container(
              height: 30,
              alignment: Alignment.center,
              child: Text(
                value.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          },
        ));
      }

      kumitateColumns.add(
        PlutoColumn(
          title: "Total",
          field: "${time}_total",
          type: PlutoColumnType.number(),
          width: 60,
          titleTextAlign: PlutoColumnTextAlign.center,
          textAlign: PlutoColumnTextAlign.center,
          backgroundColor: Colors.yellow.shade200,
          enableColumnDrag: false,
          enableContextMenu: false,
          enableDropToResize: false,
          enableSorting: false,
          enableEditingMode: false,
          cellPadding: EdgeInsets.zero,
          renderer: (rendererContext) {
            final total = rendererContext.cell.value as int;
            final target = hourlyTargets[time] ?? 0;
            final color = target > 0 
                ? (total >= target ? Colors.green : Colors.red)
                : Colors.black;
            
            return Container(
              height: 30,
              color: Colors.yellow.shade100,
              alignment: Alignment.center,
              child: Text(
                total.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            );
          },
        ),
      );

      kumitateColumns.add(
        PlutoColumn(
          title: "Akumulatif",
          field: "${time}_cumulative",
          type: PlutoColumnType.number(),
          width: 100,
          titleTextAlign: PlutoColumnTextAlign.center,
          textAlign: PlutoColumnTextAlign.center,
          backgroundColor: Colors.orange.shade200,
          enableColumnDrag: false,
          enableContextMenu: false,
          enableDropToResize: false,
          enableSorting: false,
          enableEditingMode: false,
          cellPadding: EdgeInsets.zero,
          renderer: (rendererContext) {
            final cumulative = rendererContext.cell.value as int;
            int cumulativeTarget = 0;
            for (var slot in timeSlots) {
              cumulativeTarget += (hourlyTargets[slot] ?? 0);
              if (slot == time) break;
            }
            
            final color = cumulativeTarget > 0 
                ? (cumulative >= cumulativeTarget ? Colors.green : Colors.red)
                : Colors.black;
            
            return Container(
              height: 30,
              color: Colors.orange.shade100,
              alignment: Alignment.center,
              child: Text(
                cumulative.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            );
          },
        ),
      );

      kumitateColumnGroups.add(
        PlutoColumnGroup(
          title: time,
          backgroundColor: Colors.blue.shade300,
          fields: [
            "${time}_1", "${time}_2", "${time}_3", "${time}_4", "${time}_5",
            "${time}_total", "${time}_cumulative"
          ],
        ),
      );
    }

    kumitateColumns.add(
      PlutoColumn(
        title: "GRAND TOTAL",
        field: "grand_total",
        type: PlutoColumnType.number(),
        width: 120,
        titleTextAlign: PlutoColumnTextAlign.center,
        textAlign: PlutoColumnTextAlign.center,
        backgroundColor: Colors.orange.shade300,
        enableColumnDrag: false,
        enableContextMenu: false,
        enableDropToResize: false,
        enableSorting: false,
        enableEditingMode: false,
        cellPadding: EdgeInsets.zero,
        renderer: (rendererContext) {
          final total = rendererContext.cell.value as int;
          final target = dailyTarget ?? 0;
          final color = target > 0 
              ? (total >= target ? Colors.green : Colors.red)
              : Colors.black;
              
          return Container(
            height: 30,
            color: Colors.orange.shade200,
            alignment: Alignment.center,
            child: Text(
              total.toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          );
        },
      ),
    );

    kumitateRows = [];
    
    if (kumitateData.isNotEmpty) {
      for (final entry in kumitateData) {
        final stockPagi = entry["stock_pagi"] as Map<String, dynamic>? ?? {
          '1': 0, '2': 0, '3': 0, '4': 0, 'total': 0
        };
        
        final cells = <String, PlutoCell>{
          "process_name": PlutoCell(value: entry["process_name"]),
          "type": PlutoCell(value: "Kumitate"),
          "stock_15min": PlutoCell(
            value: entry["stock_15min"] is String 
                ? int.tryParse(entry["stock_15min"] as String) ?? 0
                : (entry["stock_15min"] as num?)?.toInt() ?? 0,
          ),
          "stock_pagi_1": PlutoCell(value: stockPagi['1'] ?? 0),
          "stock_pagi_2": PlutoCell(value: stockPagi['2'] ?? 0),
          "stock_pagi_3": PlutoCell(value: stockPagi['3'] ?? 0),
          "stock_pagi_4": PlutoCell(value: stockPagi['4'] ?? 0),
          "stock_pagi_total": PlutoCell(value: stockPagi['total'] ?? 0),
        };

        int grandTotal = 0;

        for (final time in timeSlots) {
          int timeSlotTotal = 0;

          for (int i = 1; i <= 5; i++) {
            final count = (entry["${time}_$i"] as num?)?.toInt() ?? 0;
            timeSlotTotal += count;
            cells["${time}_$i"] = PlutoCell(value: count);
          }

          grandTotal += timeSlotTotal;
          cells["${time}_total"] = PlutoCell(value: timeSlotTotal);
          cells["${time}_cumulative"] = PlutoCell(value: entry["${time}_cumulative"] ?? 0);
        }

        cells["grand_total"] = PlutoCell(value: grandTotal);
        kumitateRows.add(PlutoRow(cells: cells));
      }
    }
  }

  void _buildPartColumnsAndRows() {
    partColumns = [
      PlutoColumn(
        title: "PROCESS",
        field: "process_name",
        type: PlutoColumnType.text(),
        width: 230,
        titleTextAlign: PlutoColumnTextAlign.center,
        backgroundColor: Colors.blue.shade300,
        enableColumnDrag: false,
        enableContextMenu: false,
        enableSorting: false,
        enableEditingMode: false,
        renderer: (ctx) {
          final processName = ctx.cell.value.toString();
          return Row(
            children: [
              Expanded(child: Text(processName)),
              IconButton(
                icon: Icon(Icons.bar_chart, size: 18, color: Colors.blue),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text('Grafik $processName (Part)'),
                    content: Container(
                      width: 1100,
                      height: 900,
                      child: buildChart(processName, 'Part'),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text("Tutup"),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      
      for (final time in timeSlots)
        PlutoColumn(
          title: time,
          field: "${time}_cumulative",
          type: PlutoColumnType.number(),
          width: 60,
          titleTextAlign: PlutoColumnTextAlign.center,
          textAlign: PlutoColumnTextAlign.center,
          backgroundColor: Colors.blue.shade300,
          enableColumnDrag: false,
          enableContextMenu: false,
          enableDropToResize: false,
          enableSorting: false,
          enableEditingMode: false,
          cellPadding: EdgeInsets.zero,
          renderer: (rendererContext) {
            final cumulative = rendererContext.cell.value as int;
            int cumulativeTarget = 0;
            for (var slot in timeSlots) {
              cumulativeTarget += (hourlyTargets[slot] ?? 0);
              if (slot == time) break;
            }
            
            final color = cumulativeTarget > 0 
                ? (cumulative >= cumulativeTarget ? Colors.green : Colors.red)
                : Colors.black;
            
            return Container(
              height: 30,
              alignment: Alignment.center,
              child: Text(
                cumulative.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            );
          },
        ),
      
      PlutoColumn(
        title: "Stock sebelum kensa (pagi)",
        field: "belumKensa",
        type: PlutoColumnType.text(),
        width: 200,
        titleTextAlign: PlutoColumnTextAlign.center,
        textAlign: PlutoColumnTextAlign.center,
        backgroundColor: Colors.blue.shade300,
        enableColumnDrag: false,
        enableContextMenu: false,
        enableDropToResize: false,
        enableEditingMode: true,
        enableSorting: false,
        applyFormatterInEditing: true,
        formatter: (value) {
          if (value == null) return '0';
          final strValue = value is String ? value : value.toString();
          final numericOnly = strValue.replaceAll(RegExp(r'[^0-9]'), '');
          return numericOnly.isEmpty ? '0' : numericOnly;
        },
        renderer: (rendererContext) {
          if (rendererContext.stateManager.isEditing && 
              rendererContext.stateManager.currentCell == rendererContext.cell) {
            return Padding(
              padding: EdgeInsets.all(2),
              child: TextField(
                controller: TextEditingController(
                  text: rendererContext.cell.value.toString()
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8),
                ),
                onChanged: (value) {
                  final intValue = int.tryParse(value) ?? 0;
                  rendererContext.stateManager.changeCellValue(
                    rendererContext.cell,
                    intValue,
                    notify: false,
                  );
                },
                onEditingComplete: () {
                  if (mounted) setState(() {});
                  rendererContext.stateManager.notifyListeners();
                },
              ),
            );
          }
          return Container(
            padding: EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            child: Text(
              rendererContext.cell.value.toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        },
      ),
    ];

    partRows = [];
    
    if (partData.isNotEmpty) {
      for (final entry in partData) {
        final cells = <String, PlutoCell>{
          "process_name": PlutoCell(value: entry["process_name"]),
          "type": PlutoCell(value: "Part"),
          "belumKensa": PlutoCell(
            value: entry["belumKensa"] is String 
                ? int.tryParse(entry["belumKensa"] as String) ?? 0
                : (entry["belumKensa"] as num?)?.toInt() ?? 0,
          ),
        };

        for (final time in timeSlots) {
          for (int i = 1; i <= 2; i++) {
            entry["${time}_$i"] = (entry["${time}_$i"] as num?)?.toInt() ?? 0;
          }
          
          // Apply division by 2 with floor rounding for specific processes (only for hourly data)
          if (dividedByTwoProcesses.contains(entry["process_name"])) {
            final cumulativeValue = entry["${time}_cumulative"] ?? 0;
            cells["${time}_cumulative"] = PlutoCell(
              value: (cumulativeValue / 2).floor()
            );
          } else {
            cells["${time}_cumulative"] = PlutoCell(
              value: entry["${time}_cumulative"] ?? 0
            );
          }
        }

        partRows.add(PlutoRow(cells: cells));
      }
    }
  }

  Future<void> loadData() async {
    setState(() {
      isLoading = true;
      noDataAvailable = false;
    });
    print('Loading data for Line $selectedLine on ${DateFormat('yyyy-MM-dd').format(selectedDate)}');

    final formattedDate = DateFormat("yyyy-MM-dd").format(selectedDate);
    kumitateData = await fetchCounterData(formattedDate, selectedLine, 'Kumitate');
    partData = await fetchCounterData(formattedDate, selectedLine, 'Part');

    if (kumitateData.isEmpty && partData.isEmpty) {
      setState(() {
        noDataAvailable = true;
      });
    } else {
      _buildKumitateColumnsAndRows();
      _buildPartColumnsAndRows();
    }

    setState(() => isLoading = false);
  }

  Widget buildChart(String processName, String type) {
    final dataList = type == 'Kumitate' ? kumitateData : partData;
    final process = dataList.firstWhere((e) => e["process_name"] == processName);
    final lineColors = [
      Colors.red, Colors.green, Colors.blue, Colors.orange, Colors.purple,
    ];

    final extendedTimeSlots = ["0", ...timeSlots];
    final maxLines = type == 'Part' ? 2 : 5;

    final lineBarsData = <LineChartBarData>[];
    
    for (int lineNum = 1; lineNum <= maxLines; lineNum++) {
      bool hasData = false;
      final spots = <FlSpot>[FlSpot(0, 0)];
      
      for (int t = 0; t < timeSlots.length; t++) {
        final value = (process["${timeSlots[t]}_$lineNum"] as num?)?.toDouble() ?? 0;
        if (value > 0) hasData = true;
        spots.add(FlSpot((t+1).toDouble(), value));
      }
      
      if (hasData) {
        lineBarsData.add(
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: lineColors[lineNum - 1],
            barWidth: 3,
            isStrokeCapRound: false,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 5,
                  color: lineColors[lineNum - 1],
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                );
              },
            ),
            belowBarData: BarAreaData(show: false),
          ),
        );
      }
    }

    final cumulativeSpots = <FlSpot>[FlSpot(0, 0)];
    for (int t = 0; t < timeSlots.length; t++) {
      double value = (process["${timeSlots[t]}_cumulative"] as num?)?.toDouble() ?? 0;
      // Apply division by 2 with floor rounding for specific processes in the chart (only for hourly data)
      if (type == 'Part' && dividedByTwoProcesses.contains(processName)) {
        value = (value / 2).floorToDouble();
      }
      cumulativeSpots.add(FlSpot((t+1).toDouble(), value));
    }
    
    lineBarsData.add(
      LineChartBarData(
        spots: cumulativeSpots,
        isCurved: false,
        color: Colors.black,
        barWidth: 3,
        isStrokeCapRound: false,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, barData, index) {
            return FlDotCirclePainter(
              radius: 5,
              color: Colors.black,
              strokeWidth: 2,
              strokeColor: Colors.white,
            );
          },
        ),
        belowBarData: BarAreaData(show: false),
      ),
    );

    if (dailyTarget != null) {
      final targetSpots = <FlSpot>[FlSpot(0, 0)];
      double cumulativeTarget = 0;
      for (int t = 0; t < timeSlots.length; t++) {
        cumulativeTarget += (hourlyTargets[timeSlots[t]] ?? 0).toDouble();
        targetSpots.add(FlSpot((t+1).toDouble(), cumulativeTarget));
      }
      
      lineBarsData.add(
        LineChartBarData(
          spots: targetSpots,
          isCurved: false,
          color: Colors.red,
          barWidth: 2,
          isStrokeCapRound: false,
          dotData: FlDotData(show: false),
          dashArray: [5, 5],
          belowBarData: BarAreaData(show: false),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8.0,
              runSpacing: 4.0,
              children: List.generate(lineBarsData.length, (index) {
                final colors = [
                  ...lineColors, Colors.black, Colors.red
                ];
                final labels = [
                  'Line 1', 'Line 2', 'Line 3', 'Line 4', 'Line 5', 
                  'Akumulatif', 'Target'
                ];
                
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: colors[index],
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      labels[index],
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: LineChart(
                LineChartData(
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (List<LineBarSpot> touchedSpots) {
                        return touchedSpots.map((spot) {
                          final timeIndex = spot.x.toInt();
                          if (timeIndex == 0) {
                            return LineTooltipItem(
                              'Start: 0',
                              const TextStyle(color: Colors.white),
                            );
                          }
                          final timeSlot = timeSlots[timeIndex - 1];
                          if (spot.barIndex < maxLines) {
                            return LineTooltipItem(
                              'Line ${spot.barIndex + 1}: ${spot.y.toInt()}\n$timeSlot',
                              const TextStyle(color: Colors.white),
                            );
                          } else if (spot.barIndex == maxLines) {
                            return LineTooltipItem(
                              'Akumulatif: ${spot.y.toInt()}\n$timeSlot',
                              const TextStyle(color: Colors.white),
                            );
                          } else {
                            return LineTooltipItem(
                              'Target: ${spot.y.toInt()}\n$timeSlot',
                              const TextStyle(color: Colors.white),
                            );
                          }
                        }).toList();
                      },
                    ),
                  ),
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, _) {
                          if (value != value.toInt()) return Container();
                          final index = value.toInt();
                          if (index < 0 || index >= extendedTimeSlots.length) return Container();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              extendedTimeSlots[index],
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                        interval: 1,
                        reservedSize: 24,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (value, _) => Text(
                          value.toInt().toString(),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: const Color(0xff37434d), width: 1),
                  ),
                  lineBarsData: lineBarsData,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> exportToExcel() async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];

      sheet.appendRow([
        TextCellValue('TYPE'),
        TextCellValue('PROCESS'),
        ...timeSlots.map((time) => TextCellValue(time)),
        TextCellValue('Stock sebelum kensa (pagi)'),
        TextCellValue('Stock 15 menit'),
        TextCellValue('Stock Pagi 1'),
        TextCellValue('Stock Pagi 2'),
        TextCellValue('Stock Pagi 3'),
        TextCellValue('Stock Pagi 4'),
        TextCellValue('Total Stock Pagi'),
      ]);

      for (final row in kumitateRows) {
        sheet.appendRow([
          TextCellValue('Kumitate'),
          TextCellValue(row.cells['process_name']!.value.toString()),
          ...timeSlots.map((time) => IntCellValue(row.cells['${time}_cumulative']!.value as int)),
          IntCellValue(0),
          IntCellValue(row.cells['stock_15min']!.value as int),
          IntCellValue(row.cells['stock_pagi_1']!.value as int),
          IntCellValue(row.cells['stock_pagi_2']!.value as int),
          IntCellValue(row.cells['stock_pagi_3']!.value as int),
          IntCellValue(row.cells['stock_pagi_4']!.value as int),
          IntCellValue(row.cells['stock_pagi_total']!.value as int),
        ]);
      }

      for (final row in partRows) {
        int belumKensa = row.cells['belumKensa']!.value as int;
        
        sheet.appendRow([
          TextCellValue('Part'),
          TextCellValue(row.cells['process_name']!.value.toString()),
          ...timeSlots.map((time) {
            int value = row.cells['${time}_cumulative']!.value as int;
            // Apply division by 2 with floor rounding for specific processes in export (only for hourly data)
            if (dividedByTwoProcesses.contains(row.cells['process_name']!.value.toString())) {
              value = (value / 2).floor();
            }
            return IntCellValue(value);
          }),
          IntCellValue(belumKensa),
          IntCellValue(0),
          IntCellValue(0),
          IntCellValue(0),
          IntCellValue(0),
          IntCellValue(0),
        ]);
      }

      final bytes = excel.encode() as Uint8List;
      final dateStr = DateFormat('yyyyMMdd').format(selectedDate);
      final fileName = 'Counter_Data_Line${selectedLine}_$dateStr.xlsx';
      
      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: bytes,
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported to $fileName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _saveToFirebase() async {
    setState(() => isSaving = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
      final batch = FirebaseFirestore.instance.batch();
      
      // Save Part belumKensa
      for (final row in partRows) {
        final processName = row.cells['process_name']!.value.toString().replaceAll(' ', '_');
        final docRef = FirebaseFirestore.instance
            .collection('counter_sistem')
            .doc(dateStr)
            .collection(selectedLine)
            .doc('Part')
            .collection('Process')
            .doc(processName);
            
        int belumKensa = 0;
        final cellValue = row.cells['belumKensa']?.value;
        
        // Handle different possible types for the cell value
        if (cellValue is int) {
          belumKensa = cellValue;
        } else if (cellValue is String) {
          belumKensa = int.tryParse(cellValue) ?? 0;
        } else if (cellValue is num) {
          belumKensa = cellValue.toInt();
        }
        
        final updateData = {
          'belumKensa': belumKensa,
        };
        
        batch.update(docRef, updateData);
      }
      
      // Save Kumitate stock 15 menit and stock pagi
      for (final row in kumitateRows) {
        final processName = row.cells['process_name']!.value.toString().replaceAll(' ', '_');
        final docRef = FirebaseFirestore.instance
            .collection('counter_sistem')
            .doc(dateStr)
            .collection(selectedLine)
            .doc('Kumitate')
            .collection('Process')
            .doc(processName);
            
        int stock15min = 0;
        final cellValue = row.cells['stock_15min']?.value;
        
        // Handle different possible types for the cell value
        if (cellValue is int) {
          stock15min = cellValue;
        } else if (cellValue is String) {
          stock15min = int.tryParse(cellValue) ?? 0;
        } else if (cellValue is num) {
          stock15min = cellValue.toInt();
        }

        // Get stock pagi values
        final stockPagi = {
          '1': row.cells['stock_pagi_1']?.value as int? ?? 0,
          '2': row.cells['stock_pagi_2']?.value as int? ?? 0,
          '3': row.cells['stock_pagi_3']?.value as int? ?? 0,
          '4': row.cells['stock_pagi_4']?.value as int? ?? 0,
          'total': (row.cells['stock_pagi_1']?.value as int? ?? 0) +
                   (row.cells['stock_pagi_2']?.value as int? ?? 0) +
                   (row.cells['stock_pagi_3']?.value as int? ?? 0) +
                   (row.cells['stock_pagi_4']?.value as int? ?? 0),
        };
        
        final updateData = {
          'stock_15min': stock15min,
          'stock_pagi': stockPagi,
        };
        
        batch.update(docRef, updateData);
      }
      
      await batch.commit();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Data stock pagi dan stock 15 menit berhasil disimpan!')),
        );
      }
    } catch (e) {
      print('Error saving data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan data: $e')),
        );
      }
    } finally {
      setState(() => isSaving = false);
    }
  }

  Future<void> selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(Duration(days: 1)), // Allow today + 1 day
    );

    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
        isLoading = true;
        isTargetLoading = true;
      });
      await loadData();
      await _loadTargets();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade100,
      appBar: AppBar(
        title: Text(
          "Stock Kumitate & Part per Process",
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
            icon: Icon(Icons.save, color: Colors.white),
            onPressed: isSaving ? null : _saveToFirebase,
            tooltip: "Simpan Stock Pagi dan 15 menit",
          ),
          IconButton(
            icon: Icon(Icons.file_download, color: Colors.white),
            tooltip: "Export to Excel",
            onPressed: exportToExcel,
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            tooltip: "Refresh Data",
            onPressed: () {
              setState(() {
                isLoading = true;
                isTargetLoading = true;
              });
              loadData();
              _loadTargets();
            },
          ),
          SizedBox(width: 16),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : noDataAvailable
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "No Data Available for ${DateFormat('yyyy-MM-dd').format(selectedDate)}",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => selectDate(context),
                        child: Text("Select Different Date"),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              width: 120,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.blue.shade500, width: 1),
                              ),
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: selectedLine,
                                  items: ["A", "B", "C", "D", "E"]
                                      .map((line) => DropdownMenuItem(
                                            value: line,
                                            child: Center(
                                              child: Text(
                                                "Line $line",
                                                style: TextStyle(fontSize: 14),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ))
                                      .toList(),
                                  onChanged: (value) {
                                    setState(() {
                                      selectedLine = value!;
                                      isLoading = true;
                                      isTargetLoading = true;
                                    });
                                    loadData();
                                    _loadTargets();
                                  },
                                  icon: Icon(Icons.arrow_drop_down, size: 20, color: Colors.blue.shade600),
                                  style: TextStyle(color: Colors.black),
                                  dropdownColor: Colors.white,
                                ),
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: isTargetLoading
                                  ? Center(
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Target: ${dailyTarget ?? '-'}  ',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                        ),
                                        Text(
                                          'Per Jam: ${dailyTarget != null ? (dailyTarget! ~/ 8) : '-'}',
                                          style: TextStyle(
                                            fontSize: 20,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                            Container(
                              width: 140,
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  backgroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    side: BorderSide(color: Colors.blue.shade500, width: 1),
                                  ),
                                ),
                                onPressed: () => selectDate(context),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.calendar_today, size: 18, color: Colors.blue.shade600),
                                    SizedBox(width: 6),
                                    Text(
                                      DateFormat("yyyy-MM-dd").format(selectedDate),
                                      style: TextStyle(fontSize: 14, color: Colors.black),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (kumitateRows.isNotEmpty)
                        _buildTableWidget(
                          title: 'KUMITATE',
                          columns: kumitateColumns,
                          rows: kumitateRows,
                          columnGroups: kumitateColumnGroups,
                        ),
                      if (partRows.isNotEmpty)
                        _buildTableWidget(
                          title: 'PART',
                          columns: partColumns,
                          rows: partRows,
                          columnGroups: [],
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildTableWidget({
    required String title,
    required List<PlutoColumn> columns,
    required List<PlutoRow> rows,
    required List<PlutoColumnGroup> columnGroups,
  }) {
    const rowHeight = 30.0;
    const headerHeight = 40.0;
    const columnHeaderHeight = 30.0;
    final totalHeight = headerHeight + columnHeaderHeight + (rows.length * rowHeight) + 5;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: headerHeight,
            decoration: BoxDecoration(
              color: Colors.blue.shade300,
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Center(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              FocusScope.of(context).unfocus();
              setState(() {});
            },
            child: Container(
              height: totalHeight,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue.shade800),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
              ),
              child: PlutoGrid(
                key: ValueKey('${title}_${selectedDate}_${selectedLine}'),
                columns: columns,
                rows: rows,
                columnGroups: columnGroups,
                configuration: PlutoGridConfiguration(
                  style: PlutoGridStyleConfig(
                    gridBackgroundColor: Colors.blue.shade100,
                    rowColor: Colors.blue.shade50,
                    borderColor: Colors.blue.shade800,
                    rowHeight: rowHeight,
                    columnHeight: columnHeaderHeight,
                  ),
                  scrollbar: PlutoGridScrollbarConfig(
                    isAlwaysShown: false,
                    scrollbarThickness: 0,
                  ),
                  enableMoveHorizontalInEditing: true,
                  enterKeyAction: PlutoGridEnterKeyAction.editingAndMoveDown,
                ),
                onChanged: (PlutoGridOnChangedEvent event) {
                  if (event.column.field == 'belumKensa' || 
                      event.column.field == 'stock_15min' ||
                      event.column.field.startsWith('stock_pagi_')) {
                    final stateManager = title == 'PART' 
                        ? _partStateManager 
                        : _kumitateStateManager;
                    
                    if (stateManager != null) {
                      final intValue = int.tryParse(event.value.toString()) ?? 0;
                      stateManager.changeCellValue(
                        event.row.cells[event.column.field]!,
                        intValue,
                        notify: false,
                      );

                      // Calculate stock pagi total if any stock pagi field changes
                      if (event.column.field.startsWith('stock_pagi_') && !event.column.field.endsWith('total')) {
                        final pagi1 = event.row.cells['stock_pagi_1']?.value as int? ?? 0;
                        final pagi2 = event.row.cells['stock_pagi_2']?.value as int? ?? 0;
                        final pagi3 = event.row.cells['stock_pagi_3']?.value as int? ?? 0;
                        final pagi4 = event.row.cells['stock_pagi_4']?.value as int? ?? 0;
                        final pagiTotal = pagi1 + pagi2 + pagi3 + pagi4;
                        stateManager.changeCellValue(
                          event.row.cells['stock_pagi_total']!,
                          pagiTotal,
                          notify: false,
                        );
                      }

                      setState(() {});
                    }
                  }
                },
                onLoaded: (PlutoGridOnLoadedEvent event) {
                  if (title == 'PART') {
                    _partStateManager = event.stateManager;
                  } else {
                    _kumitateStateManager = event.stateManager;
                  }
                  
                  event.stateManager.addListener(() {
                    if (!event.stateManager.hasFocus) {
                      setState(() {});
                    }
                  });
                },
                mode: PlutoGridMode.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}