import 'package:flutter/material.dart';
import 'package:conway/helpers/database_helper.dart';
import 'package:conway/models/user.dart' as conway_user;

class AuthGuard {
  static Future<bool> isAuthenticated(BuildContext context) async {
    final conway_user.User? user = await DBHelper().getUser();
    
    if (user == null) {
      // User is not authenticated, redirect to the login screen
      // ignore: use_build_context_synchronously
      Navigator.of(context).pushReplacementNamed('/auth');
      return false;
    }
    
    return true;
  }
}