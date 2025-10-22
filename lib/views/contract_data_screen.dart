import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:dropdown_search/dropdown_search.dart';

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

  @override
  void initState() {
    super.initState();
    _loadMasterContracts();
  }

  Future<void> _loadMasterContracts() async {
    setState(() => isLoadingContracts = true);
    
    try {
      DocumentSnapshot contractsSnapshot = 
          await FirebaseFirestore.instance.collection('basic_data').doc('contracts').get();
      
      if (contractsSnapshot.exists) {
        Map<String, dynamic> contractsData = _convertToStringDynamicMap(contractsSnapshot.data());
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
    } catch (e) {
      print('Error loading master contracts: $e');
      setState(() {
        contractNames = [];
      });
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
      
      // Build tabel hanya dengan tanggal yang memiliki data
      _buildTableStructure(datesWithData, processNames, dateData);

    } catch (e) {
      print('Error loading contract data: $e');
    } finally {
      setState(() => isLoadingData = false);
    }
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
    
    // Cari proses di semua tanggal seperti di final_page
    for (final date in datesInMonth) {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      
      for (final line in ["A", "B", "C", "D", "E"]) {
        for (final type in ["Kumitate", "Part"]) {
          try {
            final contractRef = FirebaseFirestore.instance
                .collection('counter_sistem')
                .doc(dateStr)
                .collection(line)
                .doc(type)
                .collection(selectedContract!);

            final snapshot = await contractRef.get();
            
            for (final doc in snapshot.docs) {
              final processName = doc.id.replaceAll('_', ' ');
              processNames.add(processName);
            }
          } catch (e) {
            // Continue jika error
          }
        }
      }
    }
    
    print('Total ${processNames.length} processes found for contract: $selectedContract');
    return processNames.toList()..sort();
  }

  Future<Map<String, Map<String, Map<String, int>>>> _loadAllDateData(
      List<DateTime> dates, List<String> processNames) async {
    final allData = <String, Map<String, Map<String, int>>>{};
    
    // Load data untuk setiap tanggal seperti di final_page
    for (final date in dates) {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final dateProcessData = <String, Map<String, int>>{};
      
      for (final processName in processNames) {
        final processLineData = <String, int>{};
        
        for (final line in ["A", "B", "C", "D", "E"]) {
          final lineTotal = await _getProcessTotalForDateAndLine(
            dateStr, 
            processName, 
            line
          );
          
          processLineData[line] = lineTotal;
        }
        
        dateProcessData[processName] = processLineData;
      }
      
      allData[dateStr] = dateProcessData;
    }
    
    print('Loaded data for ${allData.length} dates');
    return allData;
  }

  List<DateTime> _getDatesWithData(
      Map<String, Map<String, Map<String, int>>> dateData, 
      List<DateTime> allDates) {
    final datesWithData = <DateTime>[];
    
    for (final date in allDates) {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final dateProcessData = dateData[dateStr];
      
      // Cek apakah ada data di setidaknya satu line untuk tanggal ini
      bool hasData = false;
      if (dateProcessData != null) {
        for (final processData in dateProcessData.values) {
          for (final lineValue in processData.values) {
            if (lineValue > 0) {
              hasData = true;
              break;
            }
          }
          if (hasData) break;
        }
      }
      
      if (hasData) {
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

    // Add process name column
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
        frozen: PlutoColumnFrozen.start,
        renderer: (ctx) {
          return Container(
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              ctx.cell.value.toString(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          );
        },
      ),
    );

    columnGroups.add(
      PlutoColumnGroup(
        title: "Process",
        fields: ["process_name"],
        backgroundColor: Colors.blue.shade300,
      ),
    );

    // Create rows for each process
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
          renderer: (ctx) {
            final value = ctx.cell.value;
            return Container(
              alignment: Alignment.center,
              child: Text(
                value?.toString() ?? '0',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
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

  Future<int> _getProcessTotalForDateAndLine(String dateStr, String processName, String line) async {
    try {
      final processDocName = processName.replaceAll(' ', '_');
      int total = 0;
      
      // Gunakan pendekatan yang sama seperti di final_page
      for (final type in ["Kumitate", "Part"]) {
        try {
          final processRef = FirebaseFirestore.instance
              .collection('counter_sistem')
              .doc(dateStr)
              .collection(line)
              .doc(type)
              .collection(selectedContract!)
              .doc(processDocName);

          final doc = await processRef.get();
          
          if (!doc.exists) continue;

          final data = doc.data()!;

          // Baca semua field data seperti di final_page
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
        } catch (e) {
          // Continue ke type berikutnya jika error
          continue;
        }
      }

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
                            _loadContractData();
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
                              _loadContractData();
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
                              _loadContractData();
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
            child: isLoadingData
                ? _buildLoadingWidget()
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

  Widget _buildLoadingWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            "Loading contract data...",
            style: TextStyle(
              fontSize: 16,
              color: Colors.blue.shade700,
            ),
          ),
          SizedBox(height: 8),
          Text(
            "Contract: $selectedContract",
            style: TextStyle(
              fontSize: 14,
              color: Colors.blue.shade600,
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
            borderColor: Colors.blue.shade800,
            rowHeight: 50,
            columnHeight: 50,
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