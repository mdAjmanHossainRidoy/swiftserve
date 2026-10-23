import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_router.dart';

// Alias to maintain backward compatibility with app_router.dart
typedef KitchenCounterscannerPage = CounterScannerPage;

class CounterScannerPage extends StatefulWidget {
  const CounterScannerPage({super.key});

  @override
  State<CounterScannerPage> createState() => _CounterScannerPageState();
}

class _CounterScannerPageState extends State<CounterScannerPage> {
  final _supabase = Supabase.instance.client;
  bool _isProcessing = false;

  // Persistent list of recent handovers
  final List<Map<String, dynamic>> _handoverHistory = [];

  // Strict Regex: Matches standard 36-char UUID + ':' + numeric timeBlock
  static final RegExp _qrPayloadRegex = RegExp(
    r'^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}):(\d+)$',
  );

  @override
  void initState() {
    super.initState();
    _loadRecentHandovers();
  }

  // Hydrate recent handovers from database so history survives app restarts
  Future<void> _loadRecentHandovers() async {
    try {
      final List<Map<String, dynamic>> completedOrders = await _supabase
          .from('orders')
          .select()
          .eq('status', 'Completed')
          .order('created_at', ascending: false)
          .limit(20);

      if (mounted) {
        setState(() {
          _handoverHistory
            ..clear()
            ..addAll(completedOrders);
        });
      }
    } catch (_) {
      // Silently ignore initial history fetch errors to keep scanner ready
    }
  }

  void _msg(String text, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  //  1. VALIDATE & PROCESS SCANNED QR TOKEN
  Future<void> _processScannedOrder(String rawToken) async {
    final token = rawToken.trim();
    if (token.isEmpty || _isProcessing) return;

    // Pre-flight Regex Sanitization (Prevents URLs like https:// from crashing UUID query)
    final match = _qrPayloadRegex.firstMatch(token);
    if (match == null) {
      _msg(
        'Invalid SwiftServe QR Code! Unrecognized format.',
        Colors.redAccent,
      );
      return;
    }

    final String orderId = match.group(1)!;
    final int tokenTimeBlock = int.tryParse(match.group(2)!) ?? 0;

    // 30-Second Dynamic Time-Block Verification
    final int currentBlock = DateTime.now().millisecondsSinceEpoch ~/ 30000;
    if ((currentBlock - tokenTimeBlock).abs() > 1) {
      _msg(
        'QR Code Expired! Please ask the student to show the refreshed QR.',
        Colors.redAccent,
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final order = await _supabase
          .from('orders')
          .select()
          .eq('id', orderId)
          .maybeSingle();

      if (order == null) {
        _msg('Order not found in database.', Colors.red);
        return;
      }

      final String status = order['status'] ?? 'Pending';
      if (status == 'Completed') {
        _msg('Alert: This order has already been delivered!', Colors.redAccent);
      } else if (status == 'Cancelled') {
        _msg('Alert: This order was cancelled and refunded.', Colors.redAccent);
      } else if (status != 'Ready') {
        _msg(
          'Hold on: Food is still "$status". Not ready for pickup yet!',
          Colors.orange,
        );
      } else {
        await _showHandoverConfirmationDialog(order);
      }
    } catch (e) {
      _msg('Failed to verify order: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  // 2. DISPLAY ORDER DETAILS BEFORE HANDOVER
  Future<void> _showHandoverConfirmationDialog(
    Map<String, dynamic> order,
  ) async {
    final String items = order['items_summary'] ?? 'Unknown Items';
    final double amount =
        double.tryParse(order['total_amount'].toString()) ?? 0.0;
    final String orderId = order['id'].toString();
    final String shortId = orderId.length >= 8
        ? orderId.substring(0, 8)
        : orderId;

    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.verified_user, color: Colors.green),
            SizedBox(width: 8),
            Text(
              'Confirm Handover',
              style: TextStyle(color: Colors.green, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order ID: #$shortId',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const Divider(color: Colors.grey, height: 20),
            const Text(
              'Items to Deliver:',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              items,
              style: const TextStyle(
                color: Colors.amber,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Total Paid: ৳${amount.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Confirm & Handover',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _markOrderAsCompleted(order);
    }
  }

  // 3. ATOMIC COMPARE-AND-SWAP (CAS) COMPLETION
  Future<void> _markOrderAsCompleted(Map<String, dynamic> order) async {
    try {
      // Enforce status == 'Ready' inside the UPDATE query to prevent TOCTOU race conditions
      final List<Map<String, dynamic>> updatedRows = await _supabase
          .from('orders')
          .update({'status': 'Completed'})
          .eq('id', order['id'])
          .eq('status', 'Ready')
          .select();

      if (updatedRows.isEmpty) {
        _msg(
          'Handover aborted! Order status was modified or already delivered by another counter.',
          Colors.redAccent,
        );
        return;
      }

      setState(() {
        _handoverHistory.removeWhere((item) => item['id'] == order['id']);
        _handoverHistory.insert(0, updatedRows.first);
      });

      _msg('Handover Successful! Order marked as Completed.', Colors.green);
    } catch (e) {
      _msg('Failed to complete handover: $e', Colors.red);
    }
  }

  // 4. PUSH HARDWARE CAMERA ROUTE
  Future<void> _openCameraScanner() async {
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const MobileScannerCameraView()),
    );

    if (scannedCode != null && scannedCode.isNotEmpty) {
      await _processScannedOrder(scannedCode);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text(
          'Counter QR Scanner',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.amber),
            tooltip: 'Refresh History',
            onPressed: _loadRecentHandovers,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Logout',
            onPressed: () async {
              await _supabase.auth.signOut();
              if (!mounted) return;
              Navigator.pushReplacementNamed(context, AppRoutes.auth);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // UPPER SECTION: ON-DEMAND CAMERA TRIGGER
          Expanded(
            flex: 1,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.qr_code_scanner,
                    color: Colors.amber,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  if (_isProcessing)
                    const CircularProgressIndicator(color: Colors.amber)
                  else
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _openCameraScanner,
                      icon: const Icon(Icons.camera_alt, size: 24),
                      label: const Text(
                        'Click Here to Open Camera',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // LOWER SECTION: PERSISTENT HANDOVER HISTORY
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recent Handovers',
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _handoverHistory.isEmpty
                        ? const Center(
                            child: Text(
                              'No handovers recorded yet.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _handoverHistory.length,
                            itemBuilder: (context, index) {
                              final historyItem = _handoverHistory[index];
                              final String rawId =
                                  historyItem['id']?.toString() ?? '';
                              final String shortId = rawId.length >= 8
                                  ? rawId.substring(0, 8)
                                  : rawId;

                              return Card(
                                color: const Color(0xFF2A2A2A),
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  leading: const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                  ),
                                  title: Text(
                                    historyItem['items_summary'] ?? '',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Order ID: #$shortId',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: Text(
                                    '৳${historyItem['total_amount']}',
                                    style: const TextStyle(
                                      color: Colors.amber,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- DEDICATED HARDWARE CAMERA VIEW WITH CONTROLLER LIFECYCLE ---
class MobileScannerCameraView extends StatefulWidget {
  const MobileScannerCameraView({super.key});

  @override
  State<MobileScannerCameraView> createState() =>
      _MobileScannerCameraViewState();
}

class _MobileScannerCameraViewState extends State<MobileScannerCameraView> {
  final MobileScannerController _cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _isScanned = false;

  @override
  void dispose() {
    _cameraController.dispose(); // Explicitly release native camera hardware
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Scan Student QR',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.amber),
            tooltip: 'Toggle Flash',
            onPressed: () => _cameraController.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch, color: Colors.white),
            tooltip: 'Switch Camera',
            onPressed: () => _cameraController.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _cameraController,
            onDetect: (capture) {
              if (_isScanned) return;
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                setState(() => _isScanned = true);
                Navigator.pop(context, barcodes.first.rawValue);
              }
            },
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.amber, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Text(
              'Align the dynamic QR code within the frame',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                backgroundColor: Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
