import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_router.dart';

class KitchenOrderPage extends StatefulWidget {
  const KitchenOrderPage({super.key});

  @override
  State<KitchenOrderPage> createState() => _KitchenOrderPageState();
}

class _KitchenOrderPageState extends State<KitchenOrderPage> {
  final _supabase = Supabase.instance.client;

  // Tracks in-flight network requests per order ID to prevent double-taps
  final Set<String> _processingOrderIds = {};

  void _msg(String text, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // AUTHENTICATION LOGOUT
  Future<void> _logout() async {
    await _supabase.auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, AppRoutes.auth);
  }

  // GUARDED STATE MACHINE TRANSITION (CAS PATTERN)
  Future<void> _updateOrderStatus(
    String orderId,
    String expectedCurrentStatus,
    String newStatus,
  ) async {
    if (_processingOrderIds.contains(orderId)) return;
    setState(() => _processingOrderIds.add(orderId));

    try {
      // CompareAndSwap: Only update if the order is still in expectedCurrentStatus
      final List<Map<String, dynamic>> updatedRows = await _supabase
          .from('orders')
          .update({'status': newStatus})
          .eq('id', orderId)
          .eq('status', expectedCurrentStatus)
          .select();

      if (updatedRows.isEmpty) {
        _msg(
          'Transition blocked! Order status was already changed by another device.',
          Colors.orange,
        );
        return;
      }

      _msg('Order status updated to $newStatus', Colors.green);
    } catch (e) {
      _msg('Failed to update status: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _processingOrderIds.remove(orderId));
      }
    }
  }

  // ATOMIC ORDER CANCELLATION & WALLET REFUND
  Future<void> _confirmAndCancelOrder(
    String orderId,
    String userId,
    double refundAmount,
  ) async {
    if (_processingOrderIds.contains(orderId)) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Cancel Order & Refund?',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: Text(
          'Are you sure you want to cancel this order? ৳${refundAmount.toStringAsFixed(2)} will be atomically refunded to the student\'s wallet.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Yes, Cancel & Refund',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _processingOrderIds.add(orderId));

    try {
      // Execute PostgreSQL Atomic Transaction via RPC
      await _supabase.rpc(
        'cancel_and_refund',
        params: {
          'p_order_id': orderId,
          'p_user_id': userId,
          'p_refund_amount': refundAmount,
        },
      );

      _msg('Order cancelled and refunded successfully.', Colors.redAccent);
    } catch (e) {
      _msg('Failed to cancel order: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _processingOrderIds.remove(orderId));
      }
    }
  }

  // BUILD ORDER CARD WIDGET
  Widget _buildOrderCard(Map<String, dynamic> order) {
    final String status = order['status'] ?? 'Pending';
    final String itemsSummary = order['items_summary'] ?? 'Order Details';
    final String orderId = order['id']?.toString() ?? '';
    final String shortId = orderId.length >= 8
        ? orderId.substring(0, 8)
        : orderId;
    final String userId = order['user_id']?.toString() ?? '';
    final double totalAmount =
        double.tryParse(order['total_amount'].toString()) ?? 0.0;

    final bool isLocked = _processingOrderIds.contains(orderId);

    Color statusColor = Colors.orange;
    if (status == 'Preparing') statusColor = Colors.blue;
    if (status == 'Ready') statusColor = Colors.green;
    if (status == 'Completed') statusColor = Colors.grey;
    if (status == 'Cancelled') statusColor = Colors.redAccent;

    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Order ID: #$shortId',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
                Chip(
                  label: Text(
                    status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  backgroundColor: statusColor,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Items: $itemsSummary',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'Total Amount: ৳${totalAmount.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // --- STATE-DRIVEN ACTION BUTTONS ---
            if (status != 'Completed' && status != 'Cancelled')
              isLocked
                  ? const Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.amber,
                        ),
                      ),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                          ),
                          onPressed: () => _confirmAndCancelOrder(
                            orderId,
                            userId,
                            totalAmount,
                          ),
                          child: const Text('Cancel & Refund'),
                        ),
                        if (status == 'Pending')
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue,
                              side: const BorderSide(color: Colors.blue),
                            ),
                            onPressed: () => _updateOrderStatus(
                              orderId,
                              'Pending',
                              'Preparing',
                            ),
                            child: const Text('Start Preparing'),
                          ),
                        if (status == 'Preparing')
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _updateOrderStatus(
                              orderId,
                              'Preparing',
                              'Ready',
                            ),
                            child: const Text('Mark Ready'),
                          ),
                      ],
                    ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            'Live Kitchen Orders',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.redAccent),
              tooltip: 'Logout',
              onPressed: _logout,
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.amber,
            labelColor: Colors.amber,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(icon: Icon(Icons.soup_kitchen), text: 'Active Queue (FIFO)'),
              Tab(icon: Icon(Icons.history), text: 'Completed / Cancelled'),
            ],
          ),
        ),
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _supabase
              .from('orders')
              .stream(primaryKey: ['id'])
              .order('created_at', ascending: false),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.amber),
              );
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Error loading orders: ${snapshot.error}',
                  style: const TextStyle(color: Colors.redAccent),
                ),
              );
            }

            final allOrders = snapshot.data ?? [];

            // Active Queue: Pending, Preparing, Ready (Reversed to FIFO so oldest order is served first)
            final activeOrders = allOrders
                .where(
                  (o) =>
                      o['status'] != 'Completed' && o['status'] != 'Cancelled',
                )
                .toList()
                .reversed
                .toList();

            // History Queue: Completed & Cancelled (Kept LIFO so recent history is at the top)
            final historyOrders = allOrders
                .where(
                  (o) =>
                      o['status'] == 'Completed' || o['status'] == 'Cancelled',
                )
                .toList();

            return TabBarView(
              children: [
                // TAB 1: ACTIVE FIFO QUEUE
                activeOrders.isEmpty
                    ? const Center(
                        child: Text(
                          'No active orders in kitchen queue.',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: activeOrders.length,
                        itemBuilder: (ctx, i) =>
                            _buildOrderCard(activeOrders[i]),
                      ),

                // TAB 2: COMPLETED / CANCELLED HISTORY
                historyOrders.isEmpty
                    ? const Center(
                        child: Text(
                          'No completed or cancelled orders yet.',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: historyOrders.length,
                        itemBuilder: (ctx, i) =>
                            _buildOrderCard(historyOrders[i]),
                      ),
              ],
            );
          },
        ),
      ),
    );
  }
}
