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
  List<PlutoColumn> columns = [];
  List<PlutoRow> rows = [];
  List<PlutoColumnGroup> columnGroups = [];
  bool isLoading = true;

  String selectedLine = "A";
  DateTime selectedDate = DateTime.now();
  List<Map<String, dynamic>> originalData = [];
  int? dailyTarget;
  Map<String, int> hourlyTargets = {};
  bool isTargetLoading = true;

  final List<String> timeSlots = [
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
    "06:30": "07:30 - 08:29",
    "07:30": "07:30 - 08:29",
    "08:30": "08:30 - 09:29",
    "09:30": "09:30 - 10:29",
    "10:30": "10:30 - 11:29",
    "11:30": "10:30 - 11:29",
    "12:30": "12:30 - 13:29",
    "13:30": "13:30 - 14:29",
    "14:30": "14:30 - 15:29",
    "15:30": "15:30 - 16:29",
    "16:30": "16:30~",
    "17:30": "16:30~",
    "18:30": "16:30~",
    "19:30": "16:30~",
  };

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
              '07:30 - 08:29': (dailyTarget! ~/ 8),
              '08:30 - 09:29': (dailyTarget! ~/ 8),
              '09:30 - 10:29': (dailyTarget! ~/ 8),
              '10:30 - 11:29': (dailyTarget! ~/ 8),
              '12:30 - 13:29': (dailyTarget! ~/ 8),
              '13:30 - 14:29': (dailyTarget! ~/ 8),
              '14:30 - 15:29': (dailyTarget! ~/ 8),
              '15:30 - 16:29': (dailyTarget! ~/ 8),
              '16:30~': 0,
            };
          }
        });
      }
    } catch (e) {
      print('Error loading targets: $e');
    } finally {
      setState(() => isTargetLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> fetchCounterData(String date, String line) async {
    try {
      final processRef = FirebaseFirestore.instance
          .collection('counter_sistem')
          .doc(date)
          .collection(line)
          .doc('Kumitate')
          .collection('Process');

      final snapshot = await processRef.get();

      if (snapshot.docs.isEmpty) {
        print('No process documents found for Line $line on $date');
        return [];
      }

      List<Map<String, dynamic>> processList = [];

      for (var doc in snapshot.docs) {
        final processData = doc.data();
        final processMap = <String, dynamic>{
          "process_name": doc.id.replaceAll('_', ' '),
          "sequence": (processData['sequence'] as num?)?.toInt() ?? 0,
        };

        // Initialize all time slots with 0
        for (final time in timeSlots) {
          for (int i = 1; i <= 5; i++) {
            processMap["${time}_$i"] = 0;
          }
        }

        // Process each time entry in the document
        processData.forEach((key, value) {
          if (key != 'sequence' && value is Map<String, dynamic>) {
            final timeKey = key;
            final mappedTime = timeRangeMap[timeKey];
            
            if (mappedTime != null) {
              for (int i = 1; i <= 5; i++) {
                final count = (value['$i'] as num?)?.toInt() ?? 0;
                // Menjumlahkan nilai untuk slot waktu yang sama
                processMap["${mappedTime}_$i"] = (processMap["${mappedTime}_$i"] as int) + count;
              }
            }
          }
        });

        processList.add(processMap);
      }

      // Sort by sequence number
      processList.sort((a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int));
      return processList;
    } catch (e) {
      print('Error fetching counter data: $e');
      return [];
    }
  }

  Future<void> loadData() async {
    setState(() => isLoading = true);
    print('Loading data for Line $selectedLine on ${DateFormat('yyyy-MM-dd').format(selectedDate)}');

    final formattedDate = DateFormat("yyyy-MM-dd").format(selectedDate);
    originalData = await fetchCounterData(formattedDate, selectedLine);

    if (originalData.isEmpty) {
      print('No data available after fetching');
      setState(() {
        isLoading = false;
        rows = [];
      });
      return;
    }

    // Build columns
    columns = [
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
                    title: Text('Grafik $processName'),
                    content: Container(
                      width: 1100,
                      height: 900,
                      child: buildChart(processName),
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
    ];

    columnGroups = [];

    // Add columns for each time slot
    for (final time in timeSlots) {
      // Columns for each line (1-5)
      for (int i = 1; i <= 5; i++) {
        columns.add(PlutoColumn(
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
          cellPadding: EdgeInsets.all(1.0),
        ));
      }

      // Total column for the time slot
      columns.add(
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
          cellPadding: EdgeInsets.all(1.0),
          renderer: (rendererContext) {
            final total = rendererContext.cell.value as int;
            final target = hourlyTargets[time] ?? 0;
            final color = target > 0 
                ? (total >= target ? Colors.green : Colors.red)
                : Colors.black;
            
            return Container(
              color: Colors.yellow.shade100,
              alignment: Alignment.center,
              child: Text(
                total.toString(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            );
          },
        ),
      );

      // Column group for the time slot
      columnGroups.add(
        PlutoColumnGroup(
          title: time,
          backgroundColor: Colors.blue.shade300,
          fields: [
            "${time}_1",
            "${time}_2",
            "${time}_3",
            "${time}_4",
            "${time}_5",
            "${time}_total"
          ],
        ),
      );
    }

    // Grand total column
    columns.add(
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
        cellPadding: EdgeInsets.all(1.0),
        renderer: (rendererContext) {
          final total = rendererContext.cell.value as int;
          final target = dailyTarget ?? 0;
          final color = target > 0 
              ? (total >= target ? Colors.green : Colors.red)
              : Colors.black;
              
          return Container(
            color: Colors.orange.shade200,
            alignment: Alignment.center,
            child: Text(
              total.toString(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          );
        },
      ),
    );

    // Build rows from the data
    rows = originalData.map((entry) {
      final cells = <String, PlutoCell>{
        "process_name": PlutoCell(value: entry["process_name"]),
      };

      int grandTotal = 0;

      // Calculate totals for each time slot
      for (final time in timeSlots) {
        int timeSlotTotal = 0;

        for (int i = 1; i <= 5; i++) {
          final count = (entry["${time}_$i"] as num?)?.toInt() ?? 0;
          timeSlotTotal += count;
          cells["${time}_$i"] = PlutoCell(value: count);
        }

        grandTotal += timeSlotTotal;
        cells["${time}_total"] = PlutoCell(value: timeSlotTotal);
      }

      cells["grand_total"] = PlutoCell(value: grandTotal);
      return PlutoRow(cells: cells);
    }).toList();

    setState(() => isLoading = false);
  }

  Widget buildChart(String processName) {
    final process = originalData.firstWhere((e) => e["process_name"] == processName);
    final lineColors = [
      Colors.red,
      Colors.green,
      Colors.blue,
      Colors.orange,
      Colors.purple,
    ];

    final extendedTimeSlots = ["0", ...timeSlots];

    final lineBars = <LineChartBarData>[];
    
    for (int lineNum = 1; lineNum <= 5; lineNum++) {
      bool hasData = false;
      final spots = <FlSpot>[FlSpot(0, 0)];
      
      for (int t = 0; t < timeSlots.length; t++) {
        final value = (process["${timeSlots[t]}_$lineNum"] as num?)?.toDouble() ?? 0;
        if (value > 0) hasData = true;
        spots.add(FlSpot((t+1).toDouble(), value));
      }
      
      if (hasData) {
        lineBars.add(
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
              children: List.generate(5, (index) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: lineColors[index],
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Line ${index + 1}',
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
                          return LineTooltipItem(
                            'Line ${spot.barIndex + 1}: ${spot.y.toInt()}\n$timeSlot',
                            const TextStyle(color: Colors.white),
                          );
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
                  minX: 0,
                  maxX: extendedTimeSlots.length.toDouble() - 1,
                  minY: 0,
                  lineBarsData: lineBars,
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
        TextCellValue('PROCESS'),
        ...timeSlots.expand((time) => [
          for (int i = 1; i <= 5; i++) TextCellValue('$time ($i)'),
          TextCellValue('$time (Total)')
        ]),
        TextCellValue('GRAND TOTAL')
      ]);

      for (final row in rows) {
        sheet.appendRow([
          TextCellValue(row.cells['process_name']!.value.toString()),
          ...timeSlots.expand((time) => [
            for (int i = 1; i <= 5; i++) IntCellValue(row.cells['${time}_$i']!.value as int),
            IntCellValue(row.cells['${time}_total']!.value as int)
          ]),
          IntCellValue(row.cells['grand_total']!.value as int)
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

  Future<void> selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
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
          "Stock Kumitate per Process",
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
            icon: Icon(Icons.file_download, size: 26, color: Colors.white),
            tooltip: "Export to Excel",
            onPressed: exportToExcel,
            splashRadius: 24,
          ),
          IconButton(
            icon: Icon(Icons.refresh, size: 26, color: Colors.white),
            tooltip: "Refresh Data",
            onPressed: () {
              setState(() {
                isLoading = true;
                isTargetLoading = true;
              });
              loadData();
              _loadTargets();
            },
            splashRadius: 24,
          ),
          SizedBox(width: 16),
        ],
      ),
      body: Column(
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
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? Center(child: Text("No Data Available"))
                    : Padding(
                        padding: EdgeInsets.only(left: 8.0, right: 4.0),
                        child: PlutoGrid(
                          columns: columns,
                          rows: rows,
                          columnGroups: columnGroups,
                          configuration: PlutoGridConfiguration(
                            style: PlutoGridStyleConfig(
                              gridBackgroundColor: Colors.blue.shade100,
                              rowColor: Colors.blue.shade50,
                              borderColor: Colors.blue.shade800,
                              rowHeight: 30,
                              columnHeight: 30,
                              cellTextStyle: TextStyle(fontSize: 12),
                            ),
                          ),
                          mode: PlutoGridMode.readOnly,
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}