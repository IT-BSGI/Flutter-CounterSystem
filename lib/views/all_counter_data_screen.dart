import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:excel/excel.dart' as excel;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import 'dart:async';

class AllCounterDataScreen extends StatefulWidget {
  @override
  _AllCounterDataScreenState createState() => _AllCounterDataScreenState();
}

class _AllCounterDataScreenState extends State<AllCounterDataScreen> {
  // Untuk tabel Proses Kumitate (akumulatif 12345 per timeslot)
  List<PlutoColumn> prosesColumns = [];
  List<PlutoRow> prosesRows = [];
  String? selectedProcessName;
  List<String> processNames = [];

  // Untuk tabel Proses Part (akumulatif 12345 per timeslot)
  List<PlutoColumn> partProsesColumns = [];
  List<PlutoRow> partProsesRows = [];
  String? selectedPartProcessName;
  List<String> partProcessNames = [];
  List<PlutoColumnGroup> partProsesColumnGroups = [];

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
    
    // Urutkan berdasarkan urutan proses yang ditentukan
    prosesList.sort((a, b) {
      final aIndex = kumitateProcessOrder.indexOf(a['process_name'] ?? '');
      final bIndex = kumitateProcessOrder.indexOf(b['process_name'] ?? '');
      if (aIndex == -1) return 1;
      if (bIndex == -1) return -1;
      return aIndex.compareTo(bIndex);
    });
    
    // Ambil hanya proses dengan sequence != 0 (sesuai tabel kumitate)
    processNames = prosesList
      .where((e) => (e['sequence'] ?? 0) != 0)
      .map((e) => e["process_name"]?.toString() ?? "")
      .where((e) => e.isNotEmpty)
      .toList();
      
    // Urutkan processNames berdasarkan urutan yang ditentukan
    processNames.sort((a, b) {
      final aIndex = kumitateProcessOrder.indexOf(a);
      final bIndex = kumitateProcessOrder.indexOf(b);
      if (aIndex == -1) return 1;
      if (bIndex == -1) return -1;
      return aIndex.compareTo(bIndex);
    });
    
    // Pastikan selectedProcessName selalu valid
    if (selectedProcessName == null || !processNames.contains(selectedProcessName)) {
      selectedProcessName = processNames.isNotEmpty ? processNames.first : null;
    }
    
    final proses = prosesList.firstWhere(
      (e) => e["process_name"]?.toString() == selectedProcessName,
      orElse: () => {},
    );
    
    // Tentukan visibleTimeSlots untuk proses: hanya timeslot yang ada data di proses terpilih
    Set<String> slotsWithData = {};
    for (final time in timeSlots) {
      bool hasData = false;
      for (int i = 1; i <= 5; i++) {
        final val = proses["${time}_$i"];
        if (val != null && val != 0 && val.toString() != '0') {
          hasData = true;
          break;
        }
      }
      if (hasData) {
        slotsWithData.add(time);
      }
    }
    final visibleTimeSlotsProses = timeSlots.where((t) => slotsWithData.contains(t)).toList();
    
    for (final time in visibleTimeSlotsProses) {
      final cells = <String, PlutoCell>{};
      cells["time_slot"] = PlutoCell(value: time);
      for (int i = 1; i <= 5; i++) {
        // Jam: hanya perolehan di jam itu saja
        final jamRaw = proses["${time}_$i"];
        final jamValue = jamRaw == null ? 0 : (jamRaw is int ? jamRaw : int.tryParse(jamRaw.toString()) ?? 0);
        // Ak: akumulatif sampai jam itu
        int akumulatif = 0;
        for (final t in visibleTimeSlotsProses) {
          final val = proses["${t}_$i"];
          if (t.compareTo(time) > 0) break;
          akumulatif += (val is int ? val : int.tryParse(val?.toString() ?? '0') ?? 0);
          if (t == time) break;
        }
        cells["line_${i}_jam"] = PlutoCell(value: jamValue);
        cells["line_${i}_ak"] = PlutoCell(value: akumulatif);
      }
      prosesRows.add(PlutoRow(cells: cells));
    }

    this.prosesColumns = prosesColumns;
    this.prosesRows = prosesRows;
    this.prosesColumnGroups = prosesColumnGroups;
  }

  // Build tabel Proses Part: timeslot, per line (1-3) Jam & Ak
  // Data Part menyimpan ${time}_1, ${time}_2, ${time}_3 dan ${time}_cumulative
  void _buildPartProsesTable() {
    // Kolom: TIME, lalu per line (1-3) grup: Jam, Ak
    partProsesColumns = [
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
      for (int i = 1; i <= 3; i++) ...[
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
      ],
    ];

    // Group kolom per line (1-3)
    partProsesColumnGroups = [
      for (int i = 1; i <= 3; i++)
        PlutoColumnGroup(
          title: '$i',
          backgroundColor: Colors.blue.shade300,
          fields: ['line_${i}_jam', 'line_${i}_ak'],
        ),
    ];

    // Ambil semua process_name dari partData
    partProcessNames = partData
        .map((e) => e["process_name"]?.toString() ?? "")
        .where((e) => e.isNotEmpty)
        .toList();

    // Urutkan berdasarkan partProcessOrder
    partProcessNames.sort((a, b) {
      final aIndex = partProcessOrder.indexOf(a);
      final bIndex = partProcessOrder.indexOf(b);
      if (aIndex == -1) return 1;
      if (bIndex == -1) return -1;
      return aIndex.compareTo(bIndex);
    });

    // Pastikan selectedPartProcessName selalu valid
    if (selectedPartProcessName == null || !partProcessNames.contains(selectedPartProcessName)) {
      selectedPartProcessName = partProcessNames.isNotEmpty ? partProcessNames.first : null;
    }

    final partProses = partData.firstWhere(
      (e) => e["process_name"]?.toString() == selectedPartProcessName,
      orElse: () => {},
    );

    // Tentukan visibleTimeSlots: hanya timeslot yang ada data per-line (1-3) > 0
    Set<String> slotsWithData = {};
    for (final time in visibleTimeSlots) {
      for (int i = 1; i <= 3; i++) {
        final val = partProses["${time}_$i"];
        if (val != null && val != 0 && val.toString() != '0') {
          slotsWithData.add(time);
          break;
        }
      }
    }
    final visibleTimeSlotsPartProses = visibleTimeSlots.where((t) => slotsWithData.contains(t)).toList();

    // Apakah proses ini dibagi 2
    final isDividedByTwo = dividedByTwoProcesses.contains(selectedPartProcessName);

    // Build rows
    partProsesRows = [];
    for (final time in visibleTimeSlotsPartProses) {
      final cells = <String, PlutoCell>{};
      cells["time_slot"] = PlutoCell(value: time);

      for (int i = 1; i <= 3; i++) {
        // Jam: perolehan di timeslot ini untuk line i
        final jamRaw = partProses["${time}_$i"];
        int jamInt = jamRaw is int ? jamRaw : int.tryParse(jamRaw?.toString() ?? '') ?? 0;
        if (isDividedByTwo) jamInt = (jamInt / 2).floor();

        // Ak: akumulatif line i dari awal hingga timeslot ini
        int akumulatif = 0;
        for (final t in visibleTimeSlotsPartProses) {
          final val = partProses["${t}_$i"];
          final valInt = val is int ? val : int.tryParse(val?.toString() ?? '') ?? 0;
          akumulatif += valInt;
          if (t == time) break;
        }
        if (isDividedByTwo) akumulatif = (akumulatif / 2).floor();

        cells["line_${i}_jam"] = PlutoCell(value: jamInt);
        cells["line_${i}_ak"] = PlutoCell(value: akumulatif);
      }

      partProsesRows.add(PlutoRow(cells: cells));
    }

    this.partProsesColumns = partProsesColumns;
    this.partProsesRows = partProsesRows;
    this.partProsesColumnGroups = partProsesColumnGroups;
  }
  
  List<PlutoColumnGroup> prosesColumnGroups = [];
  
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
  bool noDataAvailable = false;

  final List<String> timeSlots = [
    "08:30", "09:30", "10:30", "11:30", "12:00",
    "13:00", "14:00", "15:00", "16:00",
    // Overtime slots (start at 17:25)
    "17:25", "17:55",
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

    "11:30": "12:00",
    "11:45": "12:00",
    "12:00": "12:00",

    "12:15": "13:00",
    "12:30": "13:00",
    "12:45": "13:00",

    "13:00": "14:00",
    "13:15": "14:00",
    "13:30": "14:00",
    "13:45": "14:00",

    "14:00": "15:00",
    "14:15": "15:00", 
    "14:30": "15:00",
    "14:45": "15:00",

    "15:00": "16:00",
    "15:15": "16:00",
    "15:30": "16:00", 
    "15:45": "16:00",
    "16:00": "16:00",

    // Map post-16:00 minutes into overtime slots
    "16:15": "17:25",
    "16:30": "17:25",
    "16:45": "17:25",
    "17:00": "17:25",
    "17:15": "17:25",
    "17:30": "17:25",

    "17:45": "17:55",
    "18:00": "17:55",
    "18:15": "17:55",
    "18:30": "17:55",
    "18:45": "17:55",
    "19:00": "17:55",
    "19:15": "17:55",
    "19:30": "17:55",
    "19:45": "17:55",
    "20:00": "17:55",
  };

  final List<String> partProcessOrder = [
    "Maemi IN", "Maemi OUT", "Ushiro IN", "Ushiro OUT",
    "Eri IN", "Eri OUT", "Sode IN", "Sode OUT",
    "Cuff IN", "Cuff OUT",
  ];

  // Urutan proses Kumitate yang diinginkan
  final List<String> kumitateProcessOrder = [
    "Maekata Interlock",
    "Maekata Jinui",
    "Maekata Fuse",
    "Maekata JinuiFuse",
    "Eri Tsuke",
    "Pipping Eri Tsuke",
    "Overlock Eri Tsuke",
    "Itokiri Eri Tsuke",
    "Eri Fuse",
    "Epaulate Tsuke",
    "Sode Tsuke Interlock",
    "Karidome Waki",
    "Deodorant Tape",
    "Sode Tsuke Honnui",
    "Iron Sode Tsuke",
    "Sode Fuse",
    "Jinui Pocket Samping",
    "Sode Fuse 1mm",
    "Sode Fuse 8mm",
    "Wakinui Interlock",
    "Kazari Mae",
    "Anakagari Maetate",
    "Wakinui Nihonbari",
    "Loop Tsuke",
    "Kandome",
    "Hodoki Waki",
    "Shirushi Mitsumaki",
    "Iron Waki",
    "Jinui Waki",
    "Waki Fuse",
    "Sode Guchi Tome",
    "Sode Guchi Corong",
    "Surito",
    "Cuff Tsuke",
    "Cuff Anakagari",
    "Kazari Cuff",
    "Bottan Cuff",
    "Mitsumaki",
    "Gazet",
    "Bottan Tsuke",
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
    _setupAutoRefresh(showFullLoading: true);
  }

  // Stream subscriptions for auto-refresh
  StreamSubscription<DocumentSnapshot>? _parentDocSub;
  StreamSubscription<DocumentSnapshot>? _kumitateDocSub;
  StreamSubscription<DocumentSnapshot>? _partDocSub;
  List<StreamSubscription<QuerySnapshot>> _contractSubscriptions = [];

  Future<void> _loadTargets({bool showSpinner = false}) async {
    if (showSpinner) setState(() => isTargetLoading = true);
    
    final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
    final docRef = FirebaseFirestore.instance.collection('counter_sistem').doc(dateStr);

    try {
      final doc = await docRef.get();
      if (doc.exists) {
        final data = doc.data()!;
        final targetMap = data['target_map_$selectedLine'] as Map<String, dynamic>? ?? {};

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
                'time_perpcs': (value['time_perpcs'] as num?)?.toDouble() ?? 0.0,
              });
            }
          });

          // Urutkan styles berdasarkan key (style1, style2, dll)
          styles.sort((a, b) => a['key'].compareTo(b['key']));

          // Hitung target per slot untuk jam kerja normal.
          // Gunakan label `timeSlots` untuk kunci, dan alokasikan total productive seconds (8 jam = 28800s)
          // secara merata ke semua normal slots (non-overtime) agar perubahan timeslot tetap sinkron.
          // Overtime slots are now 17:25 and 17:55 only
          List<String> overtimeTimeSlots = ['17:25', '17:55'];
          List<String> normalTimeSlots = timeSlots.where((s) => !overtimeTimeSlots.contains(s)).toList();
          int currentTimeSlotIndex = 0;

          // Compute actual available seconds per normal slot by intersecting slot interval
          // with productive periods (07:30-12:00 and 12:30-16:00). This ensures slots
          // that are 30-min are handled correctly and allocation by time_perpcs is accurate.
          DateTime parseTime(String t) {
            final parts = t.split(':');
            return DateTime(2000, 1, 1, int.parse(parts[0]), int.parse(parts[1]));
          }

          DateTime morningStart = DateTime(2000, 1, 1, 7, 30);
          DateTime morningEnd = DateTime(2000, 1, 1, 12, 0);
          DateTime afternoonStart = DateTime(2000, 1, 1, 12, 30);
          DateTime afternoonEnd = DateTime(2000, 1, 1, 16, 1);
            // Total productive seconds across morning and afternoon (used as a fallback)
            // Note: afternoonEnd is 16:01 to include the full 16:00 hour
            double productiveSeconds = morningEnd.difference(morningStart).inSeconds.toDouble()
              + (afternoonEnd.difference(afternoonStart).inSeconds - 60).toDouble();

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
            final overlapStart1 = start.isAfter(morningStart) ? start : morningStart;
            final overlapEnd1 = end.isBefore(morningEnd) ? end : morningEnd;
            if (overlapEnd1.isAfter(overlapStart1)) {
              avail += overlapEnd1.difference(overlapStart1).inSeconds.toDouble();
            }
            // overlap with afternoon
            final overlapStart2 = start.isAfter(afternoonStart) ? start : afternoonStart;
            final overlapEnd2 = end.isBefore(afternoonEnd) ? end : afternoonEnd;
            if (overlapEnd2.isAfter(overlapStart2)) {
              avail += overlapEnd2.difference(overlapStart2).inSeconds.toDouble();
            }

            slotRemainingSeconds[endLabel] = avail;
          }

          for (var style in styles) {
            double remainingQuantity = style['quantity'];
            double timePerPcs = style['time_perpcs'];

            if (timePerPcs <= 0) continue;

            // Alokasikan potongan style ke slot saat ini dan selanjutnya berdasarkan sisa detik
            while (remainingQuantity > 0 && currentTimeSlotIndex < normalTimeSlots.length) {
              final currentTimeSlot = normalTimeSlots[currentTimeSlotIndex];
              double slotSec = slotRemainingSeconds[currentTimeSlot] ?? (productiveSeconds / (normalTimeSlots.isNotEmpty ? normalTimeSlots.length : 1));

              if (slotSec <= 1e-9) {
                // Kalau slot habis, lanjut ke slot berikutnya
                currentTimeSlotIndex++;
                continue;
              }

              // Berapa pcs yang bisa diproduksi pada sisa detik slot ini
              final possiblePieces = slotSec / timePerPcs;

              // Jika tidak bisa memproduksi satupun (timePerPcs > slotSec sangat besar), maju ke slot berikutnya
              if (possiblePieces <= 1e-9) {
                currentTimeSlotIndex++;
                continue;
              }

              final allocated = possiblePieces >= remainingQuantity ? remainingQuantity : possiblePieces;

              calculatedHourlyTargets[currentTimeSlot] = (calculatedHourlyTargets[currentTimeSlot] ?? 0.0) + allocated;
              remainingQuantity -= allocated;
              totalDailyTarget += allocated;

              // Kurangi sisa detik slot
              slotSec -= allocated * timePerPcs;
              slotRemainingSeconds[currentTimeSlot] = slotSec;

              // Jika slot habis, pindah ke slot berikutnya; jika tidak, artinya style habis
              if (slotSec <= 1e-9) {
                currentTimeSlotIndex++;
              }
            }

            // Jika masih ada sisa quantity tapi waktu normal sudah habis, hentikan proses
            if (remainingQuantity > 0 && currentTimeSlotIndex >= normalTimeSlots.length) {
              break;
            }
          }

          // Hitung overtime
          if (targetMap.containsKey('overtime')) {
            final overtimeData = targetMap['overtime'] as Map<String, dynamic>;
            double overtimeQuantity = (overtimeData['quantity'] as num?)?.toDouble() ?? 0.0;
            double overtimeTimePerPcs = (overtimeData['time_perpcs'] as num?)?.toDouble() ?? 0.0;

            if (overtimeTimePerPcs > 0 && overtimeQuantity > 0) {
              // Use overtime slots defined above (30-min each)
              List<String> overtimeTimeSlots = ['16:25', '16:55', '17:25', '17:55'];
              double remainingOvertime = overtimeQuantity;

              // Inisialisasi sisa detik overtime per slot (30 menit per overtime slot)
              final Map<String, double> overtimeSlotSec = { for (var s in overtimeTimeSlots) s: 1800.0 };

              int otIndex = 0;
              while (remainingOvertime > 0 && otIndex < overtimeTimeSlots.length) {
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
          final target = data['target_$selectedLine'];
          if (target is num) {
            totalDailyTarget = target.toDouble();
            // Distribusikan total daily target ke normal slots (non-overtime)
            List<String> overtimeTimeSlots = ['16:25', '16:55', '17:25', '17:55'];
            final normalSlots = timeSlots.where((s) => !overtimeTimeSlots.contains(s)).toList();
            final perSlot = normalSlots.isNotEmpty ? totalDailyTarget / normalSlots.length : 0.0;
            calculatedHourlyTargets = {
              for (var s in timeSlots) s: (normalSlots.contains(s) ? perSlot : 0.0),
            };
          }
        }

        setState(() {
          dailyTarget = totalDailyTarget;
          hourlyTargets = calculatedHourlyTargets;
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
      if (showSpinner) setState(() => isTargetLoading = false);
    }
  }

  // METODE YANG SAMA PERSIS DENGAN counter_table_screen.dart
  Future<List<Map<String, dynamic>>> fetchCounterData(String date, String line, String type) async {
    try {
      // Dapatkan semua kontrak yang tersedia
      final parentDocRef = FirebaseFirestore.instance
          .collection('counter_sistem')
          .doc(date)
          .collection(line)
          .doc(type);

      final parentDoc = await parentDocRef.get();
      
      if (!parentDoc.exists) {
        print('No parent document found for Line $line, Type $type on $date');
        return [];
      }

      // Ambil semua kontrak yang tersedia
      final kontrakArray = parentDoc.data()?['Kontrak'] as List<dynamic>?;
      final contractNames = (kontrakArray ?? ['Process'])
          .where((item) => item != null && item.toString().isNotEmpty)
          .map((item) => item.toString())
          .toList();

      if (contractNames.isEmpty) {
        print('No contracts found for Line $line, Type $type on $date');
        return [];
      }

      print('Processing contracts for $type: $contractNames');

      // Map untuk menggabungkan data dari semua kontrak
      final Map<String, Map<String, dynamic>> mergedData = {};
  final maxLines = type == 'Part' ? 3 : 5;

      // Loop melalui semua kontrak dan gabungkan data
      for (final contract in contractNames) {
        final processRef = FirebaseFirestore.instance
            .collection('counter_sistem')
            .doc(date)
            .collection(line)
            .doc(type)
            .collection(contract);

        final snapshot = await processRef.get();

        if (snapshot.docs.isEmpty) {
          print('No documents found for Line $line, Contract $contract, Type $type on $date');
          continue;
        }

        for (var doc in snapshot.docs) {
          final processData = doc.data();
          final processName = doc.id.replaceAll('_', ' ');
          final partData = processData['part'] ?? {};
          final part1 = partData is String ? partData : partData['part1'] ?? "";
          final part2 = partData is String ? "" : partData['part2'] ?? "";

          // Inisialisasi data proses jika belum ada
          if (!mergedData.containsKey(processName)) {
            mergedData[processName] = {
              "process_name": processName,
              "sequence": (processData['sequence'] as num?)?.toInt() ?? 0,
              "belumKensa": 0,
              "stock_20min": 0,
              "stock_pagi": {
                '1': 0, '2': 0, '3': 0, '4': 0, '5': 0, 'stock': 0
              },
              "part": part1,
              "part_2": part2,
              "type": type,
              "raw_data": {}, // Simpan raw data untuk processing
            };

            // Inisialisasi data timeslot
            for (final time in timeSlots) {
              mergedData[processName]!["${time}_cumulative"] = 0;
              for (int i = 1; i <= maxLines; i++) {
                mergedData[processName]!["${time}_$i"] = 0;
              }
            }
          }

          // Simpan raw data untuk processing
          mergedData[processName]!["raw_data_$contract"] = processData;
        }
      }

      // Process data untuk setiap proses yang sudah digabungkan
      for (final processName in mergedData.keys) {
        final process = mergedData[processName]!;
  final maxLines = process["type"] == 'Part' ? 3 : 5;

        Map<String, int> cumulativeData = {};
        for (final time in timeSlots) {
          cumulativeData[time] = 0;
        }

        // Process semua kontrak untuk proses ini
        for (final contract in contractNames) {
          final rawDataKey = "raw_data_$contract";
          if (!process.containsKey(rawDataKey)) continue;

          final processData = process[rawDataKey] as Map<String, dynamic>;

          // Tambahkan belumKensa
          final belumKensa = processData['belumKensa'] is String 
              ? int.tryParse(processData['belumKensa'] as String) ?? 0
              : (processData['belumKensa'] as num?)?.toInt() ?? 0;
          process["belumKensa"] = (process["belumKensa"] as int) + belumKensa;

          // Tambahkan stock_20min
          final stock20min = processData['stock_20min'] is String 
              ? int.tryParse(processData['stock_20min'] as String) ?? 0
              : (processData['stock_20min'] as num?)?.toInt() ?? 0;
          process["stock_20min"] = (process["stock_20min"] as int) + stock20min;

          // Tambahkan stock_pagi
          final stockPagi = processData['stock_pagi'] as Map<String, dynamic>? ?? {
            '1': 0, '2': 0, '3': 0, '4': 0, '5': 0, 'stock': 0
          };
          for (int i = 1; i <= 5; i++) {
            final currentVal = (process["stock_pagi"] as Map<String, dynamic>)['$i'] ?? 0;
            final newVal = stockPagi['$i'] ?? 0;
            (process["stock_pagi"] as Map<String, dynamic>)['$i'] = 
                (currentVal is int ? currentVal : 0) + (newVal is int ? newVal : int.tryParse(newVal.toString()) ?? 0);
          }

          // Hitung stock pagi total
          final stockPagiMap = process["stock_pagi"] as Map<String, dynamic>;
          stockPagiMap['stock'] = 
              (stockPagiMap['1'] as int) + 
              (stockPagiMap['2'] as int) + 
              (stockPagiMap['3'] as int) + 
              (stockPagiMap['4'] as int) + 
              (stockPagiMap['5'] as int);

          // Process data timeslot - SAMA PERSIS DENGAN counter_table_screen.dart
          processData.forEach((key, value) {
            if (key != 'sequence' && key != 'belumKensa' && key != 'stock_20min' && 
                key != 'stock_pagi' && key != 'part' && value is Map<String, dynamic>) {
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
                  
                  // Tambahkan ke data per line
                  process["${mappedTime}_$i"] = (process["${mappedTime}_$i"] as int) + count;
                }
                cumulativeData[mappedTime] = (cumulativeData[mappedTime] ?? 0) + slotTotal;
              }
            }
          });
        }

        // Hitung cumulative akhir - SAMA PERSIS DENGAN counter_table_screen.dart
        Map<String, int> finalCumulative = {};
        int currentCumulative = 0;
        
        for (String time in timeSlots) {
          currentCumulative += (cumulativeData[time] ?? 0);
          finalCumulative[time] = currentCumulative;
          process["${time}_cumulative"] = currentCumulative;
        }

        // Hapus raw data yang sudah tidak diperlukan
        for (final contract in contractNames) {
          final rawDataKey = "raw_data_$contract";
          process.remove(rawDataKey);
        }
      }

      // Konversi map ke list
      List<Map<String, dynamic>> processList = mergedData.values.toList();

      // Urutkan data - SAMA PERSIS DENGAN counter_table_screen.dart
      if (type == 'Part') {
        processList.sort((a, b) {
          final aIndex = partProcessOrder.indexOf(a['process_name']);
          final bIndex = partProcessOrder.indexOf(b['process_name']);
          return aIndex.compareTo(bIndex);
        });
      } else {
        processList.sort((a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int));
      }

      print('Successfully merged $type data: ${processList.length} processes');
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
        enableEditingMode: false,
        enableSorting: false,
        renderer: (rendererContext) {
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
        enableEditingMode: false,
        cellPadding: EdgeInsets.zero,
        renderer: (rendererContext) {
          final part1 = rendererContext.cell.value?.toString() ?? '';
          final part2 = rendererContext.row.cells['part_2']?.value?.toString() ?? '';
          // Target Part selalu 2x target jam PERTAMA (bukan per-jam masing-masing)
          final firstSlot = visibleTimeSlots.isNotEmpty ? visibleTimeSlots.first : (timeSlots.isNotEmpty ? timeSlots.first : '08:30');
          final targetPerJam = hourlyTargets.isNotEmpty ? ((hourlyTargets[firstSlot] ?? hourlyTargets.values.first) * 2) : 0;
          
          if (part2.isNotEmpty) {
            final part1Value = int.tryParse(part1) ?? 0;
            final part2Value = int.tryParse(part2) ?? 0;
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
                  right: BorderSide(color: Colors.blue.shade800, width: 1),
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
            final color1 = part1.isEmpty || part1Value == 0 
                ? Colors.blue.shade50 
                : (part1Value >= targetPerJam ? Colors.green.shade200 : Colors.red.shade200);
            return Container(
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color1,
                border: Border(
                  right: BorderSide(color: Colors.blue.shade800, width: 1),
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
          // Target Part selalu 2x target jam PERTAMA (bukan jam slot saat ini)
          // Ini berlaku juga untuk slot 12:00 dan 13:00 yang hanya 30 menit
          final firstSlot = visibleTimeSlots.isNotEmpty ? visibleTimeSlots.first : (timeSlots.isNotEmpty ? timeSlots.first : '08:30');
          final firstHourTarget = hourlyTargets[firstSlot] ?? 0.0;
          final partTarget = firstHourTarget * 2;
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

      kumitateColumns.add(
        PlutoColumn(
          title: "Stock",
          field: "${time}_stock",
          type: PlutoColumnType.text(),
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
            final stockValue = rendererContext.cell.value;
            Color textColor = Colors.black;
            
            if (stockValue is String && stockValue == '-') {
              textColor = Colors.black;
            } else if (stockValue is int) {
              if (stockValue < 0) {
                textColor = Colors.red;
              } else if (stockValue >= 0 && stockValue <= 5) {
                textColor = Colors.orange;
              } else {
                textColor = Colors.green;
              }
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
                  stockValue.toString(),
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

      double cumulativeTarget = 0.0;
      for (var slot in timeSlots) {
        cumulativeTarget += (hourlyTargets[slot] ?? 0.0);
        if (slot == time) break;
      }
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
    final filteredKumitateData = kumitateData.where((e) => (e['sequence'] ?? 0) != 0).toList();
    
    // Urutkan berdasarkan urutan proses
    filteredKumitateData.sort((a, b) {
      final aIndex = kumitateProcessOrder.indexOf(a['process_name'] ?? '');
      final bIndex = kumitateProcessOrder.indexOf(b['process_name'] ?? '');
      if (aIndex == -1) return 1;
      if (bIndex == -1) return -1;
      return aIndex.compareTo(bIndex);
    });
    
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

        for (final time in visibleTimeSlots) {
          int timeSlotTotal = 0;

          for (int i2 = 1; i2 <= 5; i2++) {
            final count = (entry["${time}_$i2"] as num?)?.toInt() ?? 0;
            timeSlotTotal += count;
            cells["${time}_$i2"] = PlutoCell(value: count);
          }

          // PART CALCULATION
          String partCalc = '';
          int getPartOutAccum(String outName) {
            final out = partData.firstWhere(
              (e) => (e['process_name'] ?? '').toString().toLowerCase() == outName.toLowerCase(),
              orElse: () => {},
            );
            int cumulativeValue = (out["${time}_cumulative"] as int?) ?? 0;
            
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
          bool hasDataInThisTimeSlot = false;
          for (int line = 1; line <= 5; line++) {
            if ((entry["${time}_$line"] ?? 0) > 0) {
              hasDataInThisTimeSlot = true;
              break;
            }
          }

          // Overtime slots (we treat 17:25 and 17:55 specially)
          final List<String> overtimeSlots = ['17:25', '17:55'];
          final bool isOvertimeSlot = overtimeSlots.contains(time);

          if (i == 0) {
            // First row always 0
            cells["${time}_stock"] = PlutoCell(value: 0);
          } else {
            if (isOvertimeSlot) {
              // If there's no cumulative at 16:00, assume process finished before overtime → 0 stock
              bool hasDataAt1600 = (entry["16:00_cumulative"] ?? 0) != 0;
              if (!hasDataAt1600) {
                cells["${time}_stock"] = PlutoCell(value: 0);
              } else {
                // Use latest available cumulative at or before the slot for previous and current processes
                final previousProcess = filteredKumitateData[i - 1];

                int findLatestCumulative(Map<String, dynamic> proc, String targetTime) {
                  final idx = timeSlots.indexOf(targetTime);
                  if (idx == -1) return 0;
                  for (int j = idx; j >= 0; j--) {
                    final key = '${timeSlots[j]}_cumulative';
                    final val = proc[key];
                    if (val != null) {
                      final intVal = val is int ? val : int.tryParse(val?.toString() ?? '') ?? 0;
                      if (intVal != 0) return intVal;
                    }
                  }
                  return 0;
                }

                int previousCumulative = findLatestCumulative(previousProcess, time);
                int currentCumulative = findLatestCumulative(entry, time);
                final pagiStock = (cells['stock_pagi_1']?.value ?? 0) +
                                (cells['stock_pagi_2']?.value ?? 0) +
                                (cells['stock_pagi_3']?.value ?? 0) +
                                (cells['stock_pagi_4']?.value ?? 0) +
                                (cells['stock_pagi_5']?.value ?? 0);
                cells["stock_pagi_stock"] = PlutoCell(value: pagiStock);
                final stockValue = pagiStock + previousCumulative - currentCumulative;
                cells["${time}_stock"] = PlutoCell(value: stockValue);
              }
            } else {
              // Non-overtime slot
              if (!hasDataInThisTimeSlot) {
                // No data at this slot → display '-' (no data)
                cells["${time}_stock"] = PlutoCell(value: '-');
              } else {
                int previousCumulative = 0;
                for (int j = i - 1; j >= 0; j--) {
                  final previousProcess = filteredKumitateData[j];
                  bool hasPreviousData = false;
                  for (int line = 1; line <= 5; line++) {
                    if ((previousProcess["${time}_$line"] ?? 0) > 0) {
                      hasPreviousData = true;
                      break;
                    }
                  }
                  if (hasPreviousData) {
                    previousCumulative = previousProcess["${time}_cumulative"] ?? 0;
                    break;
                  }
                }
                final currentCumulative = entry["${time}_cumulative"] ?? 0;
                final pagiStock = (cells['stock_pagi_1']?.value ?? 0) +
                                (cells['stock_pagi_2']?.value ?? 0) +
                                (cells['stock_pagi_3']?.value ?? 0) +
                                (cells['stock_pagi_4']?.value ?? 0) +
                                (cells['stock_pagi_5']?.value ?? 0);
                cells["stock_pagi_stock"] = PlutoCell(value: pagiStock);
                final stockValue = pagiStock + previousCumulative - currentCumulative;
                cells["${time}_stock"] = PlutoCell(value: stockValue);
              }
            }
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
        enableEditingMode: false,
        enableSorting: false,
        renderer: (rendererContext) {
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
        final cells = <String, PlutoCell>{};
        cells["process_name"] = PlutoCell(value: entry["process_name"]);
        cells["type"] = PlutoCell(value: "Part");
        cells["belumKensa"] = PlutoCell(
          value: entry["belumKensa"] is String 
              ? int.tryParse(entry["belumKensa"] as String) ?? 0
              : (entry["belumKensa"] as num?)?.toInt() ?? 0,
        );

        for (final time in visibleTimeSlots) {
          for (int i = 1; i <= 3; i++) {
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

  Future<void> loadData({bool showLoading = false}) async {
    if (showLoading) {
      setState(() {
        isLoading = true;
        noDataAvailable = false;
      });
    }
    
    print('Loading ALL data for Line $selectedLine on ${DateFormat('yyyy-MM-dd').format(selectedDate)}');

    final formattedDate = DateFormat("yyyy-MM-dd").format(selectedDate);
    
    try {
      final kumitateFuture = fetchCounterData(formattedDate, selectedLine, 'Kumitate');
      final partFuture = fetchCounterData(formattedDate, selectedLine, 'Part');
      
      final results = await Future.wait([kumitateFuture, partFuture]);
      
      kumitateData = results[0];
      partData = results[1];

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
        print('No data available for the selected criteria');
      } else {
        _buildKumitateColumnsAndRows();
        _buildPartColumnsAndRows();
        _buildProsesTable();
        _buildPartProsesTable();
        print('ALL Data loaded successfully: ${kumitateData.length} kumitate, ${partData.length} part');
        print('Visible timeslots: $visibleTimeSlots');
      }
    } catch (e) {
      print('Error loading ALL data: $e');
      setState(() {
        noDataAvailable = true;
        kumitateData = [];
        partData = [];
      });
    } finally {
      if (showLoading) setState(() => isLoading = false);
    }
  }

  void _cancelAllSubscriptions() {
    _parentDocSub?.cancel();
    _parentDocSub = null;
    _kumitateDocSub?.cancel();
    _kumitateDocSub = null;
    _partDocSub?.cancel();
    _partDocSub = null;
    for (var s in _contractSubscriptions) {
      s.cancel();
    }
    _contractSubscriptions.clear();
  }

  void _setupContractListeners(DocumentReference parentDocRef, List<String> contractCollections) {
    // cancel previous contract listeners
    for (var s in _contractSubscriptions) s.cancel();
    _contractSubscriptions.clear();

    for (final contractName in contractCollections) {
      final sub = parentDocRef
          .collection(contractName)
          .snapshots()
          .listen((_) {
        // On any change in contract subcollection, reload merged data
        loadData();
      }, onError: (e) {
        print('Contract listener error for $contractName: $e');
      });

      _contractSubscriptions.add(sub);
    }
  }

  void _setupAutoRefresh({bool showFullLoading = false}) {
    // Cancel existing
    _cancelAllSubscriptions();

    if (showFullLoading) {
      setState(() {
        isLoading = true;
      });
    }

    final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
    final parentDocRef = FirebaseFirestore.instance.collection('counter_sistem').doc(dateStr);

    // Listen to top-level doc for target/plan changes
    _parentDocSub = parentDocRef.snapshots().listen((snapshot) async {
      // Reload targets when parent doc changes (no spinner)
      await _loadTargets(showSpinner: false);
      // Also reload all data (no full-screen loader)
      await loadData();
    }, onError: (e) {
      print('Parent doc subscription error: $e');
    });

    // Listen to Kumitate parent doc to get contract list and set up contract listeners
    final kumitateDocRef = FirebaseFirestore.instance
        .collection('counter_sistem')
        .doc(dateStr)
        .collection(selectedLine)
        .doc('Kumitate');

    _kumitateDocSub = kumitateDocRef.snapshots().listen((snapshot) {
      List<String> contractCollections = [];
      if (snapshot.exists) {
        final raw = snapshot.data();
        if (raw is Map<String, dynamic>) {
          final kontrak = raw['Kontrak'];
          if (kontrak is List) {
            contractCollections = kontrak.map((e) => e.toString()).toList();
          }
        }
      }

      if (contractCollections.isEmpty) contractCollections = ['Process'];

      _setupContractListeners(kumitateDocRef, contractCollections);
      // ensure UI has up-to-date data
      loadData();
    }, onError: (e) {
      print('Kumitate doc subscription error: $e');
      _setupContractListeners(kumitateDocRef, ['Process']);
    });

    // Also listen to Part parent doc to catch changes in part Kontrak list
    final partDocRef = FirebaseFirestore.instance
        .collection('counter_sistem')
        .doc(dateStr)
        .collection(selectedLine)
        .doc('Part');

    _partDocSub = partDocRef.snapshots().listen((snapshot) {
      List<String> contractCollections = [];
      if (snapshot.exists) {
        final raw = snapshot.data();
        if (raw is Map<String, dynamic>) {
          final kontrak = raw['Kontrak'];
          if (kontrak is List) {
            contractCollections = kontrak.map((e) => e.toString()).toList();
          }
        }
      }
      if (contractCollections.isEmpty) contractCollections = ['Process'];

      // For parts we also want to listen to their contract subcollections
      _setupContractListeners(partDocRef, contractCollections);
      loadData();
    }, onError: (e) {
      print('Part doc subscription error: $e');
    });

    // initial load (will also be triggered by snapshots, but do it now)
    _loadTargets(showSpinner: showFullLoading).then((_) => loadData(showLoading: showFullLoading));
  }

  Widget buildChart(String processName, String type) {
    final dataList = type == 'Kumitate' ? kumitateData : partData;
    final process = dataList.firstWhere((e) => e["process_name"] == processName);
    final lineColors = [
      Colors.red, Colors.green, Colors.blue, Colors.orange, Colors.purple,
    ];

    final extendedTimeSlots = ["0", ...timeSlots];
  final maxLines = type == 'Part' ? 3 : 5;

    final lineBarsData = <LineChartBarData>[];
    final activeLineNums = <int>[];
    if (type == 'Kumitate' || type == 'Part') {
      for (int lineNum = 1; lineNum <= maxLines; lineNum++) {
        bool hasData = false;
        final spots = <FlSpot>[FlSpot(0, 0)];
        for (int t = 0; t < timeSlots.length; t++) {
          final value = (process["${timeSlots[t]}_$lineNum"] as num?)?.toDouble() ?? 0;
          if (value > 0) hasData = true;
          spots.add(FlSpot((t+1).toDouble(), value));
        }
        if (hasData) {
          activeLineNums.add(lineNum);
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
                ...List.generate(activeLineNums.length, (index) {
                  final lineNum = activeLineNums[index];
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: lineColors[lineNum - 1],
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Line $lineNum',
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
          excel.IntCellValue(0),
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
          excel.IntCellValue(0),
          excel.IntCellValue(0),
          excel.IntCellValue(0),
          excel.IntCellValue(0),
          excel.IntCellValue(0),
          excel.TextCellValue(''),
          excel.TextCellValue(''),
          excel.IntCellValue(0),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade100,
      appBar: AppBar(
        title: Text(
          "Stock Kumitate & Part per Process (All Contracts)",
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
            icon: Icon(Icons.file_download, color: Colors.white),
            tooltip: "Export to Excel",
            onPressed: exportToExcel,
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            tooltip: "Refresh Data",
            onPressed: () async {
              setState(() {
                isTargetLoading = true;
              });
              await _loadTargets(showSpinner: true);
              await loadData(showLoading: true);
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
                        "No Data Available for ${DateFormat('yyyy-MM-dd').format(selectedDate)} (Line $selectedLine)",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'You can either pick another date or choose a different line to view data.',
                        style: TextStyle(fontSize: 14, color: Colors.black54),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 20),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        children: [
                          ElevatedButton(
                            onPressed: () => selectDate(context),
                            child: Text("Pilih Tanggal"),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.blue.shade500),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: selectedLine,
                                items: ["A", "B", "C", "D", "E"].map((line) => DropdownMenuItem(
                                  value: line,
                                  child: Text('Line $line'),
                                )).toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() {
                                    selectedLine = value;
                                    noDataAvailable = false;
                                  });
                                  // Reconfigure streams for the new line
                                  _setupAutoRefresh();
                                },
                              ),
                            ),
                          ),
                        ],
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
                                    });
                                    // Reconfigure streams for the new line
                                    _setupAutoRefresh();
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
                                  : Text(
                                      'Target: ${dailyTarget != null ? dailyTarget!.round() : '-'}',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
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
                          title: 'KUMITATE (All Contracts)',
                          columns: kumitateColumns,
                          rows: kumitateRows,
                          columnGroups: kumitateColumnGroups,
                        ),
                        SizedBox(height: 30),
                      ],
                      
                      if (partRows.isNotEmpty) ...[
                        _buildTableWidget(
                          title: 'PART (All Contracts)',
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
                              title: 'AKUMULATIF LINE (Kumitate)',
                              columns: prosesColumns,
                              rows: prosesRows,
                              columnGroups: prosesColumnGroups,
                              dropdownLabel: 'Pilih Proses Kumitate: ',
                              processDropdown: DropdownButton<String>(
                                value: selectedProcessName,
                                items: processNames.map((name) => DropdownMenuItem(
                                  value: name,
                                  child: Text(
                                    name,
                                    style: TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
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
                      
                      if (partProcessNames.isNotEmpty) ...[
                        SizedBox(height: 30),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTableWidget(
                              title: 'AKUMULATIF LINE (Part)',
                              columns: partProsesColumns,
                              rows: partProsesRows,
                              columnGroups: partProsesColumnGroups,
                              dropdownLabel: 'Pilih Proses Part: ',
                              processDropdown: DropdownButton<String>(
                                value: selectedPartProcessName,
                                items: partProcessNames.map((name) => DropdownMenuItem(
                                  value: name,
                                  child: Text(
                                    name,
                                    style: TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )).toList(),
                                onChanged: (value) {
                                  if (value != null && value != selectedPartProcessName) {
                                    setState(() {
                                      selectedPartProcessName = value;
                                      _buildPartProsesTable();
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
    );
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
      });
      // Reconfigure streams for the new date (will trigger loading)
      _setupAutoRefresh();
    }
  }

  Widget _buildTableWidget({
    required String title,
    required List<PlutoColumn> columns,
    required List<PlutoRow> rows,
    required List<PlutoColumnGroup> columnGroups,
    Widget? processDropdown,
    String? dropdownLabel,
  }) {
    const rowHeight = 30.0;
    const headerHeight = 40.0;
    const columnHeaderHeight = 30.0;
    final totalHeight = headerHeight + columnHeaderHeight + (rows.length * rowHeight) + 6;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
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
                  Text(dropdownLabel ?? 'Pilih Proses: ', style: TextStyle(fontWeight: FontWeight.bold)),
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
                key: ValueKey('${title}_${selectedDate}_${selectedLine}_${title == 'AKUMULATIF LINE (Kumitate)' ? (selectedProcessName ?? '') : ''}_${title == 'AKUMULATIF LINE (Part)' ? (selectedPartProcessName ?? '') : ''}'),
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
                  enableMoveHorizontalInEditing: false,
                  enterKeyAction: PlutoGridEnterKeyAction.none,
                ),
                rowColorCallback: title == 'PART (All Contracts)'
                    ? (PlutoRowColorContext rowContext) {
                        final processName = rowContext.row.cells['process_name']?.value?.toString() ?? '';
                        return getPartRowColor(processName) ?? Colors.transparent;
                      }
                    : null,
                mode: PlutoGridMode.readOnly,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cancelAllSubscriptions();
    super.dispose();
  }
}