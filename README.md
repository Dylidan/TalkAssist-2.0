# Talk Assist

This is a Flutter project.

Talk Assist 2.0 is a mobile adaptation of Talk Assist 1.0, a voice-based software application that was designed to support visually impaired users. Allocating edge cutting functionalities like accent handling and environmental adaptation. This system will be developed by extending and modifying an existing prototype build by the previous team.

Talk Assist 2.0 will focus on mobile application development, starting with android as the focus point, IOS implementation be considered after significate development process made in android platform. It will be evaluated through usage scenarios to assess its effectiveness and limitations as an assistive tool. Furthermore, offline capability and additional features will be added to post-public test adjustments.

## How this is build

This project is build under flutter framework. The app uses the llamadart Flutter plugin to run Qwen3.5-0.8B Chat GGUF (Q8_0) locally. Virtial Device emulation is supported by Android Studio.

## Current Virtial Device Setup and specs

Emulated Performance Section:

- CPU cores: 4
- Graphics acceleration: Automatic
- RAM: 4 GB
- VM heap size: 336 MB
- Perferred ABI: Optimal

### Ideal spec:

- 4-6 cores mobile CPU
- 4-8 GB of RAMs
- 128 GB of storage space
- LTE-A / 5G internet connectivity, <150 ms latency
- AI accelerator

## To run this project:

First, make sure your have your emulation device up and running. 

- Visit https://developer.android.com/studio
- You can also view this video till 1:35 (https://www.youtube.com/watch?v=ZXPUulPjl4c) for a visual walk-through of downloading Android Studio.
- Download Android Studio Panda 4
- In Android Studio, check the left panel for the “Plugin” option, and click it.
- Make sure you download the “Dart” plugin for Android Studio.
- Go back to “Projects” on the left panel.
- Click on the three dots on the right-hand side
- Open “Device Manager”
- Select the “+” icon on the upper-left-hand side.
- Select “Medium Phone”
- Make sure you are using API verion 34 for the Andriod Phone
- Go to the addition settings, scroll down, and change the RAM from 2 GB to 4 GB
- Click “Finish” and start the device by clicking the triangle icon pointing to the right side, right next to the three-dots icon in Device Manager, on the right side.
- Active the device and let it initialize.

Then open our code on the your local repo, cd /talk_assist, and run

```
flutter run
```

You can quit the app at anything with Ctrl + C

To run the application without all the debug logs, use:

```
flutter run --profile
```

## Team 6

By Chaoji Yang, JunWei Zhuo, Kenny Huang, Dylan Walker
