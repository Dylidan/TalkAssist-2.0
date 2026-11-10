# Talk Assist 2.0

A voice-first AI assistant for Android, designed for people who are blind or have low vision. You talk to it, and it talks back: no screen reading or tapping required.

Built as our senior capstone project (ICSI 499) at the University at Albany, SUNY, by a team of four. Talk Assist 2.0 extends Talk Assist 1.0, a desktop prototype built by a previous team, into a mobile app, starting with Android.

<!-- Add a screenshot or short demo GIF here, e.g.: ![Talk Assist chat screen](docs/screenshot.png) -->

## Features

- **Hands-free voice conversation:** wake-word activation, automatic speech detection, and continuous record/send cycles, so the user never has to touch the screen
- **Works online or offline:** answers come from a cloud language model when there is internet, an on-device model when there isn't, and a safe fallback mode if neither is available
- **Up-to-date answers:** questions about current events are grounded with live web search results
- **Voice reminders:** create and manage reminders by speaking, connected to the device calendar
- **Multilingual speech recognition and text-to-speech**
- **Accessibility-first design:** audio-first interaction, guided by WCAG 2.1

## How it works

The app follows an **Ear → Brain → Mouth** pipeline:

| Stage | What it does | Technology |
|-------|--------------|------------|
| **Ear** | Detects speech and converts it to text, on the device | Sherpa ONNX: Whisper (speech-to-text), Silero VAD (speech detection), Sherpa-KWS (wake word) |
| **Brain** | Generates a response, choosing the best available source | OpenRouter (cloud LLM) → Qwen3.5-0.8B (Q8_0 GGUF) via llamadart (on-device) → safe mode, with Serper web search for current information |
| **Mouth** | Reads the response aloud, on the device | Sherpa ONNX: Piper (text-to-speech) |

## Tech stack

- **App:** Flutter / Dart (Android)
- **Native integration:** Kotlin, via Flutter MethodChannels (calendar access)
- **On-device AI:** Sherpa ONNX, llama.cpp (via llamadart)
- **Cloud services:** OpenRouter API, Serper API

## Running it

You need Flutter and [Android Studio](https://developer.android.com/studio) with the Dart plugin installed.

**1. Set up an emulator.** In Android Studio, open **Device Manager**, click **+**, and create a **Medium Phone** using **API 34**. Under the additional settings, raise the RAM from 2 GB to **4 GB** (the on-device model needs it), then start the device.

**2. Create your `.env` file (required).** In the `talk_assist` folder, copy `.env.example` to a new file named `.env`. The app won't build without this file, even if you leave it empty. To enable cloud features, fill in two keys: one from [OpenRouter](https://openrouter.ai) and one from [Serper](https://serper.dev). Without keys, the app runs using the on-device model.

**3. Run the app:**
```
cd talk_assist
flutter pub get
flutter run
```

To run without debug logs, use `flutter run --profile`. Press Ctrl+C to quit.

On first launch, the app downloads the on-device model, which takes a few minutes.

**Recommended device specs:** 4–6 core CPU, 4–8 GB RAM, and a fast connection (under 150 ms latency) for cloud features.

### Developer commands

Erase chat history:
```
adb shell run-as com.example.talk_assist rm -f app_flutter/history.json
```

Clear all app data (settings, downloads, everything; the model re-downloads on next launch):
```
adb shell pm clear com.example.talk_assist
```

## My contributions (Dylan Walker)

I focused on the assistant's online intelligence layer:

- **OpenRouter integration:** built the service that handles all communication with the cloud language model, including message formatting, API key validation, connectivity-aware readiness checks, and tagging each response with its origin so the UI can show which service produced each reply
- **Web search grounding pipeline:** designed and built the system that detects when a question needs current information, fetches live results from the Serper API, and adds them to the model's context so it can answer with up-to-date facts

Key files: `open_router_llm_service.dart`, `search_config.dart`, `search_injector.dart`, `serper_search_service.dart`

## Team 6

- **Dylan Walker:** LLM and online features: OpenRouter integration and the web search grounding pipeline
- **JunWei Zhuo:** speech recognition, multilingual support, and voice-driven reminders
- **Kenny Huang:** LLM and TTS integration, prompt engineering, model benchmarking and evaluation; team secretary and main contact with our sponsor
- **Chaoji Yang:** frontend architecture and the chat UI, conversation history, the voice pipeline (speech detection, auto record/send, wake word), and the online/offline state architecture

This is a portfolio copy of our team's original repository, including its full commit history.
