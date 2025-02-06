import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';
import '../providers/counter_provider.dart';

class CounterTableView extends ConsumerStatefulWidget {
  @override
  _CounterTableViewState createState() => _CounterTableViewState();
}

class _CounterTableViewState extends ConsumerState<CounterTableView> {
  String selectedLine = "A"; // Default Line
  String selectedDate = "25-01-2025"; // Default Date

  @override
  Widget build(BuildContext context) {
    final productionData = ref.watch(productionDataProvider({'line': selectedLine, 'date': selectedDate}));

    return Scaffold(
      appBar: AppBar(
        title: Text("Production Table"),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              ref.refresh(productionDataProvider({'line': selectedLine, 'date': selectedDate}));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 🔹 Dropdown untuk memilih Line & Tanggal
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                DropdownButton<String>(
                  value: selectedLine,
                  items: ["A", "B", "C", "D", "E"].map((line) {
                    return DropdownMenuItem(value: line, child: Text("Line $line"));
                  }).toList(),
                  onChanged: (newValue) {
                    setState(() {
                      selectedLine = newValue!;
                    });
                    ref.refresh(productionDataProvider({'line': selectedLine, 'date': selectedDate}));
                  },
                ),
                ElevatedButton(
                  onPressed: () => _selectDate(context),
                  child: Text("Select Date: $selectedDate"),
                ),
              ],
            ),
          ),

          // 🔹 Tabel dengan PlutoGrid
          Expanded(
            child: productionData.when(
              loading: () => Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text("Error: $err")),
              data: (data) {
                if (data.isEmpty) return Center(child: Text("No data found"));

                // 🔹 Gunakan data langsung tanpa selectedLine
                final processData = data;

                // 🔹 Definisi kolom
                List<PlutoColumn> columns = [
                  PlutoColumn(title: "PROCESS NAME", field: "process", type: PlutoColumnType.text()),
                  PlutoColumn(title: "12:30", field: "12:30", type: PlutoColumnType.number()),
                  PlutoColumn(title: "13:30", field: "13:30", type: PlutoColumnType.number()),
                  PlutoColumn(title: "14:30", field: "14:30", type: PlutoColumnType.number()),
                  PlutoColumn(title: "15:30", field: "15:30", type: PlutoColumnType.number()),
                  PlutoColumn(title: "16:30", field: "16:30", type: PlutoColumnType.number()),
                ];

                // 🔹 Buat rows berdasarkan data Firestore
                List<PlutoRow> rows = processData.entries.map((entry) {
                  Map<String, int> timeData = entry.value;

                  return PlutoRow(cells: {
                    "process": PlutoCell(value: entry.key),
                    "12:30": PlutoCell(value: timeData["12:30"] ?? 0),
                    "13:30": PlutoCell(value: timeData["13:30"] ?? 0),
                    "14:30": PlutoCell(value: timeData["14:30"] ?? 0),
                    "15:30": PlutoCell(value: timeData["15:30"] ?? 0),
                    "16:30": PlutoCell(value: timeData["16:30"] ?? 0),
                  });
                }).toList();

                return PlutoGrid(
                  columns: columns,
                  rows: rows,
                  mode: PlutoGridMode.readOnly,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 🔹 Fungsi untuk memilih tanggal
  Future<void> _selectDate(BuildContext context) async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2026),
    );

    if (picked != null) {
      setState(() {
        selectedDate = "${picked.day}-${picked.month}-${picked.year}";
      });
      ref.refresh(productionDataProvider({'line': selectedLine, 'date': selectedDate}));
    }
  }
}
