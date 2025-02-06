import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_options.dart';
// import 'views/add_counter_view.dart';
// import 'views/counter_list_view.dart';
// import 'views/esp32_view.dart';
import 'views/dashboard.dart';
// import 'views/counter_list_view.dart';
// import 'views/settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Counter System',
      theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        ),
      // home: CounterListView(userId: "userId_123"),
      // home: AddCounterView(userId: "userId_123"),
      // home: CounterDataView(),
      // home: AdminPanel(),
      home: DashboardPanel(),
      // home: CounterTableView(),
      // routes: {
      //   '/settings': (context) => SettingsPage(), // Rute ke halaman Settings
      // },
    );
  }
}
