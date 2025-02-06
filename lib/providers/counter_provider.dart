import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/counter_repository.dart';

// 🔹 Provider untuk repository
final counterRepositoryProvider = Provider((ref) => CounterRepository());

// 🔹 Provider untuk mendapatkan data produksi berdasarkan line & tanggal
final productionDataProvider = FutureProvider.family<Map<String, Map<String, int>>, Map<String, String>>(
  (ref, params) async {
    final repository = ref.read(counterRepositoryProvider);
    return repository.getProductionData(params['line']!, params['date']!);
  },
);
