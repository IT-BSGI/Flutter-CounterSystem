import 'package:cloud_firestore/cloud_firestore.dart';

Future<List<Map<String, dynamic>>> fetchCounterData(String line, String date) async {
  FirebaseFirestore firestore = FirebaseFirestore.instance;
  CollectionReference counterRef = firestore.collection('counter_sistem').doc(line).collection(date);

  QuerySnapshot snapshot = await counterRef.get();
  
  List<Map<String, dynamic>> result = [];

  for (var doc in snapshot.docs) {
    String processName = doc.id;
    Map<String, dynamic> processData = {"process_name": processName};

    DocumentSnapshot timeSnapshot = await counterRef.doc(processName).get();

    if (timeSnapshot.exists) {
      Map<String, dynamic>? timeData = timeSnapshot.data() as Map<String, dynamic>?;

      if (timeData != null && timeData.containsKey("07:30")) {
        processData["07:30"] = timeData["07:30"];
      }
    }

    result.add(processData);
  }

  return result;
}
