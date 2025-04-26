import 'package:conway/screens/SplashScreen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'helpers/database_helper.dart';
import 'models/user.dart' as conway_user;
import 'helpers/auth_wrapper.dart';
import 'screens/user/Home_screen.dart' as user_screens;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool isAuthenticated = false;
  conway_user.User? user;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final dbUser = await DBHelper().getUser();
    if (dbUser != null) {
      setState(() {
        isAuthenticated = true;
        user = dbUser;
      });
    }
  }

  void _onLogin(conway_user.User loggedInUser) {
    setState(() {
      isAuthenticated = true;
      user = loggedInUser;
    });
  }

  void _onLogout() {
    setState(() {
      isAuthenticated = false;
      user = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Conway Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: SplashScreen(),
      routes: {
        '/auth': (context) => AuthWrapper(
              isAuthenticated: isAuthenticated,
              user: user,
              onLogin: _onLogin,
              onLogout: _onLogout,
            ),
        '/home': (context) => isAuthenticated
              ? user_screens.HomeScreen(onLogout: _onLogout)
              : AuthWrapper(
                  isAuthenticated: isAuthenticated,
                  user: user,
                  onLogin: _onLogin,
                  onLogout: _onLogout,
                ),
      },
    );
  }
}