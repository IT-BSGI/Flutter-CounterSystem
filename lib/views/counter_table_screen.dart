import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<List<Map<String, dynamic>>> fetchCounterData(String line, String date) async {
    FirebaseFirestore firestore = FirebaseFirestore.instance;
    CollectionReference counterRef = firestore.collection('counter_sistem').doc(line).collection(date);

    QuerySnapshot snapshot = await counterRef.get();

    if (snapshot.docs.isEmpty) return [];

    return snapshot.docs.map((doc) {
      String processName = doc.id;
      Map<String, dynamic> processData = {"process_name": processName};
      Map<String, dynamic>? timeData = doc.data() as Map<String, dynamic>?;

      if (timeData != null) {
        for (String time in ["07:30", "08:30", "09:30", "10:30", "11:30", "13:30", "14:30", "15:30", "16:30"]) {
          if (timeData.containsKey(time)) {
            processData[time] = timeData[time];
          }
        }
      }
      return processData;
    }).toList();
  }

  Future<void> loadData() async {
    setState(() => isLoading = true);

    String formattedDate = DateFormat("yyyy-MM-dd").format(selectedDate);
    List<Map<String, dynamic>> data = await fetchCounterData(selectedLine, formattedDate);

    List<String> timeSlots = ["07:30", "08:30", "09:30", "10:30", "11:30", "13:30", "14:30", "15:30", "16:30"];

    columns = [
      PlutoColumn(
        title: "PROCESS",
        field: "process_name",
        type: PlutoColumnType.text(),
        width: 120,
      ),
    ];

    columnGroups = [];

    for (String time in timeSlots) {
      for (int i = 1; i <= 5; i++) {
        columns.add(PlutoColumn(
          title: "$i",
          field: "${time}_$i",
          type: PlutoColumnType.number(),
          width: 50,
          textAlign: PlutoColumnTextAlign.center,
        ));
      }
      columns.add(
        PlutoColumn(
          title: "Total",
          field: "${time}_total",
          type: PlutoColumnType.number(),
          width: 60,
          textAlign: PlutoColumnTextAlign.center,
          backgroundColor: Colors.yellow.shade200,
        ),
      );

      columnGroups.add(
        PlutoColumnGroup(
          title: time,
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

    columns.add(
      PlutoColumn(
        title: "GRAND TOTAL",
        field: "grand_total",
        type: PlutoColumnType.number(),
        width: 120,
        textAlign: PlutoColumnTextAlign.center,
        backgroundColor: Colors.orange.shade300,
      ),
    );

    rows = data.map((entry) {
      Map<String, PlutoCell> cells = {
        "process_name": PlutoCell(value: entry["process_name"]),
      };

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

  Future<void> selectDate(BuildContext context) async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
    );

    if (picked != null && picked != selectedDate) {
      setState(() => selectedDate = picked);
      loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Counter Table"),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            tooltip: "Refresh Data",
            onPressed: () => loadData(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                DropdownButton<String>(
                  value: selectedLine,
                  items: ["A", "B", "C", "D", "E"]
                      .map((line) => DropdownMenuItem(value: line, child: Text("Line $line")))
                      .toList(),
                  onChanged: (value) {
                    setState(() => selectedLine = value!);
                    loadData();
                  },
                ),
                TextButton.icon(
                  icon: Icon(Icons.calendar_today, size: 18),
                  label: Text(DateFormat("yyyy-MM-dd").format(selectedDate)),
                  onPressed: () => selectDate(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? Center(child: Text("No Data Available", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))
                    : Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: PlutoGrid(
                          columns: columns,
                          rows: rows,
                          columnGroups: columnGroups,
                          configuration: PlutoGridConfiguration(
                            style: PlutoGridStyleConfig(
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
