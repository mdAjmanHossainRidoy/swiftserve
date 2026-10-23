import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_router.dart';

// Global Cart List shared between Home and Cart screen
List<Map<String, dynamic>> globalCart = [];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabase = Supabase.instance.client;
  String _selectedCategory = 'All';
  double _cachedBalance =
      0.0; // Keeps balance continuous updated rakhbe screen e

  final List<String> _categories = [
    'All',
    'Meals',
    'Fast Food',
    'Drinks',
    'Snacks',
  ];

  @override
  void initState() {
    super.initState();
    _fetchInitialBalance();
  }

  // screen load howar sathe sathe current updated balace fetch hobe db theke:
  Future<void> _fetchInitialBalance() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final data = await _supabase
          .from('wallets')
          .select('balance')
          .eq('user_id', user.id)
          .maybeSingle();
      if (data != null && mounted) {
        setState(() {
          _cachedBalance = (data['balance'] as num?)?.toDouble() ?? 0.0;
        });
      }
    } catch (_) {}
  }

  void _msg(String text, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: color,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // add to cart er stock awareness:
  void _addToCart(Map<String, dynamic> item) {
    final int availableStock = (item['stock'] as num?)?.toInt() ?? 0;

    if (availableStock <= 0) {
      _msg('${item['name']} is out of stock!', Colors.redAccent);
      return;
    }

    final existingIndex = globalCart.indexWhere(
      (element) => element['id'] == item['id'],
    );

    if (existingIndex >= 0) {
      final int currentQty = (globalCart[existingIndex]['qty'] as int?) ?? 1;
      // Prevent adding more items than available in canteen inventory
      if (currentQty >= availableStock) {
        _msg(
          'Maximum stock ($availableStock) reached for ${item['name']}!',
          Colors.orange,
        );
        return;
      }
      setState(() {
        globalCart[existingIndex]['qty'] = currentQty + 1;
      });
    } else {
      setState(() {
        final newItem = Map<String, dynamic>.from(item);
        newItem['qty'] = 1;
        globalCart.add(newItem);
      });
    }

    _msg('Added ${item['name']} to cart!', Colors.green);
  }

  // UPGRADED: SANITIZE SESSION STATE ON LOGOUT
  // logout state e jawar :
  Future<void> _handleLogout() async {
    globalCart.clear(); // Prevent cart data leaking to the next logged-in user
    await _supabase.auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, AppRoutes.auth);
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _supabase.auth.currentUser?.id;
    final totalCartItems = globalCart.fold<int>(
      0,
      (sum, item) => sum + (item['qty'] as int? ?? 1),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'SwiftServe Canteen',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.account_balance_wallet_outlined,
              color: Colors.amber,
            ),
            tooltip: 'My Wallet',
            onPressed: () async {
              await Navigator.pushNamed(context, AppRoutes.wallet);
              _fetchInitialBalance(); // Refresh when returning from wallet
            },
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long_rounded, color: Colors.amber),
            tooltip: 'My Orders',
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.orderTracker),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            tooltip: 'Logout',
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- WALLET LIVE BALANCE HEADER ---
          if (currentUserId != null)
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _supabase
                  .from('wallets')
                  .stream(primaryKey: ['id'])
                  .eq('user_id', currentUserId),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                  _cachedBalance =
                      (snapshot.data!.first['balance'] as num?)?.toDouble() ??
                      _cachedBalance;
                }

                return Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SwiftServe Balance',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Ready to Order',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '৳ ${_cachedBalance.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

          // CATEGORY FILTER TABS
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              itemBuilder: (ctx, index) {
                final cat = _categories[index];
                final active = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: active,
                    selectedColor: Colors.amber,
                    backgroundColor: const Color(0xFF1E1E1E),
                    labelStyle: TextStyle(
                      color: active ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // LIVE MENU ITEMS GRID
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _supabase.from('menu_items').stream(primaryKey: ['id']),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.amber),
                  );
                }

                final allItems = snapshot.data ?? [];
                final filteredItems = allItems.where((item) {
                  final int stock = (item['stock'] as num?)?.toInt() ?? 0;
                  if (item['is_available'] != true || stock <= 0) return false;
                  if (_selectedCategory == 'All') return true;
                  return item['category'] == _selectedCategory;
                }).toList();

                if (filteredItems.isEmpty) {
                  return const Center(
                    child: Text(
                      'No menu items available right now.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: filteredItems.length,
                  itemBuilder: (ctx, index) {
                    final item = filteredItems[index];
                    final int stock = (item['stock'] as num?)?.toInt() ?? 0;
                    final hasImg =
                        item['image_url'] != null &&
                        item['image_url'].toString().isNotEmpty;

                    return Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade800),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12),
                              ),
                              child: hasImg
                                  ? Image.network(
                                      item['image_url'],
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                        color: Colors.grey.shade900,
                                        child: const Center(
                                          child: Icon(
                                            Icons.broken_image,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                    )
                                  : Container(
                                      color: Colors.grey.shade900,
                                      child: const Center(
                                        child: Icon(
                                          Icons.fastfood,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['name'] ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '৳ ${item['price']}',
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      'Left: $stock',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  height: 32,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.amber,
                                      foregroundColor: Colors.black,
                                      padding: EdgeInsets.zero,
                                    ),
                                    onPressed: () => _addToCart(item),
                                    child: const Text(
                                      'Add to Cart',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.amber,
        foregroundColor: Colors.black,
        onPressed: () async {
          await Navigator.pushNamed(context, AppRoutes.cart);
          _fetchInitialBalance();
          setState(() {});
        },
        icon: const Icon(Icons.shopping_cart_outlined),
        label: Text(
          'View Cart ($totalCartItems)',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
