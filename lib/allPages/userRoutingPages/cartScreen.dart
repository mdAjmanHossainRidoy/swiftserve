import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'homeScreen.dart'; // Ensure globalCart is accessible
import '../app_router.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _supabase = Supabase.instance.client;
  bool _isCheckingOut = false;

  void _msg(String text, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  double get _totalPrice {
    double total = 0.0;
    for (final item in globalCart) {
      final price = (item['price'] as num?)?.toDouble() ?? 0.0;
      final qty = (item['qty'] as num?)?.toInt() ?? 1;
      total += price * qty;
    }
    return total;
  }

  // ATOMIC CHECKOUT PROCESS
  Future<void> _processCheckout() async {
    if (globalCart.isEmpty) return;
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      _msg('Authentication error. Please log in again.', Colors.redAccent);
      return;
    }

    setState(() => _isCheckingOut = true);

    try {
      final totalPrice = _totalPrice;

      // Format cart into a JSON-compatible list for PostgreSQL
      final List<Map<String, dynamic>> cartPayload = globalCart.map((item) {
        return {
          'id':
              item['id'], // CRITICAL: The menu item's UUID must be in the cart
          'qty': (item['qty'] as num?)?.toInt() ?? 1,
        };
      }).toList();

      final itemsSummary = globalCart
          .map((i) => "${i['qty']}x ${i['name']}")
          .join(', ');

      // Trigger the atomic PL/pgSQL transaction
      await _supabase.rpc(
        'process_checkout',
        params: {
          'p_user_id': userId,
          'p_total_price': totalPrice,
          'p_items_summary': itemsSummary,
          'p_cart_items': cartPayload,
        },
      );

      // Clear volatile memory only after database confirms success
      setState(() => globalCart.clear());

      _msg('Order placed successfully!', Colors.green);

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.orderTracker);
    } on PostgrestException catch (e) {
      // Catches custom RAISE EXCEPTION messages from the PostgreSQL RPC
      _msg(e.message, Colors.redAccent);
    } catch (e) {
      _msg('Checkout failed: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isCheckingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'My Cart & Checkout',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: globalCart.isEmpty
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shopping_cart_outlined,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Your cart is empty.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Add items from the Menu Catalog to start an order.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: globalCart.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (ctx, index) {
                        final item = globalCart[index];
                        final price =
                            (item['price'] as num?)?.toDouble() ?? 0.0;
                        final qty = item['qty'] as int? ?? 1;

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade800),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['name'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '৳ $price each',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                      color: Colors.amber,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        if (qty > 1) {
                                          item['qty'] = qty - 1;
                                        } else {
                                          globalCart.removeAt(index);
                                        }
                                      });
                                    },
                                  ),
                                  Text(
                                    '$qty',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.add_circle_outline,
                                      color: Colors.amber,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() => item['qty'] = qty + 1);
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Amount:',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                      Text(
                        '৳ ${_totalPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: globalCart.isEmpty
                            ? Colors.grey.shade800
                            : Colors.amber,
                        foregroundColor: globalCart.isEmpty
                            ? Colors.grey
                            : Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: (_isCheckingOut || globalCart.isEmpty)
                          ? null
                          : _processCheckout,
                      child: _isCheckingOut
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Text(
                              'PAY & PLACE ORDER',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
