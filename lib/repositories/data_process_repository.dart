import 'package:cloud_firestore/cloud_firestore.dart';

class DataProcessRepository {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // 🔹 Ambil data dari counter_sistem/data_process
  Future<Map<String, dynamic>?> getBasicData() async {
    DocumentSnapshot doc = await firestore.collection('counter_sistem').doc('data_process').get();
    
    if (doc.exists) {
      return doc.data() as Map<String, dynamic>;
    } else {
      return null;
    }
  }

  // 🔹 Tambah data ke Firestore
  Future<void> addProcess(String newProcess) async {
    DocumentReference docRef = firestore.collection('counter_sistem').doc('data_process');
    DocumentSnapshot doc = await docRef.get();

    if (doc.exists) {
      List<dynamic> processA = (doc['process_a'] ?? []) as List<dynamic>;
      processA.add(newProcess);
      await docRef.update({'process_a': processA});

      List<dynamic> processB = (doc['process_b'] ?? []) as List<dynamic>;
      processB.add(newProcess);
      await docRef.update({'process_b': processB});

      List<dynamic> processC = (doc['process_c'] ?? []) as List<dynamic>;
      processC.add(newProcess);
      await docRef.update({'process_c': processC});

      List<dynamic> processD = (doc['process_d'] ?? []) as List<dynamic>;
      processD.add(newProcess);
      await docRef.update({'process_d': processD});

      List<dynamic> processE = (doc['process_e'] ?? []) as List<dynamic>;
      processE.add(newProcess);
      await docRef.update({'process_e': processE});
    }
  }

  // 🔹 Update proses (ganti nama proses)
  Future<void> updateProcess(int index, String updatedName) async {
    DocumentReference docRef = firestore.collection('counter_sistem').doc('data_process');
    DocumentSnapshot doc = await docRef.get();

    if (doc.exists) {
      List<dynamic> processA = (doc['process_a'] ?? []) as List<dynamic>;
      if (index < processA.length) {
        processA[index] = updatedName;
        await docRef.update({'process_a': processA});
      }
      List<dynamic> processB = (doc['process_b'] ?? []) as List<dynamic>;
      if (index < processB.length) {
        processB[index] = updatedName;
        await docRef.update({'process_b': processB});
      }
      List<dynamic> processC = (doc['process_c'] ?? []) as List<dynamic>;
      if (index < processC.length) {
        processC[index] = updatedName;
        await docRef.update({'process_c': processC});
      }
      List<dynamic> processD = (doc['process_d'] ?? []) as List<dynamic>;
      if (index < processD.length) {
        processD[index] = updatedName;
        await docRef.update({'process_d': processD});
      }
      List<dynamic> processE = (doc['process_e'] ?? []) as List<dynamic>;
      if (index < processE.length) {
        processE[index] = updatedName;
        await docRef.update({'process_e': processE});
      }
    }
  }

  // 🔹 Hapus proses dari Firestore
  Future<void> deleteProcess(int index) async {
    DocumentReference docRef = firestore.collection('counter_sistem').doc('data_process');
    DocumentSnapshot doc = await docRef.get();

    if (doc.exists) {
      List<dynamic> processA = (doc['process_a'] ?? []) as List<dynamic>;
      if (index < processA.length) {
        processA.removeAt(index);
        await docRef.update({'process_a': processA});
      }
      List<dynamic> processB = (doc['process_b'] ?? []) as List<dynamic>;
      if (index < processB.length) {
        processB.removeAt(index);
        await docRef.update({'process_b': processB});
      }
      List<dynamic> processC = (doc['process_c'] ?? []) as List<dynamic>;
      if (index < processC.length) {
        processC.removeAt(index);
        await docRef.update({'process_c': processC});
      }
      List<dynamic> processD = (doc['process_d'] ?? []) as List<dynamic>;
      if (index < processD.length) {
        processD.removeAt(index);
        await docRef.update({'process_d': processD});
      }
      List<dynamic> processE = (doc['process_e'] ?? []) as List<dynamic>;
      if (index < processE.length) {
        processE.removeAt(index);
        await docRef.update({'process_e': processE});
      }
    }
  }
}
