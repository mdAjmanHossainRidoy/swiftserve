import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../allPages/app_router.dart';

class AdminCashInventoryView extends StatefulWidget {
  const AdminCashInventoryView({super.key});

  @override
  State<AdminCashInventoryView> createState() => _AdminCashInventoryViewState();
}

class _AdminCashInventoryViewState extends State<AdminCashInventoryView> {
  final _supabase = Supabase.instance.client;
  final _searchCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  Map<String, dynamic>? _foundUser;
  double _userBalance = 0.0;
  bool _isSearching = false;
  bool _isProcessingWallet = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
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

  // AUTHENTICATION LOGOUT
  Future<void> _logout() async {
    await _supabase.auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, AppRoutes.auth);
  }

  //1. SERVER-SIDE USER SEARCH
  Future<void> _searchUser() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _foundUser = null;
    });

    try {
      // Server-side case-insensitive search on username or email
      final List<Map<String, dynamic>> list = await _supabase
          .from('profiles')
          .select()
          .or('username.ilike.%$query%,email.ilike.%$query%')
          .limit(1);

      _foundUser = list.isNotEmpty ? list.first : null;

      if (_foundUser == null) {
        _msg('No user found with that username or email!', Colors.redAccent);
      } else {
        await _refreshSelectedUserBalance();
      }
    } catch (e) {
      _msg('Search error: $e', Colors.redAccent);
    }
    if (mounted) {
      setState(() => _isSearching = false);
    }
  }

  // Helper to fetch the freshest wallet balance from Supabase
  Future<double> _refreshSelectedUserBalance() async {
    if (_foundUser == null) return 0.0;
    final walletsList = await _supabase
        .from('wallets')
        .select('balance')
        .eq('user_id', _foundUser!['id']);

    final latestBalance = walletsList.isNotEmpty
        ? (walletsList[0]['balance'] as num?)?.toDouble() ?? 0.0
        : 0.0;

    if (mounted) {
      setState(() => _userBalance = latestBalance);
    }
    return latestBalance;
  }

  // 2a. CREDIT USER WALLET (TOP-UP)
  Future<void> _creditWallet() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (_foundUser == null || amount == null || amount <= 0) {
      _msg('Please enter a valid positive amount.', Colors.orange);
      return;
    }

    setState(() => _isProcessingWallet = true);
    try {
      // Fetch latest balance first to prevent Lost Update race conditions
      final latestBalance = await _refreshSelectedUserBalance();
      final newBal = latestBalance + amount;

      await _supabase.from('wallets').upsert({
        'user_id': _foundUser!['id'],
        'balance': newBal,
      }, onConflict: 'user_id');

      setState(() {
        _userBalance = newBal;
        _amountCtrl.clear();
      });
      _msg(
        'Successfully credited ৳${amount.toStringAsFixed(2)} to @${_foundUser!['username']}',
        Colors.green,
      );
    } catch (e) {
      _msg('Failed to credit: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isProcessingWallet = false);
    }
  }

  // 2b. DEDUCT / REFUND USER WALLET
  Future<void> _deductWallet() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (_foundUser == null || amount == null || amount <= 0) {
      _msg('Please enter a valid positive amount.', Colors.orange);
      return;
    }

    setState(() => _isProcessingWallet = true);
    try {
      // Fetch latest balance from server before validating deduction
      final latestBalance = await _refreshSelectedUserBalance();

      if (amount > latestBalance) {
        _msg(
          'Error: Cannot deduct ৳$amount. Latest balance is only ৳${latestBalance.toStringAsFixed(2)}!',
          Colors.redAccent,
        );
        return;
      }

      final newBal = latestBalance - amount;
      await _supabase.from('wallets').upsert({
        'user_id': _foundUser!['id'],
        'balance': newBal,
      }, onConflict: 'user_id');

      setState(() {
        _userBalance = newBal;
        _amountCtrl.clear();
      });
      _msg(
        'Successfully refunded ৳${amount.toStringAsFixed(2)} cash to @${_foundUser!['username']}',
        Colors.green,
      );
    } catch (e) {
      _msg('Failed to deduct: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isProcessingWallet = false);
    }
  }

  // 3. SECURE ITEM DELETION WITH STORAGE CLEANUP
  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Delete Food Item?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to permanently delete "${item['name']}" from the menu?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _supabase.from('menu_items').delete().eq('id', item['id']);

      // Clean up associated image from Supabase Storage to prevent orphaned files
      final String? imageUrl = item['image_url']?.toString();
      if (imageUrl != null && imageUrl.contains('/menu_images/')) {
        final fileName = imageUrl.split('/menu_images/').last;
        await _supabase.storage.from('menu_images').remove([fileName]);
      }

      _msg('${item['name']} deleted successfully.', Colors.green);
    } catch (e) {
      _msg(
        'Failed to delete item. It might be linked to an active order. Error: $e',
        Colors.redAccent,
      );
    }
  }

  // 4. ADD OR EDIT FOOD ITEM DIALOG
  void _openItemDialog({Map<String, dynamic>? existingItem}) {
    final nameCtrl = TextEditingController(text: existingItem?['name'] ?? '');
    final priceCtrl = TextEditingController(
      text: existingItem?['price']?.toString() ?? '',
    );
    final stockCtrl = TextEditingController(
      text: existingItem?['stock']?.toString() ?? '10',
    );
    String category = existingItem?['category'] ?? 'Meals';
    String imageUrl = existingItem?['image_url'] ?? '';
    Uint8List? previewBytes;
    bool uploading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> pickPhoto(ImageSource source) async {
            final file = await ImagePicker().pickImage(
              source: source,
              imageQuality: 80,
            );
            if (file == null) return;

            setDialogState(() => uploading = true);
            try {
              final bytes = await file.readAsBytes();
              final fileName =
                  'food_${DateTime.now().millisecondsSinceEpoch}.jpg';
              await _supabase.storage
                  .from('menu_images')
                  .uploadBinary(fileName, bytes);
              imageUrl = _supabase.storage
                  .from('menu_images')
                  .getPublicUrl(fileName);
              previewBytes = bytes;
            } catch (e) {
              _msg('Upload error: $e', Colors.redAccent);
            }
            setDialogState(() => uploading = false);
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: Text(
              existingItem == null ? 'Add Food Item' : 'Edit / Replace Item',
              style: const TextStyle(color: Colors.white),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _inputField(nameCtrl, 'Food Name (e.g., Burger)'),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    dropdownColor: const Color(0xFF2C2C2C),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      filled: true,
                      fillColor: Color(0xFF2C2C2C),
                    ),
                    items: ['Meals', 'Fast Food', 'Drinks', 'Snacks']
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => category = v!),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _inputField(priceCtrl, 'Price (৳)', isNum: true),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _inputField(
                          stockCtrl,
                          'Quantity (Stock)',
                          isNum: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (uploading)
                    const CircularProgressIndicator(color: Colors.amber)
                  else if (previewBytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        previewBytes!,
                        height: 90,
                        fit: BoxFit.cover,
                      ),
                    )
                  else if (imageUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        imageUrl,
                        height: 90,
                        fit: BoxFit.cover,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pickPhoto(ImageSource.gallery),
                          icon: const Icon(
                            Icons.photo,
                            size: 16,
                            color: Colors.amber,
                          ),
                          label: const Text(
                            'Gallery',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pickPhoto(ImageSource.camera),
                          icon: const Icon(
                            Icons.camera_alt,
                            size: 16,
                            color: Colors.amber,
                          ),
                          label: const Text(
                            'Camera',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                ),
                onPressed: uploading
                    ? null
                    : () async {
                        final String foodName = nameCtrl.text.trim();
                        final double? price = double.tryParse(
                          priceCtrl.text.trim(),
                        );
                        final int? stock = int.tryParse(stockCtrl.text.trim());

                        if (foodName.isEmpty) {
                          _msg('Food name cannot be empty!', Colors.redAccent);
                          return;
                        }
                        if (price == null ||
                            price <= 0 ||
                            stock == null ||
                            stock < 0) {
                          _msg(
                            'Enter a valid positive price and non-negative stock!',
                            Colors.redAccent,
                          );
                          return;
                        }

                        final data = {
                          'name': foodName,
                          'category': category,
                          'price': price,
                          'stock': stock,
                          'is_available': stock > 0,
                          'image_url': imageUrl.isEmpty ? null : imageUrl,
                        };

                        try {
                          if (existingItem == null) {
                            await _supabase.from('menu_items').insert(data);
                          } else {
                            await _supabase
                                .from('menu_items')
                                .update(data)
                                .eq('id', existingItem['id']);
                          }
                          if (mounted) Navigator.pop(ctx);
                        } catch (e) {
                          _msg('Save failed: $e', Colors.redAccent);
                        }
                      },
                child: const Text(
                  'Save Item',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Admin Cash & Inventory',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // --- PANEL 1: USER WALLET TOP-UP & REFUND ---
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '1. CASHIER: MANAGE WALLET BY USERNAME',
                    style: TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _inputField(
                          _searchCtrl,
                          'Enter Username or Email',
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: _isSearching ? null : _searchUser,
                        child: const Text('Search'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_foundUser != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2C),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '@${_foundUser!['username']}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _foundUser!['email'],
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '৳ ${_userBalance.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // DUAL TRANSACTION ROW
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _inputField(
                            _amountCtrl,
                            'Amount (৳)',
                            isNum: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: _isProcessingWallet
                                ? null
                                : _creditWallet,
                            child: const Text(
                              'Add Cash',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: const BorderSide(color: Colors.redAccent),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: _isProcessingWallet
                                ? null
                                : _deductWallet,
                            child: const Text(
                              'Refund',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // PANEL 2: INVENTORY MANAGEMENT
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '2. INVENTORY MANAGEMENT',
                        style: TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () => _openItemDialog(),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Food'),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.grey, height: 24),

                  // REAL-TIME INVENTORY STREAM
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _supabase
                        .from('menu_items')
                        .stream(primaryKey: ['id']),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Text(
                          'Error: ${snapshot.error}',
                          style: const TextStyle(color: Colors.red),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.amber),
                        );
                      }

                      final items = snapshot.data!;
                      if (items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'No food inventory found. Click "Add Food".',
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }

                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            const Divider(color: Colors.black26),
                        itemBuilder: (ctx, i) {
                          final item = items[i];
                          final hasImg =
                              item['image_url'] != null &&
                              item['image_url'].toString().isNotEmpty;

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: hasImg
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(
                                      item['image_url'],
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.broken_image,
                                        color: Colors.grey,
                                        size: 36,
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    Icons.fastfood,
                                    color: Colors.grey,
                                    size: 36,
                                  ),
                            title: Text(
                              item['name'] ?? '',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '৳${item['price']}  •  Qty/Stock: ${item['stock']}',
                              style: const TextStyle(
                                color: Colors.amber,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.amber,
                                    size: 20,
                                  ),
                                  tooltip: 'Edit Item',
                                  onPressed: () =>
                                      _openItemDialog(existingItem: item),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.redAccent,
                                    size: 20,
                                  ),
                                  tooltip: 'Remove Item',
                                  onPressed: () => _deleteItem(item),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputField(
    TextEditingController ctrl,
    String hint, {
    bool isNum = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: isNum ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF2C2C2C),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
