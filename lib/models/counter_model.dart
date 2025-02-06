import 'package:cloud_firestore/cloud_firestore.dart';


class CounterModel {
  final String id;
  final int value;
  final DateTime timestamp;

  CounterModel({required this.id, required this.value, required this.timestamp});

  factory CounterModel.fromFirestore(Map<String, dynamic> data, String id) {
    return CounterModel(
      id: id,
      value: data['value'] ?? 0,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'value': value,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}

