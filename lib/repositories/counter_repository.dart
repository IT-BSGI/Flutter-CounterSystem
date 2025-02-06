import 'package:cloud_firestore/cloud_firestore.dart';

class CounterRepository {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  Future<Map<String, Map<String, int>>> getProductionData(String line, String date) async {
    CollectionReference<Map<String, dynamic>> lineCollection = firestore
        .collection('counter_sistem')
        .doc('counter')
        .collection(line);

    DocumentSnapshot<Map<String, dynamic>> dateDoc = await lineCollection.doc(date).get();
    if (!dateDoc.exists) return {};

    Map<String, Map<String, int>> processData = {};

    // 🔹 Ambil semua koleksi proses dalam tanggal tersebut
    List<String> processNames = [];

    for (var processName in processNames) {
      QuerySnapshot<Map<String, dynamic>> processSnapshot =
          await lineCollection.doc(date).collection(processName).get();

      for (var doc in processSnapshot.docs) {
        String time = doc.id; // Waktu produksi (ex: "12:30")
        int count = doc.data()['count'] ?? 0;

        if (!processData.containsKey(processName)) {
          processData[processName] = {};
        }

        processData[processName]![time] = count;
      }
    }

    return processData;
  }
}
