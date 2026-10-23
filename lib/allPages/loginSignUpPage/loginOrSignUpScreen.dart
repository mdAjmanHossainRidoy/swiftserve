import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_router.dart';

class AuthView extends StatefulWidget {
  const AuthView({super.key});

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView> {
  final _supabase = Supabase.instance.client;

  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController(); // Used for Login Identifier too
  final _phoneCtrl = TextEditingController();
  final _studentIdCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _hidePass = true;

  @override
  // memory clear korar function:
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _studentIdCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _msg(String text, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  // password forgot korar function.
  void _showForgotPass() {
    final resetCtrl = TextEditingController(
      text: _emailCtrl.text.contains('@') ? _emailCtrl.text : '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Reset Password',
          style: TextStyle(color: Colors.white),
        ),
        content: _box(resetCtrl, 'Enter your email', Icons.email),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              if (resetCtrl.text.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await _supabase.auth.resetPasswordForEmail(
                  resetCtrl.text.trim(),
                );
                _msg('Reset link sent to your email!', Colors.green);
              } catch (e) {
                _msg('Error: $e', Colors.red);
              }
            },
            child: const Text('Send Link'),
          ),
        ],
      ),
    );
  }

  // SUBMIT FUNCTION WITH 4-TIER ROLE-BASED ROUTING
  Future<void> _submit() async {
    String identifier = _emailCtrl.text.trim(); // Can be Email or Username
    String pass = _passCtrl.text.trim();

    if (identifier.isEmpty || pass.length < 6) {
      return _msg('Enter valid credentials & 6+ char password', Colors.red);
    }

    if (!_isLogin) {
      if (_usernameCtrl.text.trim().isEmpty) {
        return _msg('Username is required!', Colors.red);
      }
      if (!identifier.contains('@')) {
        return _msg('A valid Email ID is required for Sign Up!', Colors.red);
      }
      if (pass != _confirmCtrl.text.trim()) {
        return _msg('Passwords do not match!', Colors.red);
      }
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        // login logic user &email
        if (!identifier.contains('@')) {
          final data = await _supabase
              .from('profiles')
              .select('email')
              .eq('username', identifier)
              .maybeSingle();

          if (data == null || data['email'] == null) {
            throw 'Username not found!';
          }
          identifier = data['email']; // resolve username to email
        }
        await _supabase.auth.signInWithPassword(
          email: identifier,
          password: pass,
        );
      } else {
        // signup korar jonne logic
        final username = _usernameCtrl.text.trim();
        final studentId = _studentIdCtrl.text.trim();
        final phone = _phoneCtrl.text.trim();

        // 1. atfirst check that userName exist kore kina:
        final existingUser = await _supabase
            .from('profiles')
            .select('id')
            .eq('username', username)
            .maybeSingle();

        if (existingUser != null) {
          throw 'Username is already taken. Please choose another.';
        }

        // 2. user bananor :
        final res = await _supabase.auth.signUp(
          email: identifier,
          password: pass,
        );

        if (res.user != null) {
          // 3.  details save korbe Profiles table e (Default role: 'student')
          await _supabase.from('profiles').upsert({
            'id': res.user!.id,
            'username': username,
            'full_name': username,
            'email': identifier,
            'student_id': studentId.isEmpty ? null : studentId,
            'phone': phone.isEmpty ? null : phone,
            'role': 'student',
          });

          // 4. and shei fresh user er balance zero thakbe.
          await _supabase.from('wallets').upsert({
            'user_id': res.user!.id,
            'balance': 0.0,
          }, onConflict: 'user_id');
        }
      }

      // tarpor route decide korbe(admin naki, kitchen, counter or student?)//
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final profile = await _supabase
            .from('profiles')
            .select('role')
            .eq('id', user.id)
            .single();

        final String role = profile['role'] ?? 'student';

        if (!mounted) return;

        if (role == 'admin') {
          Navigator.pushReplacementNamed(context, AppRoutes.adminInventory);
        } else if (role == 'kitchen') {
          Navigator.pushReplacementNamed(context, AppRoutes.kitchenOrder);
        } else if (role == 'counter') {
          Navigator.pushReplacementNamed(context, AppRoutes.counterScanner);
        } else {
          Navigator.pushReplacementNamed(context, AppRoutes.home);
        }
      }
    } catch (e) {
      _msg(e.toString().replaceAll('Exception: ', ''), Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.restaurant_rounded,
                  size: 48,
                  color: Colors.amber,
                ),
                const SizedBox(height: 12),
                const Text(
                  'SwiftServe',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),

                // --- TABS ---
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isLogin
                              ? Colors.amber
                              : Colors.grey[800],
                        ),
                        onPressed: () => setState(() => _isLogin = true),
                        child: const Text(
                          'Sign In',
                          style: TextStyle(color: Colors.black),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: !_isLogin
                              ? Colors.amber
                              : Colors.grey[800],
                        ),
                        onPressed: () => setState(() => _isLogin = false),
                        child: const Text(
                          'Sign Up',
                          style: TextStyle(color: Colors.black),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                //signup er specific fields://
                if (!_isLogin) ...[
                  _box(_usernameCtrl, 'Username (Required)', Icons.person),
                  const SizedBox(height: 12),
                ],

                // email and identifier field://
                _box(
                  _emailCtrl,
                  _isLogin ? 'Username or Email' : 'Email Address (Required)',
                  Icons.email,
                ),
                const SizedBox(height: 12),

                // optional field.//
                if (!_isLogin) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _box(
                          _studentIdCtrl,
                          'Student ID (Optional)',
                          Icons.badge,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _box(
                          _phoneCtrl,
                          'Phone (Optional)',
                          Icons.phone,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                //password field://
                _box(_passCtrl, 'Password', Icons.lock, isPass: true),
                if (!_isLogin) ...[
                  const SizedBox(height: 12),
                  _box(
                    _confirmCtrl,
                    'Confirm Password',
                    Icons.lock_reset,
                    isPass: true,
                  ),
                ],
                const SizedBox(height: 16),

                if (_isLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showForgotPass,
                      child: const Text(
                        'Forgot Password?',
                        style: TextStyle(color: Colors.amber),
                      ),
                    ),
                  ),

                const SizedBox(height: 8),

                // sesh er submit button.
                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            _isLogin ? 'Login Now' : 'Sign Up Now',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _box(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    bool isPass = false,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: isPass ? _hidePass : false,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.grey, size: 20),
        suffixIcon: isPass
            ? IconButton(
                icon: Icon(
                  _hidePass ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey,
                  size: 20,
                ),
                onPressed: () => setState(() => _hidePass = !_hidePass),
              )
            : null,
        filled: true,
        fillColor: const Color(0xFF2A2A2A),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
