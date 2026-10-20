import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SplashArtwork();
}

class SplashArtwork extends StatelessWidget {
  const SplashArtwork({super.key});

  @override
  Widget build(BuildContext context) =>
      const AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: Color(0xFF003C30),
          body: SizedBox.expand(
            child: Image(
              image: AssetImage('assets/images/branding/splash.webp'),
              fit: BoxFit.fill,
              semanticLabel: 'يمن درايف، رحلتك بين يديك',
            ),
          ),
        ),
      );
}
