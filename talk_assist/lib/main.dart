import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'chat_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sherpa_onnx.initBindings();
  await dotenv.load(
    fileName: ".env",
    isOptional: true,
    mergeWith: _dartDefineEnvironment(),
  );
  if (kDebugMode) {
    debugPrint(
      "ENV loaded: OPENROUTER_KEY=${_envPresence("OPENROUTER_KEY")}, "
      "SERPER_KEY=${_envPresence("SERPER_KEY")}",
    );
  }
  runApp(const MainApp());
}

Map<String, String> _dartDefineEnvironment() {
  const openRouterKey = String.fromEnvironment("OPENROUTER_KEY");
  const serperKey = String.fromEnvironment("SERPER_KEY");

  return <String, String>{
    if (openRouterKey.trim().isNotEmpty) "OPENROUTER_KEY": openRouterKey,
    if (serperKey.trim().isNotEmpty) "SERPER_KEY": serperKey,
  };
}

String _envPresence(String name) {
  final value = dotenv.env[name]?.trim() ?? "";
  return value.isEmpty ? "missing" : "present(length=${value.length})";
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ChatScreen(),
    );
  }
}
