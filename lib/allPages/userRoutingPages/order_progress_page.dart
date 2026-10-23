import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrderProgressPage extends StatefulWidget {
  const OrderProgressPage({super.key});

  @override
  State<OrderProgressPage> createState() => _OrderProgressPageState();
}

class _OrderProgressPageState extends State<OrderProgressPage> {
  final _supabase = Supabase.instance.client;

  void _showDynamicQrDialog(String orderId) {
    showDialog(
      context: context,
      builder: (ctx) => _DynamicQrDialog(orderId: orderId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(
          child: Text(
            'Please log in to view orders.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'My Order Progress',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase
            .from('orders')
            .stream(primaryKey: ['id'])
            .eq('user_id', user.id)
            .order('created_at', ascending: false),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.amber),
            );
          }

          final orders = snapshot.data ?? [];
          if (orders.isEmpty) {
            return const Center(
              child: Text(
                'No active orders found.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final String status = order['status'] ?? 'Pending';
              final String orderId = order['id'];
              final String itemsSummary =
                  order['items_summary'] ?? 'Order Items';

              Color statusColor = Colors.orange;
              if (status == 'Preparing') statusColor = Colors.blue;
              if (status == 'Ready') statusColor = Colors.green;
              if (status == 'Completed') statusColor = Colors.grey;
              if (status == 'Cancelled') statusColor = Colors.redAccent;

              return Card(
                color: const Color(0xFF1E1E1E),
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Order #${orderId.substring(0, 8)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                          Chip(
                            label: Text(
                              status,
                              style: const TextStyle(color: Colors.white),
                            ),
                            backgroundColor: statusColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Items: $itemsSummary',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Amount: ৳${order['total_amount']}',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // STRICT STATE-DRIVEN UI RENDERING
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              status == 'Ready'
                                  ? 'Ready for pickup! Show QR at counter.'
                                  : (status == 'Completed' ||
                                        status == 'Cancelled')
                                  ? 'Order is $status.'
                                  : 'Food is $status. QR code will appear when ready.',
                              style: TextStyle(
                                color: status == 'Ready'
                                    ? Colors.greenAccent
                                    : (status == 'Completed' ||
                                          status == 'Cancelled')
                                    ? Colors.grey
                                    : Colors.amber,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          // Only render the QR button if the state is exactly 'Ready'
                          if (status == 'Ready')
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: Colors.black,
                              ),
                              onPressed: () => _showDynamicQrDialog(orderId),
                              icon: const Icon(Icons.qr_code_2, size: 18),
                              label: const Text('Show QR'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// --- Dynamic 30-Second Regenerating QR Code Dialog ---
class _DynamicQrDialog extends StatefulWidget {
  final String orderId;
  const _DynamicQrDialog({required this.orderId});

  @override
  State<_DynamicQrDialog> createState() => _DynamicQrDialogState();
}

class _DynamicQrDialogState extends State<_DynamicQrDialog> {
  Timer? _timer;
  int _secondsRemaining = 30;
  String _qrPayload = '';

  @override
  void initState() {
    super.initState();
    _generatePayload();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final remaining = 30 - (nowSeconds % 30);

      setState(() {
        _secondsRemaining = remaining;
        if (_secondsRemaining == 30 || _qrPayload.isEmpty) {
          _generatePayload();
        }
      });
    });
  }

  void _generatePayload() {
    final timeBlock = DateTime.now().millisecondsSinceEpoch ~/ 30000;
    _qrPayload = '${widget.orderId}:$timeBlock';
  }

  @override
  void dispose() {
    _timer?.cancel(); // Critical to prevent memory leaks
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Center(
        child: Text(
          'Scan at Delivery Counter',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 220,
              height: 220,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _qrPayload.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.black),
                    )
                  : Center(
                      child: QrImageView(
                        data: _qrPayload,
                        version: QrVersions.auto,
                        size: 200.0,
                        gapless: true,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer_outlined, color: Colors.amber, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Regenerating in $_secondsRemaining seconds',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Dynamic token changes every 30s to prevent fraud',
              style: TextStyle(color: Colors.grey, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close', style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }
}
