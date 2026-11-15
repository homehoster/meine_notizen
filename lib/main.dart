import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'screens/note_screen.dart';
import 'state/app_state.dart';

final navKey = GlobalKey<NavigatorState>();

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

class _NotizAppState extends State<NotizApp> {
  @override
  void initState() {
    super.initState();
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_open);
    HomeWidget.widgetClicked.listen(_open);
  }

  void _open(Uri? uri) {
    if (uri == null || uri.host != 'note' || uri.pathSegments.isEmpty) return;
    final n = context.read<AppState>().byId(uri.pathSegments.first);
    if (n == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navKey.currentState?.push(MaterialPageRoute(builder: (_) => NoteScreen(note: n)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return MaterialApp(
      navigatorKey: navKey,
      title: 'Notizen',
      themeMode: s.themeMode,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: Colors.teal, brightness: Brightness.dark, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
