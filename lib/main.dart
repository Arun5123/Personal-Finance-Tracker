import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/sheet.dart';
import 'screens/create_sheet_screen.dart';
import 'screens/data_entry_screen.dart';
import 'screens/data_view_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/google_auth_service.dart';
import 'services/google_sheets_service.dart';
import 'services/local_storage_service.dart';
import 'state/app_state.dart';
import 'widgets/app_animations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services.
  final authService = GoogleAuthService();
  final sheetsService = GoogleSheetsService(authService);
  final storageService = LocalStorageService();

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(
        authService: authService,
        sheetsService: sheetsService,
        storageService: storageService,
      ),
      child: const PersonalFinanceTrackerApp(),
    ),
  );
}

class PersonalFinanceTrackerApp extends StatelessWidget {
  const PersonalFinanceTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Personal Finance Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return FadeSlideRoute(page: const _SplashScreen());
          case '/login':
            return FadeSlideRoute(page: const LoginScreen());
          case '/home':
            return FadeSlideRoute(page: const HomeScreen());
          case '/create-sheet':
            return FadeSlideRoute(page: const CreateSheetScreen());
          case '/add-entry':
            final args = settings.arguments;
            if (args is Sheet) {
              // Imported sheets are read-only: view their data instead
              // of opening the entry form.
              if (args.isImported) {
                return FadeSlideRoute(
                  page: DataViewScreen.sheet(sheet: args),
                );
              }
              return FadeSlideRoute(
                page: DataEntryScreen.sheet(sheet: args),
              );
            }
            return FadeSlideRoute(page: const HomeScreen());
          case '/view-data':
            final args = settings.arguments;
            if (args is Sheet) {
              return FadeSlideRoute(
                page: DataViewScreen.sheet(sheet: args),
              );
            }
            return FadeSlideRoute(page: const HomeScreen());
          default:
            return FadeSlideRoute(page: const _SplashScreen());
        }
      },
    );
  }
}

/// Splash screen that checks for an existing sign-in session.
class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _scale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final appState = context.read<AppState>();
    await appState.initialize();

    if (!mounted) return;

    if (appState.isAuthenticated) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.25),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/app_logo.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.white,
                        child: const Icon(
                          Icons.account_balance_wallet,
                          size: 80,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'SheetFin',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const Text(
              'Personal Finance Tracker',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            const CircularProgressIndicator(color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}