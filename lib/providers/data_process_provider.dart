import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/data_process_repository.dart';

// 🔹 Provider repository
final dataProcessRepositoryProvider = Provider((ref) => DataProcessRepository());

// 🔹 Provider untuk mendapatkan data Firestore
final basicDataProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final repository = ref.read(dataProcessRepositoryProvider);
  return repository.getBasicData();
});

// 🔹 Provider untuk menambah proses baru
final addProcessProvider = FutureProvider.family<void, String>((ref, newProcess) async {
  final repository = ref.read(dataProcessRepositoryProvider);
  await repository.addProcess(newProcess);
});

// 🔹 Provider untuk mengupdate proses
final updateProcessProvider = FutureProvider.family<void, Map<String, dynamic>>((ref, params) async {
  final repository = ref.read(dataProcessRepositoryProvider);
  await repository.updateProcess(params['index'], params['updatedName']);
});

// 🔹 Provider untuk menghapus proses
final deleteProcessProvider = FutureProvider.family<void, int>((ref, index) async {
  final repository = ref.read(dataProcessRepositoryProvider);
  await repository.deleteProcess(index);
});