import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:fl_chart/fl_chart.dart';

class FinalPage extends StatefulWidget {
  @override
  _FinalPageState createState() => _FinalPageState();
}

class _FinalPageState extends State<FinalPage> {
  int selectedYear = DateTime.now().year;
  int selectedMonth = DateTime.now().month;
  bool isLoading = true;
  List<String> lines = ['A', 'B', 'C', 'D', 'E'];
  List<int> daysInMonth = [];
  List<PlutoColumn> columns = [];
  List<PlutoColumnGroup> columnGroups = [];
  List<PlutoRow> rows = [];
  Map<String, Map<int, double>> lineTargetPerDay = {}; // line -> day -> target
  // PlutoGridStateManager? _stateManager; // Removed unused field

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    daysInMonth = List.generate(
      DateUtils.getDaysInMonth(selectedYear, selectedMonth),
      (i) => i + 1,
    );
    columns = [
      PlutoColumn(
        title: 'Line',
        field: 'line',
        type: PlutoColumnType.text(),
        width: 80,
        titleTextAlign: PlutoColumnTextAlign.center,
        textAlign: PlutoColumnTextAlign.center,
        backgroundColor: Colors.blue.shade300,
        enableColumnDrag: false,
        enableDropToResize: false,
        enableContextMenu: false,
        enableSorting: false,
        enableEditingMode: false,
        cellPadding: EdgeInsets.zero,
        renderer: (ctx) => Container(
          constraints: BoxConstraints.expand(),
          alignment: Alignment.center,
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            border: Border(
              right: BorderSide(color: Colors.blue, width: 1),
              bottom: BorderSide(color: Colors.blue, width: 1),
            ),
          ),
          child: Text(
            ctx.cell.value.toString(),
            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
        ),
      ),
    ];
    columnGroups = [
      PlutoColumnGroup(title: '', fields: ['line'], backgroundColor: Colors.blue.shade300),
    ];

    // Optimasi: Ambil semua dokumen target harian untuk bulan ini sekaligus
    lineTargetPerDay.clear();
    for (final line in lines) {
      lineTargetPerDay[line] = {};
    }
    try {
      final startDate = DateTime(selectedYear, selectedMonth, 1);
      final endDate = DateTime(selectedYear, selectedMonth, daysInMonth.last);
      // Query semua dokumen counter_sistem untuk bulan ini
      final snap = await FirebaseFirestore.instance
          .collection('counter_sistem')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: DateFormat('yyyy-MM-dd').format(startDate))
          .where(FieldPath.documentId, isLessThanOrEqualTo: DateFormat('yyyy-MM-dd').format(endDate))
          .get();
      final docMap = {for (var doc in snap.docs) doc.id: doc.data()};
      for (final day in daysInMonth) {
        final date = DateTime(selectedYear, selectedMonth, day);
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        final data = docMap[dateStr] ?? {};
        for (final line in lines) {
          double? target;
          if (data.containsKey('target_${line}')) {
            target = (data['target_${line}'] as num?)?.toDouble();
          } else if (data.containsKey('target${line}')) {
            target = (data['target${line}'] as num?)?.toDouble();
          } else if (data.containsKey('target')) {
            target = (data['target'] as num?)?.toDouble();
          }
          if (target != null) {
            lineTargetPerDay[line]![day] = target;
          } else {
            lineTargetPerDay[line]![day] = 0;
          }
        }
      }
    } catch (e) {
      print('Firestore error target bulk: $e');
      // fallback: isi 0
      for (final line in lines) {
        for (final day in daysInMonth) {
          lineTargetPerDay[line]![day] = 0;
        }
      }
    }

    // Tambahkan kolom grup tanggal (Target dulu, lalu Output)
    for (final d in daysInMonth) {
      final date = DateTime(selectedYear, selectedMonth, d);
      final isWeekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
      final outField = 'day_${d}_out';
      final targetField = 'day_${d}_target';
      columns.addAll([
        PlutoColumn(
          title: 'Target',
          field: targetField,
          type: PlutoColumnType.text(),
          width: 60,
          titleTextAlign: PlutoColumnTextAlign.center,
          textAlign: PlutoColumnTextAlign.center,
          backgroundColor: Colors.blue.shade200,
          enableColumnDrag: false,
          enableDropToResize: false,
          enableContextMenu: false,
          enableSorting: false,
          enableEditingMode: false,
          cellPadding: EdgeInsets.zero,
          renderer: (ctx) => Container(
            constraints: BoxConstraints.expand(),
            alignment: Alignment.center,
            padding: EdgeInsets.zero,
            decoration: BoxDecoration(
              color: isWeekend ? Colors.grey.shade300 : Colors.blue.shade50,
              border: Border(
                right: BorderSide(color: Colors.blue, width: 1),
                bottom: BorderSide(color: Colors.blue, width: 1),
              ),
            ),
            child: Text(
              ctx.cell.value.toString(),
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: Colors.black),
            ),
          ),
        ),
        PlutoColumn(
          title: 'Out',
          field: outField,
          type: PlutoColumnType.text(),
          width: 60,
          titleTextAlign: PlutoColumnTextAlign.center,
          textAlign: PlutoColumnTextAlign.center,
          backgroundColor: Colors.blue.shade200,
          enableColumnDrag: false,
          enableDropToResize: false,
          enableContextMenu: false,
          enableSorting: false,
          enableEditingMode: false,
          cellPadding: EdgeInsets.zero,
          renderer: (ctx) {
            // Ambil target dari cell di baris yang sama
            final row = ctx.row;
            final targetStr = row.cells[targetField]?.value?.toString() ?? '';
            final outStr = ctx.cell.value?.toString() ?? '';
            final target = double.tryParse(targetStr);
            final out = double.tryParse(outStr);
            Color fontColor = Colors.black;
            if (target != null && out != null) {
              if (out >= target) {
                fontColor = Colors.green;
              } else {
                fontColor = Colors.red;
              }
            }
            return Container(
              constraints: BoxConstraints.expand(),
              alignment: Alignment.center,
              padding: EdgeInsets.zero,
              decoration: BoxDecoration(
                color: isWeekend ? Colors.grey.shade300 : Colors.blue.shade50,
                border: Border(
                  right: BorderSide(color: Colors.blue, width: 1),
                  bottom: BorderSide(color: Colors.blue, width: 1),
                ),
              ),
              child: Text(
                ctx.cell.value.toString(),
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: fontColor),
              ),
            );
          },
        ),
      ]);
      columnGroups.add(
        PlutoColumnGroup(
          title: d.toString(),
          fields: [targetField, outField],
          backgroundColor: Colors.blue.shade300,
        ),
      );
    }
    // Kolom total menjadi grup: target_akum, output_akum, selisih
    columns.addAll([
      PlutoColumn(
        title: 'Target',
        field: 'total_target',
        type: PlutoColumnType.text(),
        width: 70,
        titleTextAlign: PlutoColumnTextAlign.center,
        textAlign: PlutoColumnTextAlign.center,
        backgroundColor: Colors.yellow.shade300,
        enableColumnDrag: false,
        enableDropToResize: false,
        enableContextMenu: false,
        enableSorting: false,
        enableEditingMode: false,
        cellPadding: EdgeInsets.zero,
        renderer: (ctx) => Container(
          constraints: BoxConstraints.expand(),
          alignment: Alignment.center,
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: Colors.yellow.shade100,
            border: Border(
              right: BorderSide(color: Colors.blue, width: 1),
              bottom: BorderSide(color: Colors.blue, width: 1),
            ),
          ),
          child: Text(
            ctx.cell.value.toString(),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black),
          ),
        ),
      ),
      PlutoColumn(
        title: 'Output',
        field: 'total_output',
        type: PlutoColumnType.text(),
        width: 70,
        titleTextAlign: PlutoColumnTextAlign.center,
        textAlign: PlutoColumnTextAlign.center,
        backgroundColor: Colors.yellow.shade300,
        enableColumnDrag: false,
        enableDropToResize: false,
        enableContextMenu: false,
        enableSorting: false,
        enableEditingMode: false,
        cellPadding: EdgeInsets.zero,
        renderer: (ctx) => Container(
          constraints: BoxConstraints.expand(),
          alignment: Alignment.center,
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: Colors.yellow.shade100,
            border: Border(
              right: BorderSide(color: Colors.blue, width: 1),
              bottom: BorderSide(color: Colors.blue, width: 1),
            ),
          ),
          child: Text(
            ctx.cell.value.toString(),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black),
          ),
        ),
      ),
      PlutoColumn(
        title: 'Selisih',
        field: 'total_selisih',
        type: PlutoColumnType.text(),
        width: 70,
        titleTextAlign: PlutoColumnTextAlign.center,
        textAlign: PlutoColumnTextAlign.center,
        backgroundColor: Colors.yellow.shade300,
        enableColumnDrag: false,
        enableDropToResize: false,
        enableContextMenu: false,
        enableSorting: false,
        enableEditingMode: false,
        cellPadding: EdgeInsets.zero,
        renderer: (ctx) => Container(
          constraints: BoxConstraints.expand(),
          alignment: Alignment.center,
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: Colors.yellow.shade100,
            border: Border(
              right: BorderSide(color: Colors.blue, width: 1),
              bottom: BorderSide(color: Colors.blue, width: 1),
            ),
          ),
          child: Text(
            ctx.cell.value.toString(),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black),
          ),
        ),
      ),
    ]);
    columnGroups.add(
      PlutoColumnGroup(title: 'Total', fields: ['total_target', 'total_output', 'total_selisih'], backgroundColor: Colors.yellow.shade300),
    );

    rows = [];
    for (final line in lines) {
      Map<int, String> lineData = {};
      Map<int, int> lineDataInt = {};
      // Optimasi: untuk setiap hari, ambil dokumen terakhir (berdasarkan sequence)
      // dari setiap kontrak yang terdaftar di dokumen 'Kumitate'. Struktur baru
      // menyimpan kontrak di field 'Kontrak' (array). Jika tidak ada, fallback
      // ke koleksi legacy 'Process'. Hasilnya adalah total (sum) dari semua
      // dokumen terakhir per kontrak untuk hari tersebut.
      final processCounts = await Future.wait(daysInMonth.map((day) async {
        final date = DateTime(selectedYear, selectedMonth, day);
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        int totalCount = 0;
        try {
          final kumitateDocRef = FirebaseFirestore.instance
              .collection('counter_sistem')
              .doc(dateStr)
              .collection(line)
              .doc('Kumitate');

          final kumitateSnap = await kumitateDocRef.get();
          List<String> contractCollections = [];
          if (kumitateSnap.exists) {
            final data = kumitateSnap.data();
            if (data != null && data['Kontrak'] is List) {
              contractCollections = List<dynamic>.from(data['Kontrak']).map((e) => e.toString()).toList();
            }
          }

          if (contractCollections.isEmpty) {
            // fallback ke struktur lama
            contractCollections = ['Process'];
          }

          for (final contractName in contractCollections) {
            try {
              final latestSnap = await kumitateDocRef
                  .collection(contractName)
                  .orderBy('sequence', descending: true)
                  .limit(1)
                  .get();

              if (latestSnap.docs.isEmpty) continue;

              final processData = latestSnap.docs.first.data();
              processData.forEach((key, value) {
                if (key != 'sequence' &&
                    key != 'belumKensa' &&
                    key != 'stock_20min' &&
                    key != 'stock_pagi' &&
                    key != 'part' &&
                    value is Map<String, dynamic>) {
                  value.forEach((lineKey, lineValue) {
                    totalCount += (lineValue as int? ?? 0);
                  });
                }
              });
            } catch (e) {
              // ignore per-contract errors but continue with others
              print('Error reading latest for $line $dateStr contract $contractName: $e');
            }
          }
        } catch (e) {
          print('Firestore error on $line $day: $e');
        }

        return totalCount;
      }));

      for (int i = 0; i < daysInMonth.length; i++) {
        final day = daysInMonth[i];
        final totalCount = processCounts[i];
        lineData[day] = totalCount > 0 ? totalCount.toString() : ' ';
        lineDataInt[day] = totalCount;
      }
      final cells = <String, PlutoCell>{
        'line': PlutoCell(value: 'Line $line'),
      };
      int totalOutput = 0;
      double totalTarget = 0;
      for (final day in daysInMonth) {
        final outField = 'day_${day}_out';
        final targetField = 'day_${day}_target';
        // Target dulu, baru output
        final target = lineTargetPerDay[line]?[day] ?? 0;
        cells[targetField] = PlutoCell(value: target > 0 ? target.toStringAsFixed(0) : ' ');
        final val = lineDataInt[day] ?? 0;
        cells[outField] = PlutoCell(value: lineData[day] ?? ' ');
        if (val > 0) totalOutput += val;
        if (target > 0) totalTarget += target;
      }
      final selisih = totalOutput - totalTarget;
      cells['total_target'] = PlutoCell(value: totalTarget > 0 ? totalTarget.toStringAsFixed(0) : ' ');
      cells['total_output'] = PlutoCell(value: totalOutput > 0 ? totalOutput.toString() : ' ');
      cells['total_selisih'] = PlutoCell(value: (totalTarget > 0 || totalOutput > 0) ? selisih.toStringAsFixed(0) : ' ');
      rows.add(PlutoRow(cells: cells));
    }
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade100,
      appBar: AppBar(
        title: Text(
          "Final Bottan Data",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        actions: [
          Tooltip(
            message: 'Refresh',
            child: IconButton(
              icon: Icon(Icons.refresh, color: Colors.white, size: 26),
              onPressed: isLoading ? null : _loadData,
              splashRadius: 24,
              tooltip: 'Refresh',
            ),
          ),
        ],
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
        toolbarHeight: 60,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Container(
                    width: 120,
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue.shade300, width: 1),
                    ),
                    child: Center(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: selectedYear,
                          style: TextStyle(fontWeight: FontWeight.normal, color: Colors.black, fontSize: 16),
                          icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.blue.shade700, size: 28),
                          dropdownColor: Colors.white,
                          alignment: Alignment.center,
                          items: List.generate(6, (i) {
                            final year = DateTime.now().year - 3 + i;
                            return DropdownMenuItem(
                              value: year,
                              alignment: Alignment.center,
                              child: Center(child: Text(year.toString(), style: TextStyle(fontWeight: FontWeight.normal, fontSize: 16, color: Colors.black), textAlign: TextAlign.center)),
                            );
                          }),
                          onChanged: (v) {
                            if (v != null) setState(() { selectedYear = v; _loadData(); });
                          },
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Container(
                    width: 160,
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue.shade300, width: 1),
                    ),
                    child: Center(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: selectedMonth,
                          style: TextStyle(fontWeight: FontWeight.normal, color: Colors.black, fontSize: 16),
                          icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.blue.shade700, size: 28),
                          dropdownColor: Colors.white,
                          alignment: Alignment.center,
                          items: List.generate(12, (i) {
                            final month = i + 1;
                            return DropdownMenuItem(
                              value: month,
                              alignment: Alignment.center,
                              child: Center(child: Text(DateFormat('MMMM').format(DateTime(0, month)), style: TextStyle(fontWeight: FontWeight.normal, fontSize: 16, color: Colors.black), textAlign: TextAlign.center)),
                            );
                          }),
                          onChanged: (v) {
                            if (v != null) setState(() { selectedMonth = v; _loadData(); });
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: SizedBox(
                // 1 header + 5 rows, header 36, row 32
                height: 36 + 6 * 32 + 14,
                child: isLoading
                    ? Center(child: CircularProgressIndicator())
                    : PlutoGrid(
                        columns: columns,
                        rows: rows,
                        columnGroups: columnGroups,
                        configuration: PlutoGridConfiguration(
                          style: PlutoGridStyleConfig(
                            columnHeight: 36,
                            rowHeight: 32,
                            gridBorderColor: Colors.blue, // blue border
                            gridBackgroundColor: Colors.blue.shade50, // cell background
                            activatedBorderColor: Colors.blue,
                            activatedColor: Colors.blue.shade50,
                            cellTextStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                            columnTextStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                        mode: PlutoGridMode.readOnly,
                      ),
              ),
            ),
            // Tambahkan grafik di bawah tabel
            if (!isLoading)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in lines)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10.0, left: 2.0),
                            child: Text(
                              'Line $line',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: Colors.blue.shade900),
                            ),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _buildLineChart(line, false), // Harian
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: _buildLineChart(line, true), // Akumulatif
                              ),
                            ],
                          ),
                          SizedBox(height: 22),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Fungsi builder grafik harian dan akumulatif
  Widget _buildLineChart(String line, bool isAkumulatif) {
    final List<int> xDays = daysInMonth;
    final List<double> yData = [];
    double akum = 0;
    for (final day in xDays) {
      final row = rows.firstWhere(
        (r) => r.cells['line']?.value == 'Line $line',
        orElse: () => PlutoRow(cells: {}),
      );
      final valStr = row.cells['day_${day}_out']?.value?.toString() ?? '';
      final val = int.tryParse(valStr.trim()) ?? 0;
      if (isAkumulatif) {
        akum += val;
        yData.add(akum);
      } else {
        yData.add(val.toDouble());
      }
    }
    // Jika semua data kosong, tampilkan placeholder
    final hasData = yData.any((v) => v > 0);
    if (!hasData) {
      return Container(
        constraints: BoxConstraints(minHeight: 180, maxHeight: 260),
        color: Colors.grey.shade100,
        child: Center(child: Text('Tidak ada data')), 
      );
    }
    // Responsif: gunakan LayoutBuilder untuk menyesuaikan lebar
    return LayoutBuilder(
      builder: (context, constraints) {
        final chartHeight = (constraints.maxWidth < 400) ? 160.0 : 200.0;
        return SizedBox(
          height: chartHeight,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) {
                    return Dialog(
                      backgroundColor: Colors.transparent,
                      insetPadding: EdgeInsets.all(8),
                      child: Container(
                        constraints: BoxConstraints(maxWidth: 800),
                        child: Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(32, 24, 24, 24),
                            child: SizedBox(
                              height: 480,
                              child: _buildChartContent(xDays, yData, line, isAkumulatif, isPopup: true),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
              child: Card(
                elevation: 2,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: _buildChartContent(xDays, yData, line, isAkumulatif, isPopup: false),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChartContent(List<int> xDays, List<double> yData, String line, bool isAkumulatif, {bool isPopup = false}) {
    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 44, getTitlesWidget: (value, meta) {
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Text(value.toInt().toString(), style: TextStyle(fontSize: 12)),
              );
            }),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (xDays.length / 6).ceilToDouble(),
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 1 || idx > xDays.length) return SizedBox.shrink();
                return Text('${xDays[idx - 1]}', style: TextStyle(fontSize: 10));
              },
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: true, border: Border.all(color: Colors.blue.shade200)),
        minX: 1,
        maxX: xDays.length.toDouble(),
        minY: 0,
        maxY: (yData.reduce((a, b) => a > b ? a : b) * 1.2).ceilToDouble(),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (int i = 0; i < xDays.length; i++)
                FlSpot((i + 1).toDouble(), yData[i]),
            ],
            isCurved: false, // garis tegas
            color: isAkumulatif ? Colors.orange : Colors.blue,
            barWidth: isPopup ? 4 : 3,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: (isAkumulatif ? Colors.orange : Colors.blue).withOpacity(0.12)),
          ),
        ],
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final idx = spot.x.toInt() - 1;
                final day = (idx >= 0 && idx < xDays.length) ? xDays[idx] : '-';
                final value = spot.y.toInt();
                return LineTooltipItem(
                  '$day: $value',
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: isPopup ? 18 : 14),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }
}
