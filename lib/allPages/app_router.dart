import 'package:flutter/material.dart';
import 'package:swiftserve/allPages/adminSection/adminCashInventory_view.dart';
import 'package:swiftserve/allPages/adminSection/KitchenCounterscannerPage.dart';
import 'package:swiftserve/allPages/adminSection/kitchenOrderPage.dart';
import 'package:swiftserve/allPages/loginSignUpPage/loginOrSignUpscreen.dart';
import 'package:swiftserve/allPages/userRoutingPages/cartScreen.dart';
import 'package:swiftserve/allPages/userRoutingPages/homeScreen.dart';
import 'package:swiftserve/allPages/userRoutingPages/order_progress_page.dart';
import 'package:swiftserve/allPages/userRoutingPages/walletPage.dart';

class AppRoutes {
  static const String auth = '/auth';
  static const String home = '/home';
  static const String cart = '/cart';
  static const String wallet = '/wallet';
  static const String orderTracker = '/orderTracker';
  static const String kitchenOrder = '/kitchenOrder';
  static const String counterScanner = '/counterScanner';
  static const String adminInventory = '/adminInventory';

  // App Theme
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF121212),
      primarySwatch: Colors.amber,
    );
  }

  // --- Routes Map ---
  static Map<String, WidgetBuilder> get routes {
    return {
      auth: (context) => const AuthView(),
      home: (context) => const HomeScreen(),
      cart: (context) => const CartScreen(),
      wallet: (context) => const WalletPage(),
      orderTracker: (context) => const OrderProgressPage(),
      kitchenOrder: (context) => const KitchenOrderPage(),
      counterScanner: (context) => const CounterScannerPage(),
      adminInventory: (context) => const AdminCashInventoryView(),
    };
  }
}
