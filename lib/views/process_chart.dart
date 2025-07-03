import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class ProcessChart extends StatelessWidget {
  final List<int> values;

  const ProcessChart({super.key, required this.values});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: values.asMap().entries.map((entry) {
                return FlSpot(entry.key.toDouble(), entry.value.toDouble());
              }).toList(),
              isCurved: true,
              barWidth: 2,
              color: Colors.blueAccent,
              belowBarData: BarAreaData(show: false),
              dotData: FlDotData(show: true),
            ),
          ],
          titlesData: FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(show: false),
        ),
      ),
    );
  }
}
