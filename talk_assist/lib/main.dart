import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'chat_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sherpa_onnx.initBindings();
  await _loadEnvironment();
  runApp(const MainApp());
}

Future<void> _loadEnvironment() async {
  try {
    await dotenv.load(fileName: ".env");
  } on FileNotFoundError {
    debugPrint("No .env file found. Continuing with empty environment.");
    dotenv.testLoad(fileInput: "");
  } on EmptyEnvFileError {
    debugPrint("Empty .env file detected. Continuing with empty environment.");
    dotenv.testLoad(fileInput: "");
  }
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
