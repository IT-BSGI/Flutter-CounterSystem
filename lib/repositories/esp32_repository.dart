import 'package:cloud_firestore/cloud_firestore.dart';

class CounterRepository {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // 🔹 Ambil data dari counter_sistem/basic_data
  Future<Map<String, dynamic>?> getBasicData() async {
    DocumentSnapshot doc = await firestore.collection('counter_sistem').doc('basic_data').get();
    
    if (doc.exists) {
      return doc.data() as Map<String, dynamic>;
    } else {
      return null;
    }
  }

  // 🔹 Tambah data ke Firestore
  Future<void> addProcess(String newProcess) async {
    DocumentReference docRef = firestore.collection('counter_sistem').doc('basic_data');
    DocumentSnapshot doc = await docRef.get();

    if (doc.exists) {
      List<dynamic> processNames = (doc['process_name'] ?? []) as List<dynamic>;
      processNames.add(newProcess);
      await docRef.update({'process_name': processNames});
    }
  }

  // 🔹 Update proses (ganti nama proses)
  Future<void> updateProcess(int index, String updatedName) async {
    DocumentReference docRef = firestore.collection('counter_sistem').doc('basic_data');
    DocumentSnapshot doc = await docRef.get();

    if (doc.exists) {
      List<dynamic> processNames = (doc['process_name'] ?? []) as List<dynamic>;
      if (index < processNames.length) {
        processNames[index] = updatedName;
        await docRef.update({'process_name': processNames});
      }
    }
  }

  // 🔹 Hapus proses dari Firestore
  Future<void> deleteProcess(int index) async {
    DocumentReference docRef = firestore.collection('counter_sistem').doc('basic_data');
    DocumentSnapshot doc = await docRef.get();

    if (doc.exists) {
      List<dynamic> processNames = (doc['process_name'] ?? []) as List<dynamic>;
      if (index < processNames.length) {
        processNames.removeAt(index);
        await docRef.update({'process_name': processNames});
      }
    }
  }
}
