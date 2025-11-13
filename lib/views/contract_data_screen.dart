import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'dart:async';

class ContractDataScreen extends StatefulWidget {
  @override
  _ContractDataScreenState createState() => _ContractDataScreenState();
}

class _ContractDataScreenState extends State<ContractDataScreen> {
  int selectedYear = DateTime.now().year;
  int selectedMonth = DateTime.now().month;
  String? selectedContract;
  
  bool isLoadingContracts = false;
  bool isLoadingData = false;
  
  List<String> contractNames = [];
  List<PlutoColumn> columns = [];
  List<PlutoRow> rows = [];
  List<PlutoColumnGroup> columnGroups = [];

  Timer? _loadDataTimer;

  // Urutan proses yang ditentukan
  final List<String> desiredProcessOrder = [
    "Maekata JinuiFuse",
    "Maekata Jinui",
    "Maekata Fuse",
    "Eri Pipping",
    "Eri Tsuke",
    "Overlock Eri Tsuke",
    "Eri Fuse",
    "Sode Tsuke Interlock",
    "Sode Tsuke Honnui",
    "Iron Sode Tsuke",
    "Sode Fuse",
    "Sode Fuse 8mm",
    "Sode Fuse 1mm",
    "Wakinui Interlock",
    "Wakinui Nihonbari",
    "Waki Honnui",
    "Iron Waki",
    "Waki Fuse",
    "Cuff Tsuke",
    "Kazari Cuff",
    "Mitsumaki",
    "Gazet",
    "Kandome",
    "Bottan Tsuke",
    "Maemi IN", 
    "Maemi OUT", 
    "Ushiro IN", 
    "Ushiro OUT",
    "Eri IN", 
    "Eri OUT", 
    "Sode IN", 
    "Sode OUT",
    "Cuff IN", 
    "Cuff OUT",
  ];

  @override
  void initState() {
    super.initState();
    _loadMasterContracts();
  }

  @override
  void dispose() {
    _loadDataTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMasterContracts() async {
    setState(() => isLoadingContracts = true);
    
    try {
      // Mengambil kontrak dari struktur baru: basic_data/data_contracts/contracts/
      QuerySnapshot contractsSnapshot = 
          await FirebaseFirestore.instance
              .collection('basic_data')
              .doc('data_contracts')
              .collection('contracts')
              .get();
      
      if (contractsSnapshot.docs.isNotEmpty) {
        setState(() {
          contractNames = contractsSnapshot.docs.map((doc) => doc.id).toList()..sort();
          if (contractNames.isNotEmpty && selectedContract == null) {
            selectedContract = contractNames.first;
          }
        });
      } else {
        setState(() {
          contractNames = [];
        });
      }
    } catch (e) {
      print('Error loading master contracts: $e');
      // Fallback: coba ambil dari struktur lama jika struktur baru tidak ada
      try {
        DocumentSnapshot oldContractsSnapshot = 
            await FirebaseFirestore.instance.collection('basic_data').doc('contracts').get();
        
        if (oldContractsSnapshot.exists) {
          Map<String, dynamic> contractsData = _convertToStringDynamicMap(oldContractsSnapshot.data());
          setState(() {
            contractNames = contractsData.keys.where((key) => key.isNotEmpty).toList()..sort();
            if (contractNames.isNotEmpty && selectedContract == null) {
              selectedContract = contractNames.first;
            }
          });
        } else {
          setState(() {
            contractNames = [];
          });
        }
      } catch (fallbackError) {
        print('Error loading fallback contracts: $fallbackError');
        setState(() {
          contractNames = [];
        });
      }
    } finally {
      setState(() => isLoadingContracts = false);
    }
  }

  Map<String, dynamic> _convertToStringDynamicMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    } else if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {};
  }

  void _scheduleLoadData() {
    _loadDataTimer?.cancel();
    _loadDataTimer = Timer(Duration(milliseconds: 300), _loadContractData);
  }

  Future<void> _loadContractData() async {
    if (selectedContract == null) return;
    
    setState(() => isLoadingData = true);
    
    try {
      final firstDay = DateTime(selectedYear, selectedMonth, 1);
      final lastDay = DateTime(selectedYear, selectedMonth + 1, 0);
      final datesInMonth = _generateDatesInMonth(firstDay, lastDay);

      // Cari semua proses yang ada untuk kontrak ini dengan mencari di semua tanggal
      final processNames = await _findAllProcessesForContract(datesInMonth);
      
      if (processNames.isEmpty) {
        setState(() {
          rows = [];
          columns = [];
          columnGroups = [];
        });
        return;
      }
      
      // Load data untuk semua tanggal dan proses
      final dateData = await _loadAllDateData(datesInMonth, processNames);
      
      // Filter hanya tanggal yang memiliki data
      final datesWithData = _getDatesWithData(dateData, datesInMonth);
      
      // Filter dan urutkan proses berdasarkan desiredOrder dan hanya yang memiliki data
      final filteredProcessNames = _filterAndSortProcesses(processNames, dateData, datesWithData);
      
      if (filteredProcessNames.isEmpty) {
        setState(() {
          rows = [];
          columns = [];
          columnGroups = [];
        });
        return;
      }
      
      // Build tabel hanya dengan tanggal yang memiliki data dan proses yang difilter
      _buildTableStructure(datesWithData, filteredProcessNames, dateData);

    } catch (e) {
      print('Error loading contract data: $e');
    } finally {
      setState(() => isLoadingData = false);
    }
  }

  List<String> _filterAndSortProcesses(
    List<String> processNames, 
    Map<String, Map<String, Map<String, int>>> dateData, 
    List<DateTime> datesWithData
  ) {
    final processesWithData = <String>{};
    
    // Cek setiap proses apakah memiliki data di setidaknya satu tanggal dan line
    for (final processName in processNames) {
      bool hasData = false;
      
      for (final date in datesWithData) {
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        final processDateData = dateData[dateStr]?[processName];
        
        if (processDateData != null) {
          for (final line in ["A", "B", "C", "D", "E"]) {
            if ((processDateData[line] ?? 0) > 0) {
              hasData = true;
              break;
            }
          }
        }
        if (hasData) break;
      }
      
      if (hasData) {
        processesWithData.add(processName);
      }
    }
    
    // Urutkan berdasarkan desiredOrder dan hanya ambil yang ada di desiredOrder
    final filteredAndSorted = desiredProcessOrder.where((process) => processesWithData.contains(process)).toList();
    
    print('Filtered to ${filteredAndSorted.length} processes with data');
    return filteredAndSorted;
  }

  List<DateTime> _generateDatesInMonth(DateTime firstDay, DateTime lastDay) {
    final dates = <DateTime>[];
    for (var date = firstDay; date.isBefore(lastDay.add(Duration(days: 1))); date = date.add(Duration(days: 1))) {
      dates.add(date);
    }
    return dates;
  }

  Future<List<String>> _findAllProcessesForContract(List<DateTime> datesInMonth) async {
    final processNames = <String>{};
    
    print('Searching processes in ${datesInMonth.length} dates for contract: $selectedContract');
    
    // Buat semua query sekaligus
    final queries = <Future<QuerySnapshot>>[];
    
    for (final date in datesInMonth) {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      
      for (final line in ["A", "B", "C", "D", "E"]) {
        for (final type in ["Kumitate", "Part"]) {
          final contractRef = FirebaseFirestore.instance
              .collection('counter_sistem')
              .doc(dateStr)
              .collection(line)
              .doc(type)
              .collection(selectedContract!);

          queries.add(contractRef.get().catchError((e) {
            return FirebaseFirestore.instance
                .collection('counter_sistem')
                .doc('dummy')
                .collection('dummy')
                .get();
          }));
        }
      }
    }
    
    // Eksekusi semua query secara parallel
    final snapshots = await Future.wait(queries);
    
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        final processName = doc.id.replaceAll('_', ' ');
        processNames.add(processName);
      }
    }
    
    print('Total ${processNames.length} processes found for contract: $selectedContract');
    return processNames.toList();
  }

  Future<Map<String, Map<String, Map<String, int>>>> _loadAllDateData(
      List<DateTime> dates, List<String> processNames) async {
    final allData = <String, Map<String, Map<String, int>>>{};
    
    // Buat batch queries untuk semua tanggal
    final dateQueries = <Future<void>>[];
    
    for (final date in dates) {
      dateQueries.add(_loadSingleDateData(date, processNames, allData));
    }
    
    // Eksekusi parallel
    await Future.wait(dateQueries);
    
    print('Loaded data for ${allData.length} dates');
    return allData;
  }

  Future<void> _loadSingleDateData(
      DateTime date, 
      List<String> processNames, 
      Map<String, Map<String, Map<String, int>>> allData) async {
    
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final dateProcessData = <String, Map<String, int>>{};
    
    // Buat queries untuk semua proses secara parallel
    final processQueries = <Future<void>>[];
    
    for (final processName in processNames) {
      processQueries.add(_loadProcessData(dateStr, processName, dateProcessData));
    }
    
    await Future.wait(processQueries);
    
    // Hanya simpan jika ada data
    if (dateProcessData.values.any((processData) => 
        processData.values.any((value) => value > 0))) {
      allData[dateStr] = dateProcessData;
    }
  }

  Future<void> _loadProcessData(
      String dateStr, 
      String processName, 
      Map<String, Map<String, int>> dateProcessData) async {
    
    final processLineData = <String, int>{};
    final lineQueries = <Future<void>>[];
    
    for (final line in ["A", "B", "C", "D", "E"]) {
      lineQueries.add(_getProcessTotalForDateAndLine(dateStr, processName, line)
          .then((total) {
        if (total > 0) {
          processLineData[line] = total;
        }
      }));
    }
    
    await Future.wait(lineQueries);
    
    if (processLineData.isNotEmpty) {
      dateProcessData[processName] = processLineData;
    }
  }

  List<DateTime> _getDatesWithData(
      Map<String, Map<String, Map<String, int>>> dateData, 
      List<DateTime> allDates) {
    final datesWithData = <DateTime>[];
    
    for (final date in allDates) {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final dateProcessData = dateData[dateStr];
      
      if (dateProcessData != null && dateProcessData.isNotEmpty) {
        datesWithData.add(date);
      }
    }
    
    print('Found ${datesWithData.length} dates with data');
    return datesWithData;
  }

  void _buildTableStructure(
      List<DateTime> dates, 
      List<String> processNames,
      Map<String, Map<String, Map<String, int>>> dateData) {
    columns = [];
    rows = [];
    columnGroups = [];

    // Add process name column - TINGGI PENUH tanpa grup terpisah
    columns.add(
      PlutoColumn(
        title: "PROCESS",
        field: "process_name",
        type: PlutoColumnType.text(),
        width: 200,
        titleTextAlign: PlutoColumnTextAlign.center,
        backgroundColor: Colors.blue.shade300,
        enableColumnDrag: false,
        enableContextMenu: false,
        enableSorting: false,
        enableEditingMode: false,
        enableDropToResize: false,
        enableFilterMenuItem: false,
        enableHideColumnMenuItem: false,
        enableRowDrag: false,
        enableRowChecked: false,
        frozen: PlutoColumnFrozen.start,
        cellPadding: EdgeInsets.zero,
        renderer: (ctx) => Container(
          constraints: BoxConstraints.expand(),
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            border: Border(
              right: BorderSide(color: Colors.blue, width: 1),
              bottom: BorderSide(color: Colors.blue, width: 1),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              ctx.cell.value.toString(),
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );

    // Create rows for each process (sudah terurut berdasarkan desiredOrder)
    for (final processName in processNames) {
      final cells = <String, PlutoCell>{
        "process_name": PlutoCell(value: processName),
      };
      
      // Initialize all date-line cells with data from dateData
      for (final date in dates) {
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        final processDateData = dateData[dateStr]?[processName];
        
        for (final line in ["A", "B", "C", "D", "E"]) {
          final fieldName = "${dateStr}_$line";
          final value = processDateData?[line] ?? 0;
          cells[fieldName] = PlutoCell(value: value);
        }
      }
      
      rows.add(PlutoRow(cells: cells));
    }

    // Add date columns and groups with line sub-columns hanya untuk tanggal yang memiliki data
    for (final date in dates) {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final displayDateStr = DateFormat('dd-MM').format(date);
      
      _addDateColumnsWithLines(displayDateStr, dateStr);
    }
    
    print('Table built with ${rows.length} processes and ${dates.length} dates');
  }

  void _addDateColumnsWithLines(String displayDateStr, String dateStr) {
    final lineFields = <String>[];
    
    for (final line in ["A", "B", "C", "D", "E"]) {
      final fieldName = "${dateStr}_$line";
      lineFields.add(fieldName);
      
      columns.add(
        PlutoColumn(
          title: line,
          field: fieldName,
          type: PlutoColumnType.number(),
          width: 60,
          titleTextAlign: PlutoColumnTextAlign.center,
          textAlign: PlutoColumnTextAlign.center,
          backgroundColor: Colors.blue.shade100,
          enableColumnDrag: false,
          enableContextMenu: false,
          enableSorting: false,
          enableEditingMode: false,
          enableDropToResize: false,
          enableFilterMenuItem: false,
          enableHideColumnMenuItem: false,
          enableRowDrag: false,
          enableRowChecked: false,
          cellPadding: EdgeInsets.zero,
          renderer: (ctx) {
            final value = ctx.cell.value;
            final isWeekend = _isWeekend(dateStr);
            
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
                value?.toString() ?? '0',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: (value ?? 0) > 0 ? Colors.black : Colors.grey,
                ),
              ),
            );
          },
        ),
      );
    }

    columnGroups.add(
      PlutoColumnGroup(
        title: displayDateStr,
        fields: lineFields,
        backgroundColor: Colors.blue.shade200,
      ),
    );
  }

  bool _isWeekend(String dateStr) {
    try {
      final date = DateFormat('yyyy-MM-dd').parse(dateStr);
      return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    } catch (e) {
      return false;
    }
  }

  Future<int> _getProcessTotalForDateAndLine(String dateStr, String processName, String line) async {
    try {
      final processDocName = processName.replaceAll(' ', '_');
      int total = 0;
      
      // Query kedua tipe secara parallel
      final typeQueries = <Future<int>>[];
      
      for (final type in ["Kumitate", "Part"]) {
        typeQueries.add(_getTypeTotal(dateStr, processDocName, line, type));
      }
      
      final results = await Future.wait(typeQueries);
      total = results.fold(0, (sum, value) => sum + value);
      
      return total;
    } catch (e) {
      return 0;
    }
  }

  Future<int> _getTypeTotal(String dateStr, String processDocName, String line, String type) async {
    try {
      final processRef = FirebaseFirestore.instance
          .collection('counter_sistem')
          .doc(dateStr)
          .collection(line)
          .doc(type)
          .collection(selectedContract!)
          .doc(processDocName);

      final doc = await processRef.get();
      
      if (!doc.exists) return 0;

      final data = doc.data()!;
      int total = 0;

      data.forEach((key, value) {
        if (key != 'sequence' && 
            key != 'belumKensa' && 
            key != 'stock_20min' && 
            key != 'stock_pagi' && 
            key != 'part' &&
            value is Map<String, dynamic>) {
          value.forEach((lineKey, lineValue) {
            total += (lineValue as int? ?? 0);
          });
        }
      });

      return total;
    } catch (e) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade100,
      appBar: AppBar(
        title: Text(
          "Contract Data",
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
            icon: Icon(Icons.refresh, color: Colors.white),
            tooltip: "Refresh Data",
            onPressed: () {
              _loadMasterContracts();
              if (selectedContract != null) {
                _loadContractData();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search/Filter Section
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Contract Dropdown Search
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade500, width: 1),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: DropdownSearch<String>(
                        popupProps: PopupProps.menu(
                          showSelectedItems: true,
                          showSearchBox: true,
                          searchFieldProps: TextFieldProps(
                            decoration: InputDecoration(
                              hintText: "Search contract...",
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12),
                            ),
                          ),
                          menuProps: MenuProps(
                            backgroundColor: Colors.white,
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          listViewProps: ListViewProps(
                            padding: EdgeInsets.zero,
                          ),
                          fit: FlexFit.loose,
                        ),
                        items: contractNames,
                        dropdownBuilder: (context, selectedItem) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              selectedItem ?? "Select Contract",
                              style: TextStyle(
                                fontSize: 16,
                                color: selectedItem != null ? Colors.black : Colors.grey,
                              ),
                            ),
                          );
                        },
                        onChanged: (String? value) {
                          setState(() {
                            selectedContract = value;
                          });
                          if (value != null) {
                            _scheduleLoadData(); // Gunakan debounced version
                          }
                        },
                        selectedItem: selectedContract,
                        dropdownDecoratorProps: DropDownDecoratorProps(
                          dropdownSearchDecoration: InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 16),

                // Month/Year Selector
                Row(
                  children: [
                    Container(
                      width: 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade500, width: 1),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: selectedYear,
                          items: List.generate(3, (i) {
                            final year = DateTime.now().year - 1 + i;
                            return DropdownMenuItem(
                              value: year,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  year.toString(),
                                  style: TextStyle(fontSize: 14),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          }),
                          onChanged: (value) {
                            setState(() => selectedYear = value!);
                            if (selectedContract != null) {
                              _scheduleLoadData(); // Gunakan debounced version
                            }
                          },
                          icon: Icon(Icons.arrow_drop_down, size: 24, color: Colors.blue.shade600),
                          style: TextStyle(color: Colors.black),
                          dropdownColor: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Container(
                      width: 140,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade500, width: 1),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: selectedMonth,
                          items: List.generate(12, (i) {
                            final month = i + 1;
                            return DropdownMenuItem(
                              value: month,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  DateFormat('MMMM').format(DateTime(0, month)),
                                  style: TextStyle(fontSize: 14),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          }),
                          onChanged: (value) {
                            setState(() => selectedMonth = value!);
                            if (selectedContract != null) {
                              _scheduleLoadData(); // Gunakan debounced version
                            }
                          },
                          icon: Icon(Icons.arrow_drop_down, size: 24, color: Colors.blue.shade600),
                          style: TextStyle(color: Colors.black),
                          dropdownColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Data Table
          Expanded(
            child: isLoadingContracts
                ? _buildLoadingWidget("Loading contracts...")
                : isLoadingData
                    ? _buildLoadingWidget("Loading contract data...")
                    : selectedContract == null
                        ? _buildPlaceholderWidget("Please select a contract to view data", Icons.assignment)
                        : rows.isEmpty
                            ? _buildPlaceholderWidget("No data available for selected contract", Icons.data_array)
                            : _buildDataTable(),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingWidget(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: Colors.blue.shade700,
            ),
          ),
          SizedBox(height: 8),
          if (selectedContract != null) ...[
            Text(
              "Contract: $selectedContract",
              style: TextStyle(
                fontSize: 14,
                color: Colors.blue.shade600,
              ),
            ),
            SizedBox(height: 4),
          ],
          Text(
            "This may take a few moments...",
            style: TextStyle(
              fontSize: 12,
              color: Colors.blue.shade500,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderWidget(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.blue.shade300),
          SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 18,
              color: Colors.blue.shade700,
            ),
            textAlign: TextAlign.center,
          ),
          if (selectedContract != null) ...[
            SizedBox(height: 8),
            Text(
              "Contract: $selectedContract",
              style: TextStyle(
                fontSize: 14,
                color: Colors.blue.shade600,
              ),
            ),
          ],
          if (contractNames.isEmpty) ...[
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadMasterContracts,
              child: Text("Retry Loading Contracts"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade500,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDataTable() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: PlutoGrid(
        key: ValueKey('${selectedContract}_${selectedYear}_${selectedMonth}_${rows.length}'),
        columns: columns,
        rows: rows,
        columnGroups: columnGroups,
        configuration: PlutoGridConfiguration(
          style: PlutoGridStyleConfig(
            gridBackgroundColor: Colors.blue.shade50,
            rowColor: Colors.blue.shade50,
            borderColor: Colors.blue,
            rowHeight: 32,
            columnHeight: 36,
            cellTextStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            columnTextStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            activatedBorderColor: Colors.blue,
            activatedColor: Colors.blue.shade50,
            gridBorderColor: Colors.blue,
          ),
          scrollbar: PlutoGridScrollbarConfig(
            isAlwaysShown: true,
            scrollbarThickness: 5,
          ),
        ),
        mode: PlutoGridMode.readOnly,
      ),
    );
  }
}