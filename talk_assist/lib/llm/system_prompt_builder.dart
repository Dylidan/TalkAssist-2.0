import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:talk_assist/llm/model_config.dart';

class SystemPromptBuilder {
  /// Dynamic system prompt containing current device context
  static Future<String> buildDynamicSystemPrompt() async {
    final now = DateTime.now();
    
    // Battery Info
    String batteryInfo = "Unknown";
    try {
      final battery = Battery();
      final level = await battery.batteryLevel;
      final state = await battery.batteryState;
      final isCharging = state == BatteryState.charging || state == BatteryState.full;
      batteryInfo = "$level% (Charging: $isCharging)";
    } catch (_) {}

    // Network Status
    String networkInfo = "Unknown";
    try {
      final connectivity = Connectivity();
      final results = await connectivity.checkConnectivity();
      if (results.contains(ConnectivityResult.wifi)) {
        networkInfo = "Wi-Fi";
      } else if (results.contains(ConnectivityResult.mobile)) {
        networkInfo = "Mobile Data";
      } else if (results.contains(ConnectivityResult.none)) {
        networkInfo = "Offline";
      } else {
        networkInfo = "Online";
      }
    } catch (_) {}

    // Locale
    final locale = Platform.localeName;

    // Return the model config system prompt with device context
    return '''${ModelConfig.systemPrompt}
    If the user asks about their battery, time, network, or location, use the following real-time data to answer them accurately.
    --- DEVICE CONTEXT ---
    Time: ${now.toLocal()}
    Timezone: ${now.timeZoneName}
    Locale: $locale
    Battery: $batteryInfo
    Network: $networkInfo
    ''';
  }
}
