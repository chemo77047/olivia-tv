import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';
import 'guide_screen.dart';

const teal = Color(0xFF14B8A6);
const tealDark = Color(0xFF0F766E);
const bg = Color(0xFF071A1E);
const panel = Color(0xFF0D2A30);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const OliviaTV());
}

class OliviaTV extends StatelessWidget {
  const OliviaTV({super.key});

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      child: MaterialApp(
        title: 'Olivia TV',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: bg,
          colorScheme: ColorScheme.fromSeed(seedColor: teal, brightness: Brightness.dark, primary: teal),
          useMaterial3: true,
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await Future.wait([Store.i.load(), Future.delayed(const Duration(milliseconds: 2200))]);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const GuideScreen(resumeLast: true),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B3B3F), bg, Color(0xFF0B3B3F)],
          ),
        ),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: 1),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOutBack,
            builder: (_, s, child) => Transform.scale(scale: s, child: child),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/logo.png', width: 140, height: 140),
                const SizedBox(height: 18),
                ShaderMask(
                  shaderCallback: (r) => const LinearGradient(colors: [Color(0xFF5EEAD4), teal, Color(0xFF99F6E4)])
                      .createShader(r),
                  child: const Text(
                    'Olivia TV',
                    style: TextStyle(fontSize: 64, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1.5),
                  ),
                ),
                const SizedBox(height: 26),
                const SizedBox(
                  width: 180,
                  child: LinearProgressIndicator(color: teal, backgroundColor: panel, minHeight: 4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
