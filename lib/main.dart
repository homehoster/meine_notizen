import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'screens/note_screen.dart';
import 'state/app_state.dart';

final navKey = GlobalKey<NavigatorState>();
const _widgetChannel =
    MethodChannel('com.github.homehoster.meine_notizen/widget');
const _seedColor = Color(0xFF1565C0);
const _secondaryColor = Color(0xFFF59E0B);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HomeWidget.setAppGroupId('group.com.github.homehoster.meine_notizen');
  final state = AppState();
  await state.init();
  runApp(ChangeNotifierProvider.value(value: state, child: const NotizApp()));
}

class NotizApp extends StatefulWidget {
  const NotizApp({super.key});
  @override
  State<NotizApp> createState() => _NotizAppState();
}

class _NotizAppState extends State<NotizApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _widgetChannel.setMethodCallHandler((call) async {
      if (call.method == 'openWidgetUri' && call.arguments is String) {
        _open(Uri.tryParse(call.arguments as String));
      }
    });
    _widgetChannel.invokeMethod<void>('ready');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final state = context.read<AppState>();
    switch (lifecycle) {
      case AppLifecycleState.resumed:
        state.onForeground();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        state.onBackground();
      default:
        break;
    }
  }

  void _open(Uri? uri) {
    if (uri == null ||
        !{'note', 'actions', 'new-note', 'home'}.contains(uri.host)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = navKey.currentState;
      final context = navKey.currentContext;
      if (navigator == null || context == null) return;
      if (uri.host == 'home') return;
      if (uri.host == 'actions') {
        showModalBottomSheet<void>(
          context: context,
          builder: (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('Meine Notizen öffnen'),
                  onTap: () => Navigator.pop(sheetContext),
                ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Neue Notiz'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _createNote(context, navigator);
                  },
                ),
              ],
            ),
          ),
        );
        return;
      }
      if (uri.host == 'new-note') {
        _createNote(context, navigator);
        return;
      }
      if (uri.pathSegments.isEmpty) return;
      final n = context.read<AppState>().byId(uri.pathSegments.first);
      if (n != null) {
        navigator.push(MaterialPageRoute(builder: (_) => NoteScreen(note: n)));
      }
    });
  }

  Future<void> _createNote(
    BuildContext context,
    NavigatorState navigator,
  ) async {
    final note = await context.read<AppState>().create();
    if (context.mounted && navigator.mounted) {
      navigator.push(MaterialPageRoute(builder: (_) => NoteScreen(note: note)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return MaterialApp(
      navigatorKey: navKey,
      title: 'Notizen',
      themeMode: switch (s.themeSelection) {
        AppTheme.system => ThemeMode.system,
        AppTheme.light || AppTheme.paper => ThemeMode.light,
        AppTheme.dark => ThemeMode.dark,
      },
      theme: _buildTheme(
        Brightness.light,
        paper: s.themeSelection == AppTheme.paper,
      ),
      darkTheme: _buildTheme(Brightness.dark),
      home: const HomeScreen(),
    );
  }
}

ThemeData _buildTheme(Brightness brightness, {bool paper = false}) {
  if (paper) {
    const canvas = Color(0xFFF5EDE4);
    const surface = Color(0xFFFBF6F0);
    const ink = Color(0xFF2B2219);
    const primary = Color(0xFF2F251C);
    const edge = Color(0xFFD3C5B4);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: primary,
          onPrimary: surface,
          secondary: const Color(0xFF2863AB),
          surface: surface,
          onSurface: ink,
          surfaceContainerLowest: const Color(0xFFFDF9F4),
          surfaceContainerLow: const Color(0xFFF8F1E9),
          surfaceContainer: canvas,
          surfaceContainerHigh: const Color(0xFFEDE3D7),
          surfaceContainerHighest: const Color(0xFFE7DCCF),
          outline: edge,
          outlineVariant: const Color(0xFFE0D4C5),
          error: const Color(0xFFA83D2B),
          errorContainer: const Color(0xFFF6E1D9),
        );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: surface,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFE0D4C5)),
      textSelectionTheme: const TextSelectionThemeData(
        selectionColor: Color(0x2E2863AB),
        cursorColor: primary,
        selectionHandleColor: primary,
      ),
    );
  }

  final colorScheme = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: brightness,
  ).copyWith(secondary: _secondaryColor);

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      backgroundColor: _seedColor,
      foregroundColor: Colors.white,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _seedColor,
      foregroundColor: Colors.white,
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
