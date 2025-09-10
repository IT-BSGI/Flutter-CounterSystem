import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:excel/excel.dart' as excel;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';

class CounterTableScreen extends StatefulWidget {
  @override
  _CounterTableScreenState createState() => _CounterTableScreenState();
}

class _CounterTableScreenState extends State<CounterTableScreen> {
  // Untuk tabel Proses (akumulatif 12345 per timeslot)
  List<PlutoColumn> prosesColumns = [];
  List<PlutoRow> prosesRows = [];
  String? selectedProcessName;
  List<String> processNames = [];

  // Build tabel Proses: timeslot, 1,2,3,4,5, total akumulatif per timeslot
  void _buildProsesTable() {
    // Kolom: TIME, lalu per line (1-5) grup: Jam, Ak
    prosesColumns = [
      PlutoColumn(
        title: "TIME",
        field: "time_slot",
        type: PlutoColumnType.text(),
        width: 100,
        titleTextAlign: PlutoColumnTextAlign.center,
        backgroundColor: Colors.blue.shade300,
        enableColumnDrag: false,
        enableContextMenu: false,
        enableSorting: false,
        enableEditingMode: false,
        enableDropToResize: false,
        renderer: (ctx) {
          return Container(
            alignment: Alignment.center,
            child: Text(
              ctx.cell.value.toString(),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          );
        },
      ),
      for (int i = 1; i <= 5; i++) ...[
        PlutoColumn(
          title: "Jam",
          field: "line_${i}_jam",
          type: PlutoColumnType.number(),
          width: 60,
          titleTextAlign: PlutoColumnTextAlign.center,
          textAlign: PlutoColumnTextAlign.center,
          backgroundColor: Colors.blue.shade200,
          enableColumnDrag: false,
          enableContextMenu: false,
          enableSorting: false,
          enableEditingMode: false,
          enableDropToResize: false,
          renderer: (ctx) {
            return Container(
              alignment: Alignment.center,
              child: Text(
                ctx.cell.value.toString(),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            );
          },
        ),
        PlutoColumn(
          title: "Ak",
          field: "line_${i}_ak",
          type: PlutoColumnType.number(),
          width: 60,
          titleTextAlign: PlutoColumnTextAlign.center,
          textAlign: PlutoColumnTextAlign.center,
          backgroundColor: Colors.blue.shade200, // Sama dengan kolom Jam
          enableColumnDrag: false,
          enableContextMenu: false,
          enableSorting: false,
          enableEditingMode: false,
          enableDropToResize: false,
          renderer: (ctx) {
            return Container(
              alignment: Alignment.center,
              child: Text(
                ctx.cell.value.toString(),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            );
          },
        ),
      ],
    ];

    // Group kolom per line
    prosesColumnGroups = [
      for (int i = 1; i <= 5; i++)
        PlutoColumnGroup(
          title: '$i',
          backgroundColor: Colors.blue.shade300,
          fields: ['line_${i}_jam', 'line_${i}_ak'],
        ),
    ];

    // Baris: setiap timeslot, data dari proses terpilih
    prosesRows = [];
    final prosesList = List<Map<String, dynamic>>.from(kumitateData);
    prosesList.sort((a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int));
    // Ambil hanya proses dengan sequence != 0 (sesuai tabel kumitate)
    processNames = prosesList
      .where((e) => (e['sequence'] ?? 0) != 0)
      .map((e) => e["process_name"]?.toString() ?? "")
      .where((e) => e.isNotEmpty)
      .toList();
    // Pastikan selectedProcessName selalu valid
    if (selectedProcessName == null || !processNames.contains(selectedProcessName)) {
      selectedProcessName = processNames.isNotEmpty ? processNames.first : null;
    }
    final proses = prosesList.firstWhere(
      (e) => e["process_name"]?.toString() == selectedProcessName,
      orElse: () => {},
    );
    for (final time in visibleTimeSlots) {
      final cells = <String, PlutoCell>{};
      cells["time_slot"] = PlutoCell(value: time);
      for (int i = 1; i <= 5; i++) {
        // Jam: hanya perolehan di jam itu saja
        final jamRaw = proses["${time}_$i"];
        final jamValue = jamRaw == null ? ' ' : (jamRaw is int ? (jamRaw == 0 ? ' ' : jamRaw) : jamRaw.toString() == '0' ? ' ' : jamRaw);
        // Ak: akumulatif sampai jam itu
        int akumulatif = 0;
        bool hasData = false;
        for (final t in visibleTimeSlots) {
          final val = proses["${t}_$i"];
          if (val != null && val != 0 && val.toString() != '0') hasData = true;
          if (t.compareTo(time) > 0) break;
          akumulatif += (val is int ? val : int.tryParse(val?.toString() ?? '0') ?? 0);
          if (t == time) break;
        }
        cells["line_${i}_jam"] = PlutoCell(value: jamValue);
        // Akumulatif: jika tidak ada data sama sekali, tampilkan ' '
        cells["line_${i}_ak"] = PlutoCell(value: hasData ? akumulatif : ' ');
      }
      prosesRows.add(PlutoRow(cells: cells));
    }

    this.prosesColumns = prosesColumns;
    this.prosesRows = prosesRows;
    this.prosesColumnGroups = prosesColumnGroups;
  }
  List<PlutoColumnGroup> prosesColumnGroups = [];
  bool get isEditableNow {
    final now = DateTime.now();
    final isToday = selectedDate.year == now.year && selectedDate.month == now.month && selectedDate.day == now.day;
    final before0830 = now.hour < 8 || (now.hour == 8 && now.minute < 30);
    return isToday && before0830;
  }
  List<PlutoColumnGroup> partColumnGroups = [];
  // Fungsi untuk menentukan warna baris PART
  Color? getPartRowColor(String processName) {
    switch (processName) {
      case 'Maemi IN':
      case 'Maemi OUT':
        return Colors.blue.shade50;
      case 'Ushiro IN':
      case 'Ushiro OUT':
        return Colors.blue.shade200;
      case 'Eri IN':
      case 'Eri OUT':
        return Colors.blue.shade50;
      case 'Sode IN':
      case 'Sode OUT':
        return Colors.blue.shade200;
      case 'Cuff IN':
      case 'Cuff OUT':
        return Colors.blue.shade50;
      default:
        return null;
    }
  }
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
  double? dailyTarget;
  Map<String, double> hourlyTargets = {};
  bool isTargetLoading = true;
  bool isSaving = false;
  bool noDataAvailable = false;

  PlutoGridStateManager? _kumitateStateManager;
  PlutoGridStateManager? _partStateManager;

  final List<String> timeSlots = [
    "08:30", "09:30", "10:30", "11:30", "13:30", 
    "14:30", "15:30", "16:30", "17:55", "18:55", "19:55",
  ];
    List<String> visibleTimeSlots = [];

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

  final List<String> partProcessOrder = [
    "Maemi IN", "Maemi OUT", "Ushiro IN", "Ushiro OUT",
    "Eri IN", "Eri OUT", "Sode IN", "Sode OUT",
    "Cuff IN", "Cuff OUT",
  ];

  // Map nama process ke huruf Jepang (hiragana)
  final Map<String, String> partProcessHiragana = {
    "Maemi IN": "まえみ いん",
    "Maemi OUT": "まえみ あうと",
    "Ushiro IN": "うしろ いん",
    "Ushiro OUT": "うしろ あうと",
    "Eri IN": "えり いん",
    "Eri OUT": "えり あうと",
    "Sode IN": "そで いん",
    "Sode OUT": "そで あうと",
    "Cuff IN": "かふ いん",
    "Cuff OUT": "かふ あうと",
  };

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
          // Simpan sebagai double untuk akurasi
          dailyTarget = target is num ? target.toDouble() : null;
          
          if (dailyTarget != null) {
            double targetPerHour = dailyTarget! / 8;
            
            hourlyTargets = {
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
        final partData = processData['part'] ?? {};
        final part1 = partData is String ? partData : partData['part1'] ?? "";
        final part2 = partData is String ? "" : partData['part2'] ?? "";

        final processMap = <String, dynamic>{
          "process_name": doc.id.replaceAll('_', ' '),
          "sequence": (processData['sequence'] as num?)?.toInt() ?? 0,
          "belumKensa": processData['belumKensa'] is String 
              ? int.tryParse(processData['belumKensa'] as String) ?? 0
              : (processData['belumKensa'] as num?)?.toInt() ?? 0,
          "stock_20min": processData['stock_20min'] is String 
              ? int.tryParse(processData['stock_20min'] as String) ?? 0
              : (processData['stock_20min'] as num?)?.toInt() ?? 0,
          "stock_pagi": processData['stock_pagi'] ?? {
            '1': 0, '2': 0, '3': 0, '4': 0, 'stock': 0
          },
          "part": part1,
          "part_2": part2,
          "type": type,
          "raw_data": processData,
        };

        Map<String, int> cumulativeData = {};
        for (final time in timeSlots) {
          cumulativeData[time] = 0;
        }

        processData.forEach((key, value) {
          if (key != 'sequence' && key != 'belumKensa' && key != 'stock_20min' && key != 'stock_pagi' && key != 'part' && value is Map<String, dynamic>) {
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
          if (key != 'sequence' && key != 'belumKensa' && key != 'stock_20min' && key != 'stock_pagi' && key != 'part' && value is Map<String, dynamic>) {
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
        width: 260,
        titleTextAlign: PlutoColumnTextAlign.center,
        backgroundColor: Colors.blue.shade300,
        enableColumnDrag: false,
        enableContextMenu: false,
        enableSorting: false,
        enableEditingMode: false,
        renderer: (ctx) {
          final processName = ctx.cell.value.toString();
          final hiragana = partProcessHiragana[processName];
          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(processName, style: TextStyle(fontWeight: FontWeight.bold)),
                    if (hiragana != null)
                      Text('($hiragana)', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                  ],
                ),
              ),
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
        frozen: PlutoColumnFrozen.start,
      ),
      PlutoColumn(
        title: "Stock 20 menit",
        field: "stock_20min",
        type: PlutoColumnType.text(),
        width: 117,
        titleTextAlign: PlutoColumnTextAlign.center,
        textAlign: PlutoColumnTextAlign.center,
        backgroundColor: Colors.blue.shade300,
        enableColumnDrag: false,
        enableDropToResize: false,
        enableContextMenu: false,
        enableEditingMode: isEditableNow,
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
        frozen: PlutoColumnFrozen.start,
      ),
      for (int i = 1; i <= 5; i++)
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
          enableEditingMode: isEditableNow,
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
        title: "PART",
        field: "part",
        type: PlutoColumnType.text(),
        width: 90,
        titleTextAlign: PlutoColumnTextAlign.center,
        textAlign: PlutoColumnTextAlign.center,
        backgroundColor: Colors.blue.shade200,
        enableColumnDrag: false,
        enableContextMenu: false,
        enableDropToResize: false,
        enableSorting: false,
        enableEditingMode: isEditableNow,
        cellPadding: EdgeInsets.zero,
        renderer: (rendererContext) {
          final part1 = rendererContext.cell.value?.toString() ?? '';
          final part2 = rendererContext.row.cells['part_2']?.value?.toString() ?? '';
          final targetPerJam = hourlyTargets.isNotEmpty ? (hourlyTargets.values.first * 2) : 0;
          // Saat edit: tampilkan gabungan part1,part2 di semua baris
          if (rendererContext.stateManager.isEditing && rendererContext.stateManager.currentCell == rendererContext.cell) {
            String part1 = rendererContext.cell.value?.toString() ?? '';
            String part2 = rendererContext.row.cells['part_2']?.value?.toString() ?? '';
            String combined = part1.contains(',') ? part1 : (part2.isNotEmpty ? '$part1,$part2' : part1);
            final controller = TextEditingController(text: combined);
            return Container(
              height: 30,
              child: Padding(
                padding: EdgeInsets.all(2),
                child: TextField(
                  controller: controller,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                    hintText: 'part1,part2',
                  ),
                  onChanged: (value) {
                    rendererContext.stateManager.changeCellValue(
                      rendererContext.cell,
                      value,
                      notify: false,
                    );
                  },
                  onSubmitted: (value) {
                    if (value.trim().isEmpty) {
                      rendererContext.stateManager.changeCellValue(
                        rendererContext.cell,
                        '',
                        notify: false,
                      );
                      rendererContext.stateManager.changeCellValue(
                        rendererContext.row.cells['part_2']!,
                        '',
                        notify: false,
                      );
                    } else {
                      final values = value.split(',');
                      final p1 = values.isNotEmpty ? values[0].trim() : '';
                      final p2 = values.length > 1 ? values[1].trim() : '';
                      rendererContext.stateManager.changeCellValue(
                        rendererContext.cell,
                        p1,
                        notify: false,
                      );
                      rendererContext.stateManager.changeCellValue(
                        rendererContext.row.cells['part_2']!,
                        p2,
                        notify: false,
                      );
                    }
                    rendererContext.stateManager.notifyListeners();
                    if (mounted) setState(() {});
                  },
                ),
              ),
            );
          }
          // Tampilan normal dengan warna berdasarkan target
          if (part2.isNotEmpty) {
            final part1Value = int.tryParse(part1) ?? 0;
            final part2Value = int.tryParse(part2) ?? 0;
            // Jika tidak ada data, warna tetap biru
            final color1 = part1.isEmpty || part1Value == 0 
                ? Colors.blue.shade50 
                : (part1Value >= targetPerJam ? Colors.green.shade200 : Colors.red.shade200);
            final color2 = part2.isEmpty || part2Value == 0 
                ? Colors.blue.shade50 
                : (part2Value >= targetPerJam ? Colors.green.shade200 : Colors.red.shade200);
            return Container(
              height: 30,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: Colors.blue.shade800, width: 1), // border kanan untuk part
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      alignment: Alignment.center,
                      child: Text(part1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      decoration: BoxDecoration(
                        color: color1,
                        border: Border(
                          right: BorderSide(color: Colors.blue.shade800, width: 1),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      alignment: Alignment.center,
                      child: Text(part2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      decoration: BoxDecoration(
                        color: color2,
                      ),
                    ),
                  ),
                ],
              ),
            );
          } else {
            final part1Value = int.tryParse(part1) ?? 0;
            // Jika tidak ada data, warna tetap biru
            final color1 = part1.isEmpty || part1Value == 0 
                ? Colors.blue.shade50 
                : (part1Value >= targetPerJam ? Colors.green.shade200 : Colors.red.shade200);
            return Container(
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color1,
                border: Border(
                  right: BorderSide(color: Colors.blue.shade800, width: 1), // border kanan untuk part
                ),
              ),
              child: Text(part1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            );
          }
        },
      ),
      PlutoColumn(
        title: "Stock",
        field: "stock_pagi_stock",
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
          final stock = rendererContext.cell.value as int;
          return Container(
            height: 30,
            decoration: BoxDecoration(
              color: Colors.yellow.shade100,
              border: Border(
                right: BorderSide(color: Colors.blue.shade800, width: 1),
              ),
            ),
            child: Center(
              child: Text(
                stock.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
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
        fields: ["stock_pagi_1", "stock_pagi_2", "stock_pagi_3", "stock_pagi_4", "stock_pagi_5", "part", "part_2", "stock_pagi_stock"],
      ),
    ];

  for (final time in visibleTimeSlots) {
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
              child: Center(
                child: Text(
                  value.toString(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          },
        ));
      }

      // Tambah kolom PART (readonly, hasil perhitungan)
      kumitateColumns.add(PlutoColumn(
        title: "PART",
        field: "${time}_part_calc",
        type: PlutoColumnType.text(),
        width: 90,
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
          final value = rendererContext.cell.value?.toString() ?? '';
          final targetPerJam = hourlyTargets[time] ?? 0.0;
          final partTarget = targetPerJam * 2;
          BoxDecoration baseDecoration = BoxDecoration(
            color: Colors.blue.shade50,
            border: Border(
              right: BorderSide(color: Colors.blue.shade800, width: 0.5),
            ),
          );
          if (value.isEmpty) {
            return Container(
              height: 30,
              decoration: baseDecoration,
              alignment: Alignment.center,
              child: Text('', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
            );
          }
          if (value.contains(',')) {
            final parts = value.split(',');
            final part1 = int.tryParse(parts[0].trim()) ?? 0;
            final part2 = parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 0 : 0;
            // Jika tidak ada data, warna tetap biru
            final color1 = parts[0].trim().isEmpty || part1 == 0 
                ? Colors.blue.shade50 
                : (part1 >= partTarget ? Colors.green.shade200 : Colors.red.shade200);
            final color2 = parts.length <= 1 || parts[1].trim().isEmpty || part2 == 0 
                ? Colors.blue.shade50 
                : (part2 >= partTarget ? Colors.green.shade200 : Colors.red.shade200);
            return Container(
              height: 30,
              decoration: baseDecoration,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      alignment: Alignment.center,
                      child: Text(parts[0].trim(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
                      decoration: BoxDecoration(
                        color: color1,
                        border: Border(
                          right: BorderSide(color: Colors.blue.shade800, width: 1),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      alignment: Alignment.center,
                      child: Text(parts.length > 1 ? parts[1].trim() : '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
                      decoration: BoxDecoration(
                        color: color2,
                      ),
                    ),
                  ),
                ],
              ),
            );
          } else {
            final part1 = int.tryParse(value) ?? 0;
            // Jika tidak ada data, warna tetap biru
            final color1 = value.isEmpty || part1 == 0 
                ? Colors.blue.shade50 
                : (part1 >= partTarget ? Colors.green.shade200 : Colors.red.shade200);
            return Container(
              height: 30,
              decoration: baseDecoration.copyWith(color: color1),
              alignment: Alignment.center,
              child: Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
            );
          }
        },
      ));

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
            final target = hourlyTargets[time] ?? 0.0;
            final color = target > 0 
                ? (total >= target ? Colors.green : Colors.red)
                : Colors.black;
            
            return Container(
              height: 30,
              decoration: BoxDecoration(
                color: Colors.yellow.shade100,
                border: Border(
                  left: BorderSide(color: Colors.blue.shade800, width: 0.5),
                  right: BorderSide(color: Colors.blue.shade800, width: 0.5),
                ),
              ),
              child: Center(
                child: Text(
                  total.toString(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
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
            double cumulativeTarget = 0.0;
            for (var slot in timeSlots) {
              cumulativeTarget += (hourlyTargets[slot] ?? 0.0);
              if (slot == time) break;
            }
            
            final color = cumulativeTarget > 0 
                ? (cumulative >= cumulativeTarget ? Colors.green : Colors.red)
                : Colors.black;
            
            return Container(
              height: 30,
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                border: Border(
                  left: BorderSide(color: Colors.blue.shade800, width: 0.5),
                  right: BorderSide(color: Colors.blue.shade800, width: 0.5),
                ),
              ),
              child: Center(
                child: Text(
                  cumulative.toString(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            );
          },
        ),
      );

      // Modified Stock column for each time slot with color coding
      kumitateColumns.add(
        PlutoColumn(
          title: "Stock",
          field: "${time}_stock",
          type: PlutoColumnType.number(),
          width: 80,
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
            final stock = rendererContext.cell.value as int;
            Color textColor;
            
            if (stock < 0) {
              textColor = Colors.red;
            } else if (stock >= 0 && stock <= 5) {
              textColor = Colors.orange;
            } else {
              textColor = Colors.green;
            }
            
            return Container(
              height: 30,
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                border: Border(
                  left: BorderSide(color: Colors.blue.shade800, width: 0.5),
                  right: BorderSide(color: Colors.blue.shade800, width: 0.5),
                ),
              ),
              child: Center(
                child: Text(
                  stock.toString(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
            );
          },
        ),
      );

      // Hitung target akumulatif
      double cumulativeTarget = 0.0;
      for (var slot in timeSlots) {
        cumulativeTarget += (hourlyTargets[slot] ?? 0.0);
        if (slot == time) break;
      }
      // Waktu mulai dari tengah, lalu spasi panjang, lalu target di ujung kanan
      String groupTitle = ''.padLeft(60) + time + ''.padRight(40) + 'Target: ${cumulativeTarget.round()}';
      kumitateColumnGroups.add(
        PlutoColumnGroup(
          title: groupTitle,
          backgroundColor: Colors.blue.shade300,
          fields: [
            "${time}_1", "${time}_2", "${time}_3", "${time}_4", "${time}_5",
            "${time}_part_calc",
            "${time}_total", "${time}_cumulative", "${time}_stock"
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
          final target = dailyTarget ?? 0.0;
          final color = target > 0 
              ? (total >= target ? Colors.green : Colors.red)
              : Colors.black;
              
          return Container(
            height: 30,
            decoration: BoxDecoration(
              color: Colors.orange.shade200,
              border: Border(
                left: BorderSide(color: Colors.blue.shade800, width: 0.5),
                right: BorderSide(color: Colors.blue.shade800, width: 0.5),
              ),
            ),
            child: Center(
              child: Text(
                total.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          );
        },
      ),
    );

    kumitateRows = [];
    // Filter: hanya tampilkan process dengan sequence != 0
    final filteredKumitateData = kumitateData.where((e) => (e['sequence'] ?? 0) != 0).toList();
    if (filteredKumitateData.isNotEmpty) {
      for (int i = 0; i < filteredKumitateData.length; i++) {
        final entry = filteredKumitateData[i];
        final stockPagi = entry["stock_pagi"] as Map<String, dynamic>? ?? {
          '1': 0, '2': 0, '3': 0, '4': 0, '5': 0, 'stock': 0
        };
        final processName = (entry["process_name"] ?? '').toString();
        final part1 = (entry["part"] ?? '').toString();
        final part2 = (entry["part_2"] ?? '').toString();

        final cells = <String, PlutoCell>{
          "process_name": PlutoCell(value: entry["process_name"]),
          "type": PlutoCell(value: "Kumitate"),
          "stock_20min": PlutoCell(
            value: entry["stock_20min"] is String 
                ? int.tryParse(entry["stock_20min"] as String) ?? 0
                : (entry["stock_20min"] as num?)?.toInt() ?? 0,
          ),
          "stock_pagi_1": PlutoCell(value: stockPagi['1'] ?? 0),
          "stock_pagi_2": PlutoCell(value: stockPagi['2'] ?? 0),
          "stock_pagi_3": PlutoCell(value: stockPagi['3'] ?? 0),
          "stock_pagi_4": PlutoCell(value: stockPagi['4'] ?? 0),
          "stock_pagi_5": PlutoCell(value: stockPagi['5'] ?? 0),
          "part": PlutoCell(value: entry["part"] ?? ""),
          "part_2": PlutoCell(value: entry["part_2"] ?? ""),
          "stock_pagi_stock": PlutoCell(value: stockPagi['stock'] ?? 0),
        };

        int grandTotal = 0;

        for (final time in timeSlots) {
          int timeSlotTotal = 0;

          for (int i2 = 1; i2 <= 5; i2++) {
            final count = (entry["${time}_$i2"] as num?)?.toInt() ?? 0;
            timeSlotTotal += count;
            cells["${time}_$i2"] = PlutoCell(value: count);
          }

          // PART CALCULATION (readonly, sesuai rumus, hanya jika part di stock pagi ada)
          String partCalc = '';
          // Helper: cari proses OUT terkait di partData
          int getPartOutAccum(String outName) {
            final out = partData.firstWhere(
              (e) => (e['process_name'] ?? '').toString().toLowerCase() == outName.toLowerCase(),
              orElse: () => {},
            );
            int cumulativeValue = (out["${time}_cumulative"] as int?) ?? 0;
            
            // Jika proses adalah Sode atau Cuff, bagi nilai cumulative dengan 2
            if (dividedByTwoProcesses.contains(outName)) {
              cumulativeValue = (cumulativeValue / 2).floor();
            }
            
            return cumulativeValue;
          }
          int getThisAccum() => (entry["${time}_cumulative"] as int?) ?? 0;
          bool hasPart1 = part1.isNotEmpty && part1 != '0';
          bool hasPart2 = part2.isNotEmpty && part2 != '0';
          int pagi1 = int.tryParse(part1) ?? 0;
          int pagi2 = int.tryParse(part2) ?? 0;
          if (hasPart1 || hasPart2) {
            if (processName.contains("Maekata")) {
              int maemiOut = getPartOutAccum('Maemi OUT');
              int ushiroOut = getPartOutAccum('Ushiro OUT');
              int thisAccum = getThisAccum();
              if (hasPart1) {
                partCalc = '${pagi1 + maemiOut - thisAccum}';
              }
              if (hasPart2) {
                if (partCalc.isNotEmpty) partCalc += ', ';
                partCalc += '${pagi2 + ushiroOut - thisAccum}';
              }
            } else if (processName.contains("Eri")) {
              int eriOut = getPartOutAccum('Eri OUT');
              int thisAccum = getThisAccum();
              if (hasPart1) partCalc = '${pagi1 + eriOut - thisAccum}';
            } else if (processName.contains("Sode")) {
              int sodeOut = getPartOutAccum('Sode OUT');
              int thisAccum = getThisAccum();
              if (hasPart1) partCalc = '${pagi1 + sodeOut - thisAccum}';
            } else if (processName.contains("Cuff")) {
              int cuffOut = getPartOutAccum('Cuff OUT');
              int thisAccum = getThisAccum();
              if (hasPart1) partCalc = '${pagi1 + cuffOut - thisAccum}';
            }
          } else {
            partCalc = '';
          }
          cells["${time}_part_calc"] = PlutoCell(value: partCalc);

          grandTotal += timeSlotTotal;
          cells["${time}_total"] = PlutoCell(value: timeSlotTotal);
          cells["${time}_cumulative"] = PlutoCell(value: entry["${time}_cumulative"] ?? 0);
          
          // Calculate stock for each time slot
          if (i == 0) {
            // First row (process) always has 0 stock
            cells["${time}_stock"] = PlutoCell(value: 0);
          } else {
            // For other rows: stock = stock_pagi_stock + previous process cumulative - current process cumulative
            final previousProcess = filteredKumitateData[i-1];
            final previousCumulative = previousProcess["${time}_cumulative"] ?? 0;
            final currentCumulative = entry["${time}_cumulative"] ?? 0;
            // stock_pagi_stock = stock_pagi_1 + ... + stock_pagi_5
            final pagiStock = (cells['stock_pagi_1']?.value ?? 0) + (cells['stock_pagi_2']?.value ?? 0) + (cells['stock_pagi_3']?.value ?? 0) + (cells['stock_pagi_4']?.value ?? 0) + (cells['stock_pagi_5']?.value ?? 0);
            cells["stock_pagi_stock"] = PlutoCell(value: pagiStock);
            final stockValue = pagiStock + previousCumulative - currentCumulative;
            cells["${time}_stock"] = PlutoCell(value: stockValue);
          }
        }

        cells["grand_total"] = PlutoCell(value: grandTotal);
        kumitateRows.add(PlutoRow(cells: cells));
      }
    }
  }

  void _buildPartColumnsAndRows() {
    double cumulativeTarget = 0.0;
    partColumnGroups = [
      for (final time in visibleTimeSlots)
        (() {
          cumulativeTarget += (hourlyTargets[time] ?? 0.0);
          return PlutoColumnGroup(
            title: '${cumulativeTarget.round()}',
            backgroundColor: Colors.blue.shade300,
            fields: ['${time}_cumulative'],
          );
        })(),
    ];
    partColumns = [
      PlutoColumn(
        title: "PROCESS",
        field: "process_name",
        type: PlutoColumnType.text(),
        width: 260,
        titleTextAlign: PlutoColumnTextAlign.center,
        backgroundColor: Colors.blue.shade300,
        enableColumnDrag: false,
        enableContextMenu: false,
        enableSorting: false,
        enableEditingMode: false,
        renderer: (ctx) {
          final processName = ctx.cell.value.toString();
          final rowColor = getPartRowColor(processName);
          final hiragana = partProcessHiragana[processName];
          return Container(
            color: rowColor,
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(processName, style: TextStyle(fontWeight: FontWeight.bold)),
                      if (hiragana != null) ...[
                        SizedBox(width: 6),
                        Text('($hiragana)', style: TextStyle(fontSize: 13, color: Colors.black)),
                      ],
                    ],
                  ),
                ),
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
            ),
          );
        },
      ),
      
      for (final time in visibleTimeSlots)
        PlutoColumn(
          title: time,
          field: "${time}_cumulative",
          type: PlutoColumnType.number(),
          width: 70,
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
            double cumulativeTarget = 0.0;
            for (var slot in visibleTimeSlots) {
              cumulativeTarget += (hourlyTargets[slot] ?? 0.0);
              if (slot == time) break;
            }
            
            final color = cumulativeTarget > 0 
                ? (cumulative >= cumulativeTarget ? Colors.green : Colors.red)
                : Colors.black;
            
            return Container(
              height: 30,
              child: Center(
                child: Text(
                  cumulative.toString(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
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
            child: Center(
              child: Text(
                rendererContext.cell.value.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
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

      for (final time in visibleTimeSlots) {
          for (int i = 1; i <= 2; i++) {
            entry["${time}_$i"] = (entry["${time}_$i"] as num?)?.toInt() ?? 0;
          }
          
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

      // Tentukan visibleTimeSlots: hanya timeslot yang ada data di salah satu proses
      Set<String> slots = {};
      for (final data in [...kumitateData, ...partData]) {
        for (final slot in timeSlots) {
          for (int i = 1; i <= 5; i++) {
            if ((data["${slot}_$i"] ?? 0) != 0) {
              slots.add(slot);
            }
          }
        }
      }
      visibleTimeSlots = timeSlots.where((t) => slots.contains(t)).toList();


    if (kumitateData.isEmpty && partData.isEmpty) {
      setState(() {
        noDataAvailable = true;
      });
    } else {
      _buildKumitateColumnsAndRows();
      _buildPartColumnsAndRows();
      _buildProsesTable();
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
    if (type == 'Kumitate' || type == 'Part') {
      // Untuk Kumitate dan Part, tampilkan data per nomor line saja (bukan akumulatif)
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
              children: [
                ...List.generate(lineBarsData.length, (index) {
                  final colors = [
                    ...lineColors
                  ];
                  final labels = [
                    'Line 1', 'Line 2', 'Line 3', 'Line 4', 'Line 5'
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
              ],
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
      final excelFile = excel.Excel.createExcel();
      final sheet = excelFile['Sheet1'];

      // Header row
      sheet.appendRow([
        excel.TextCellValue('TYPE'), 
        excel.TextCellValue('PROCESS'),
        ...timeSlots.map((e) => excel.TextCellValue(e)),
        excel.TextCellValue('Stock sebelum kensa (pagi)'),
        excel.TextCellValue('Stock 20 menit'),
        excel.TextCellValue('Stock Pagi 1'),
        excel.TextCellValue('Stock Pagi 2'), 
        excel.TextCellValue('Stock Pagi 3'),
        excel.TextCellValue('Stock Pagi 4'),
        excel.TextCellValue('PART 1'),
        excel.TextCellValue('PART 2'),
        excel.TextCellValue('Stock')
      ]);

      // Kumitate data
      for (final row in kumitateRows) {
        sheet.appendRow([
          excel.TextCellValue('Kumitate'),
          excel.TextCellValue(row.cells['process_name']!.value.toString()),
          ...timeSlots.map((time) => excel.IntCellValue(row.cells['${time}_cumulative']!.value as int)),
          excel.IntCellValue(0), // Stock sebelum kensa
          excel.IntCellValue(row.cells['stock_20min']!.value as int),
          excel.IntCellValue(row.cells['stock_pagi_1']!.value as int),
          excel.IntCellValue(row.cells['stock_pagi_2']!.value as int),
          excel.IntCellValue(row.cells['stock_pagi_3']!.value as int),
          excel.IntCellValue(row.cells['stock_pagi_4']!.value as int),
          excel.TextCellValue(row.cells['part']?.value?.toString() ?? ''),
          excel.TextCellValue(row.cells['part_2']?.value?.toString() ?? ''),
          excel.IntCellValue(row.cells['stock_pagi_stock']!.value as int),
        ]);
      }

      // Part data
      for (final row in partRows) {
        sheet.appendRow([
          excel.TextCellValue('Part'),
          excel.TextCellValue(row.cells['process_name']!.value.toString()),
          ...timeSlots.map((time) {
            int value = row.cells['${time}_cumulative']!.value as int;
            if (dividedByTwoProcesses.contains(row.cells['process_name']!.value.toString())) {
              value = (value / 2).floor();
            }
            return excel.IntCellValue(value);
          }),
          excel.IntCellValue(row.cells['belumKensa']!.value as int),
          excel.IntCellValue(0), // Stock 20 menit
          excel.IntCellValue(0), // Stock Pagi 1
          excel.IntCellValue(0), // Stock Pagi 2
          excel.IntCellValue(0), // Stock Pagi 3
          excel.IntCellValue(0), // Stock Pagi 4
          excel.TextCellValue(''), // PART 1
          excel.TextCellValue(''), // PART 2
          excel.IntCellValue(0), // Stock
        ]);
      }

      // Save file
      final bytes = excelFile.save()!;
      final dateStr = DateFormat('yyyyMMdd').format(selectedDate);
      final fileName = 'Counter_Data_Line${selectedLine}_$dateStr.xlsx';
      
      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: Uint8List.fromList(bytes),
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported to $fileName')),
        );
      }
    } catch (e) {
      print('Export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: ${e.toString()}')),
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
      
      // Save Kumitate stock 20 menit, stock pagi, dan PART
      for (final row in kumitateRows) {
        final processName = row.cells['process_name']!.value.toString().replaceAll(' ', '_');
        final docRef = FirebaseFirestore.instance
            .collection('counter_sistem')
            .doc(dateStr)
            .collection(selectedLine)
            .doc('Kumitate')
            .collection('Process')
            .doc(processName);

        int stock20min = 0;
        final cellValue = row.cells['stock_20min']?.value;
        if (cellValue is int) {
          stock20min = cellValue;
        } else if (cellValue is String) {
          stock20min = int.tryParse(cellValue) ?? 0;
        } else if (cellValue is num) {
          stock20min = cellValue.toInt();
        }

        // Get stock pagi values
        final stockPagi = {
          '1': row.cells['stock_pagi_1']?.value as int? ?? 0,
          '2': row.cells['stock_pagi_2']?.value as int? ?? 0,
          '3': row.cells['stock_pagi_3']?.value as int? ?? 0,
          '4': row.cells['stock_pagi_4']?.value as int? ?? 0,
          'stock': (row.cells['stock_pagi_1']?.value as int? ?? 0) +
                  (row.cells['stock_pagi_2']?.value as int? ?? 0) +
                  (row.cells['stock_pagi_3']?.value as int? ?? 0) +
                  (row.cells['stock_pagi_4']?.value as int? ?? 0),
        };

        // PART: logika split part1,part2 berlaku untuk semua baris
        String partValue = row.cells['part']?.value as String? ?? '';
        String partValue2 = row.cells['part_2']?.value as String? ?? '';
        if (partValue.contains(',')) {
          final values = partValue.split(',');
          partValue = values.isNotEmpty ? values[0].trim() : '';
          partValue2 = values.length > 1 ? values[1].trim() : '';
        }

        final updateData = {
          'stock_20min': stock20min,
          'stock_pagi': stockPagi,
          'part': {
            'part1': partValue,
            'part2': partValue2,
          },
        };
        batch.update(docRef, updateData);
      }
      
      await batch.commit();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Data berhasil disimpan!')),
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
      // Setelah selesai simpan, refresh data
      await loadData();
      await _loadTargets();
      setState(() => isSaving = false);
    }
  }

  Future<void> selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(Duration(days: 1)),
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
            tooltip: "Save Data",
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
                                          'Target: ${dailyTarget != null ? dailyTarget!.round() : '-'}  ',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                        ),
                                        Text(
                                          'Per Jam: ${dailyTarget != null ? (dailyTarget! / 8).round() : '-'}',
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
                      if (kumitateRows.isNotEmpty) ...[
                        _buildTableWidget(
                          title: 'KUMITATE',
                          columns: kumitateColumns,
                          rows: kumitateRows,
                          columnGroups: kumitateColumnGroups,
                        ),
                        SizedBox(height: 30),
                      ],
                      if (partRows.isNotEmpty) ...[
                        _buildTableWidget(
                          title: 'PART',
                          columns: partColumns,
                          rows: partRows,
                          columnGroups: partColumnGroups,
                        ),
                        SizedBox(height: 30),
                      ],
                      if (processNames.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTableWidget(
                              title: 'AKUMULATIF LINE',
                              columns: prosesColumns,
                              rows: prosesRows,
                              columnGroups: prosesColumnGroups,
                              processDropdown: DropdownButton<String>(
                                value: selectedProcessName,
                                items: processNames.map((name) => DropdownMenuItem(
                                  value: name,
                                  child: Text(name),
                                )).toList(),
                                onChanged: (value) {
                                  if (value != null && value != selectedProcessName) {
                                    setState(() {
                                      selectedProcessName = value;
                                      _buildProsesTable();
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
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
    Widget? processDropdown,
  }) {
  const rowHeight = 30.0;
  const headerHeight = 40.0;
  const columnHeaderHeight = 30.0;
  // Hitung tinggi tabel dinamis sesuai jumlah baris
  // Tinggi tabel otomatis sesuai jumlah baris
  final totalHeight = headerHeight + columnHeaderHeight + (rows.length * rowHeight) + 6;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0), // hilangkan padding vertikal
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
          if (processDropdown != null)
            Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Text('Pilih Proses: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.blue.shade500, width: 1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        canvasColor: Colors.white,
                      ),
                      child: processDropdown,
                    ),
                  ),
                ],
              ),
            ),
          GestureDetector(
            onTap: () {
              FocusScope.of(context).unfocus();
              setState(() {});
            },
            child: Container(
              constraints: BoxConstraints(
                minHeight: totalHeight,
                maxHeight: totalHeight,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue.shade800),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
              ),
              child: PlutoGrid(
                key: ValueKey('${title}_${selectedDate}_${selectedLine}_${title == 'AKUMULATIF LINE' ? (selectedProcessName ?? '') : ''}'),
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
                    isAlwaysShown: true,
                    scrollbarThickness: 5,
                  ),
                  enableMoveHorizontalInEditing: true,
                  enterKeyAction: PlutoGridEnterKeyAction.editingAndMoveDown,
                ),
                // Pewarnaan baris khusus untuk PART
                rowColorCallback: title == 'PART'
                    ? (PlutoRowColorContext rowContext) {
                        final processName = rowContext.row.cells['process_name']?.value?.toString() ?? '';
                        return getPartRowColor(processName) ?? Colors.transparent;
                      }
                    : null,
                onChanged: (PlutoGridOnChangedEvent event) {
                  if (event.column.field == 'belumKensa' || 
                      event.column.field == 'stock_20min' ||
                      event.column.field == 'part' ||
                      event.column.field == 'part_2' ||
                      event.column.field.startsWith('stock_pagi_')) {
                    final stateManager = title == 'PART' 
                        ? _partStateManager 
                        : _kumitateStateManager;
                    
                    if (stateManager != null) {
                      if (event.column.field == 'part' || event.column.field == 'part_2') {
                        stateManager.changeCellValue(
                          event.row.cells[event.column.field]!,
                          event.value.toString(),
                          notify: false,
                        );
                      } else {
                        final intValue = int.tryParse(event.value.toString()) ?? 0;
                        stateManager.changeCellValue(
                          event.row.cells[event.column.field]!,
                          intValue,
                          notify: false,
                        );
                      }

                      if (event.column.field.startsWith('stock_pagi_') && !event.column.field.endsWith('stock')) {
                        final pagi1 = event.row.cells['stock_pagi_1']?.value as int? ?? 0;
                        final pagi2 = event.row.cells['stock_pagi_2']?.value as int? ?? 0;
                        final pagi3 = event.row.cells['stock_pagi_3']?.value as int? ?? 0;
                        final pagi4 = event.row.cells['stock_pagi_4']?.value as int? ?? 0;
                        final pagiStock = pagi1 + pagi2 + pagi3 + pagi4;
                        stateManager.changeCellValue(
                          event.row.cells['stock_pagi_stock']!,
                          pagiStock,
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