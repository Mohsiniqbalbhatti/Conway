import 'package:flutter/material.dart';
import 'package:conway/models/user.dart' as conway_user;
import 'package:conway/screens/guest/login_screen.dart';
import 'package:conway/screens/user/Home_screen.dart';

class AuthWrapper extends StatelessWidget {
  final bool isAuthenticated;
  final conway_user.User? user;
  final void Function(conway_user.User) onLogin;
  final VoidCallback? onLogout;

  const AuthWrapper({
    super.key,
    required this.isAuthenticated,
    required this.user,
    required this.onLogin,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    if (isAuthenticated && user != null) {
      return HomeScreen(onLogout: onLogout);
    } else {
      return LoginScreen(onLogin: onLogin);
    }
  }
} 