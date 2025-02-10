import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'firestore_service.dart'; // Import Firestore service

class CounterTableScreen extends StatefulWidget {
  @override
  _CounterTableScreenState createState() => _CounterTableScreenState();
}

class _CounterTableScreenState extends State<CounterTableScreen> {
  List<PlutoColumn> columns = [];
  List<PlutoRow> rows = [];
  List<PlutoColumnGroup> columnGroups = [];
  bool isLoading = true;

  String selectedLine = "A"; // 🔹 Default Line
  DateTime selectedDate = DateTime.now(); // 🔹 Default ke hari ini

  @override
  void initState() {
    super.initState();
    loadData(selectedLine, _formatDate(selectedDate));
  }

  Future<void> loadData(String line, String date) async {
    setState(() => isLoading = true);

    List<Map<String, dynamic>> data = await fetchCounterData(line, date);
    List<String> timeSlots = ["07:30", "08:30", "09:30", "10:30", "11:30", "13:30", "14:30", "15:30", "16:30"];

    columns = [
      PlutoColumn(title: "PROCESS NAME", field: "process_name", type: PlutoColumnType.text(), width: 150),
    ];

    columnGroups = [];

    for (String time in timeSlots) {
      for (int i = 1; i <= 5; i++) {
        columns.add(PlutoColumn(title: "$i", field: "${time}_$i", type: PlutoColumnType.number(), width: 80));
      }
      columns.add(
        PlutoColumn(title: "TOTAL", field: "${time}_total", type: PlutoColumnType.number(), width: 100, backgroundColor: Colors.yellow.shade200),
      );

      columnGroups.add(PlutoColumnGroup(
        title: time,
        fields: ["${time}_1", "${time}_2", "${time}_3", "${time}_4", "${time}_5", "${time}_total"],
      ));
    }

    columns.add(
      PlutoColumn(title: "GRAND TOTAL", field: "grand_total", type: PlutoColumnType.number(), width: 120, backgroundColor: Colors.orange.shade300),
    );

    rows = data.map((entry) {
      Map<String, PlutoCell> cells = {"process_name": PlutoCell(value: entry["process_name"])};
      int grandTotal = 0;

      for (String time in timeSlots) {
        int count1 = entry[time]?["1"] ?? 0;
        int count2 = entry[time]?["2"] ?? 0;
        int count3 = entry[time]?["3"] ?? 0;
        int count4 = entry[time]?["4"] ?? 0;
        int count5 = entry[time]?["5"] ?? 0;
        int total = count1 + count2 + count3 + count4 + count5;
        grandTotal += total;

        cells["${time}_1"] = PlutoCell(value: count1);
        cells["${time}_2"] = PlutoCell(value: count2);
        cells["${time}_3"] = PlutoCell(value: count3);
        cells["${time}_4"] = PlutoCell(value: count4);
        cells["${time}_5"] = PlutoCell(value: count5);
        cells["${time}_total"] = PlutoCell(value: total);
      }

      cells["grand_total"] = PlutoCell(value: grandTotal);
      return PlutoRow(cells: cells);
    }).toList();

    setState(() => isLoading = false);
  }

  String _formatDate(DateTime date) {
    return DateFormat("MM-dd-yyyy").format(date); // 🔹 Format: 02-01-2025
  }

  void _pickDate() async {
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (pickedDate != null) {
      setState(() {
        selectedDate = pickedDate;
      });
      loadData(selectedLine, _formatDate(selectedDate));
    }
  }

  void _changeLine(String? newLine) {
    if (newLine != null) {
      setState(() {
        selectedLine = newLine;
      });
      loadData(selectedLine, _formatDate(selectedDate));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Counter Table")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 🔹 Dropdown Line Selector
                DropdownButton<String>(
                  value: selectedLine,
                  items: ["A", "B", "C", "D", "E"].map((String line) {
                    return DropdownMenuItem<String>(value: line, child: Text("Line $line"));
                  }).toList(),
                  onChanged: _changeLine,
                ),

                // 🔹 Date Picker
                TextButton.icon(
                  icon: Icon(Icons.calendar_today),
                  label: Text(_formatDate(selectedDate)),
                  onPressed: _pickDate,
                ),
              ],
            ),
          ),

          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator())
                : Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: PlutoGrid(
                      columns: columns,
                      rows: rows,
                      columnGroups: columnGroups,
                      onLoaded: (PlutoGridOnLoadedEvent event) {},
                      onChanged: (PlutoGridOnChangedEvent event) {},
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
