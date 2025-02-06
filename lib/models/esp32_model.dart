import 'package:cloud_firestore/cloud_firestore.dart';


class Esp32Model {
  final String id;
  final int value;
  final DateTime timestamp;

  Esp32Model({required this.id, required this.value, required this.timestamp});

  factory Esp32Model.fromFirestore(Map<String, dynamic> data, String id) {
    return Esp32Model(
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

