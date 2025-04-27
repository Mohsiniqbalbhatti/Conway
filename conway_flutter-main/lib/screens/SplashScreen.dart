import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import '../helpers/database_helper.dart';


class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  // Color scheme matching login screen
  final Color _primaryTeal = const Color(0xFF19BFB7);
  final Color _secondaryGreen = const Color(0xFF59A52C);
  final Color _lightBackground = const Color(0xFFE0F7FA);

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _opacityAnimation = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0, 0.5, curve: Curves.easeOut),)
        );

        _controller.forward().whenComplete(() {
      Navigator.pushReplacementNamed(context, '/auth');
    });
  }

  Future<void> _checkAuthStatus() async {
    await DBHelper().getUser();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _lightBackground,
                  _lightBackground.withAlpha(230),
                  Colors.white.withAlpha(204),
                ],
                stops: const [0, 0.5, 1],
              ),
            ),
            child: Stack(
              children: [
                // Animated chat bubble pattern
                ..._buildAnimatedBubbles(),

                // Main content
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Typing animation with gradient text
                      FadeTransition(
                        opacity: _opacityAnimation,
                        child: AnimatedTextKit(
                          isRepeatingAnimation: false,
                          totalRepeatCount: 1,
                          animatedTexts: [
                            TyperAnimatedText(
                              'Conway',
                              textStyle: TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Poppins',
                                foreground: Paint()
                                  ..shader = LinearGradient(
                                    colors: [_primaryTeal, _secondaryGreen],
                                    stops: const [0.3, 0.7],
                                  ).createShader(const Rect.fromLTWH(0, 0, 200, 70)),
                                shadows: [
                                  BoxShadow(
                                    color: _primaryTeal.withAlpha(51),
                                    blurRadius: 20,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              speed: const Duration(milliseconds: 150),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Pulsing dot
                      ScaleTransition(
                        scale: Tween(begin: 0.8, end: 1.2).animate(
                          CurvedAnimation(
                            parent: _controller,
                            curve: const Interval(0.5, 1, curve: Curves.easeInOut),
                          ),
                        ),
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _primaryTeal,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _primaryTeal.withAlpha(128),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
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
      ),
    );
  }

  List<Widget> _buildAnimatedBubbles() {
    return List.generate(5, (index) {
      final size = 60.0 + (index * 20.0);
      final left = 30.0 + (index * 40.0);
      final top = 100.0 + (index * 60.0);
      final delay = index * 0.15;

      return Positioned(
        left: left,
        top: top,
        child: FadeTransition(
          opacity: Tween(begin: 0.0, end: 0.08).animate(
            CurvedAnimation(
              parent: _controller,
              curve: Interval(delay, 1, curve: Curves.easeIn),
            ),
          ),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: _primaryTeal,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    });
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text('Home Screen')),
    );
  }
}