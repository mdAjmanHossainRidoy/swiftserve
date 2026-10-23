import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import './allPages/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://hyyohtyknrfczvnxxcbq.supabase.co',
    anonKey: 'sb_publishable_pyBEk7AGoOyUfQxp50zcEQ_j3QxP2i0',
  );

  runApp(const SwiftServeApp());
}

class SwiftServeApp extends StatelessWidget {
  const SwiftServeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SwiftServe Canteen',
      debugShowCheckedModeBanner: false,
      theme: AppRoutes.darkTheme,
      initialRoute: AppRoutes.auth,
      routes: AppRoutes.routes,
    );
  }
}
