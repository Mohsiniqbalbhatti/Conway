import 'dart:convert';
import 'dart:async';
import 'package:conway/helpers/database_helper.dart';
import 'package:conway/models/user.dart'
as conway_user; // Aliased to avoid conflict
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../constants/api_config.dart';
import 'signup_screen.dart';
import '../../services/socket_service.dart'; // Import SocketService

class LoginScreen extends StatefulWidget {
  final void Function(conway_user.User) onLogin;
  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailOrUsernameController =
  TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final SocketService _socketService = SocketService(); // Get instance

  // Color scheme
  final Color _logoTextColor = const Color(0xFF19BFB7);
  final Color _faviconColor = const Color(0xFF59A52C);
  final Color _primaryColor = const Color(0xFF19BFB7);
  final Color _secondaryColor = const Color(0xFF59A52C);

  Future<void> _login() async {
    setState(() => _isLoading = true);

    final emailOrUsername = _emailOrUsernameController.text.trim();
    final password = _passwordController.text;

    if (emailOrUsername.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter both email/username and password"),
        ),
      );
      setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await http.post(
        Uri.parse(ApiConfig.login),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"identifier": emailOrUsername, "password": password}),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Connection timed out. Server might be unreachable.');
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        final Map<String, dynamic> userJson = body['user'];
        
        final String userIdString = userJson['_id'] as String;
        
        final userFromServer = conway_user.User(
          id: userIdString,
          email: userJson['email'] as String? ?? '',
          profileUrl: userJson['profileUrl'] as String? ?? '',
        );

        await DBHelper().insertUser(userFromServer);

        // *** Connect Socket ***
        print("[LoginScreen] Connecting socket after regular login for user: ${userFromServer.id}");
        _socketService.connect(userFromServer.id);
        // ********************

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Login successful!"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );

        await Future.delayed(const Duration(milliseconds: 1500));

        widget.onLogin(userFromServer);
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        final Map<String, dynamic> errorData = jsonDecode(response.body);
        final String errorMessage = errorData['message'] ?? 'Login failed. Check your credentials.';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } catch (e) {
      print('Login error details: $e');
      
      String errorMessage = "Network error occurred. Please try again.";
      
      if (e.toString().contains('SocketException') || 
          e.toString().contains('Connection refused') ||
          e.toString().contains('Network is unreachable')) {
        errorMessage = 'Cannot connect to server. Check your network connection and server address.';
      } else if (e.toString().contains('timed out')) {
        errorMessage = 'Connection timed out. Server might be unreachable.';
      } else if (e is FormatException) {
        errorMessage = 'Invalid response from server. Please try again.';
      }
      
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage)));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      final User? firebaseUser = userCredential.user;

      if (firebaseUser != null) {
        final response = await http.post(
          Uri.parse(ApiConfig.googleAuth),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "email": firebaseUser.email,
            "fullname": firebaseUser.displayName,
            "photoURL": firebaseUser.photoURL,
            "firebaseUID": firebaseUser.uid
          }),
        ).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException('Connection timed out. Server might be unreachable.');
          },
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          final Map<String, dynamic> responseData = jsonDecode(response.body);
          final Map<String, dynamic> userJson = responseData['user'];
          
          final String userIdString = userJson['_id'] as String;
          
          final user = conway_user.User(
            id: userIdString,
            email: userJson['email'] as String? ?? '',
            profileUrl: userJson['profileUrl'] as String? ?? '',
          );

          await DBHelper().insertUser(user);
          
          // *** Connect Socket ***
          print("[LoginScreen] Connecting socket after Google sign-in for user: ${user.id}");
          _socketService.connect(user.id);
          // ********************
          
          widget.onLogin(user);

          final bool isExistingAccount = responseData['isExistingAccount'] ?? false;
          final String message = isExistingAccount 
              ? "Logged in to your existing account" 
              : "Google login successful!";
              
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
          
          await Future.delayed(const Duration(milliseconds: 1500));

          Navigator.pushReplacementNamed(context, '/home');
        } else {
          throw Exception("Server returned ${response.statusCode}: ${response.body}");
        }
      }
    } catch (e) {
      print('Google sign-in error details: $e');
      
      String errorMessage = "Google sign in failed. Please try again.";
      
      if (e.toString().contains('SocketException') || 
          e.toString().contains('Connection refused') ||
          e.toString().contains('Network is unreachable')) {
        errorMessage = 'Cannot connect to server. Check your network connection and server address.';
      } else if (e.toString().contains('timed out')) {
        errorMessage = 'Connection timed out. Server might be unreachable.';
      } else if (e is FormatException) {
        errorMessage = 'Invalid response from server. Please try again.';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 40.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildAnimatedHeader(),
                const SizedBox(height: 32),
                _buildInputField(
                  controller: _emailOrUsernameController,
                  icon: Icons.alternate_email,
                  hintText: "Email or Username",
                ),
                const SizedBox(height: 16),
                _buildInputField(
                  controller: _passwordController,
                  icon: Icons.lock,
                  hintText: "Password",
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                _buildGradientLoginButton(),
                const SizedBox(height: 24),
                _buildDivider(),
                const SizedBox(height: 24),
                _buildGoogleButton(),
                const SizedBox(height: 24),
                _buildSignUpText(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedHeader() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Image.asset(
          'assets/logo.png',
          height: 80,
          width: 180,
          color: _faviconColor,
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: ShaderMask(
            shaderCallback:
                (bounds) => LinearGradient(
              colors: [_logoTextColor, _secondaryColor],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ).createShader(bounds),
            child: const Text(
              "Welcome Back",
              key: ValueKey('welcome-text'),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.1),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          "Sign in to continue your conversations",
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required IconData icon,
    required String hintText,
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.black87),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: _primaryColor),
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.grey[500]),
        filled: true,
        fillColor: Colors.grey[50],
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _primaryColor, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
      ),
    );
  }

  Widget _buildGradientLoginButton() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_primaryColor, _secondaryColor],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child:
        _isLoading
            ? const SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        )
            : const Text(
          "Login",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey[300], thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            "OR",
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey[300], thickness: 1)),
      ],
    );
  }

  Widget _buildGoogleButton() {
    return OutlinedButton.icon(
      onPressed: _isLoading ? null : _signInWithGoogle,
      icon: Image.asset('assets/google_icon.png', height: 20, width: 20),
      label: const Text(
        "Continue with Google",
        style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w500),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: Colors.grey[300]!),
      ),
    );
  }

  Widget _buildSignUpText() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Don't have an account? ",
          style: TextStyle(color: Colors.grey[600]),
        ),
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SignupScreen(
                  toggleView: () {
                    // When signup is complete, pop back to login screen
                    Navigator.pop(context);
                  },
                ),
              ),
            );
          },
          child: Text(
            "Sign Up",
            style: TextStyle(color: _primaryColor, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}