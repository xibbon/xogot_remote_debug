# Xogot Connect

A Godot addon that enables remote deployment and debugging of your Godot projects on iOS devices using the [Xogot](https://apps.apple.com/us/app/xogot-make-games-anywhere/id6469385251) app.

## Prerequisites

- **Xogot App**: Install [Xogot from the iOS App Store](https://apps.apple.com/us/app/xogot-make-games-anywhere/id6469385251) on your iPhone or iPad.  
- **Godot Engine**: 4.4.1 or later.


## Installation

1. Copy the `xogot_connect` folder into your project's `addons` folder:

   ```
   your_project/
   └── addons/
       └── xogot_connect/
   ```


2. Enable the addon in Godot:
- Open your project in Godot.
- Go to **Project Settings** → **Plugins**.
- Find **Xogot Connect** in the list.
- Check the box to enable it.

## Usage

Once the plugin is enabled, it adds a new **Xogot** pane on the right side of the Godot editor—next to **Inspector**, **Node**, and **History**.

<img width="343" height="410" alt="image" src="https://github.com/user-attachments/assets/ea801847-5c7c-469a-a044-b87f75503d65" />


### 1. Sign In and Pair Devices

1. Open the **Xogot** pane in Godot.  
2. Tap **Sign In**. This will open your default web browser.  
3. Sign in to the same Xogot account you use on your iPhone or iPad.  
4. After signing in, you’ll see your Xogot profile and API key. Tap **Copy** to copy the API key.  
5. Return to Godot and paste the API key into the **API Key** field where it says *“Paste your API Key.”*  
6. Tap **Submit**. You’ll be taken back to the devices list, where you can:
- **Search for devices** running Xogot on the local network, or  
- **Manually add a device** by entering its IP address and port.

<img width="402" height="415" alt="image" src="https://github.com/user-attachments/assets/2dc07e33-789a-4e66-8dd8-e4cf653a3d15" />

To find a device’s connection details:
- On your iPhone or iPad, open Xogot and switch to the **Remote** tab.
- Ensure the device is **made discoverable**.
- The screen will display *“Waiting for connection”* and show the device name, IP address, and port.

### 2. Remote Deploy and Debug

<img width="352" height="95" alt="image" src="https://github.com/user-attachments/assets/b0262de5-5452-4e69-8105-b51b89dc2968" />

Once a device is discovered or manually added, you can:
- Tap the **Remote Deploy** button in Godot’s toolbar (to the right of the Play, Pause, and Stop buttons) to launch the project on your iOS device.  
- Once the game is running, you can use **Pause** and **Stop**, and hit **breakpoints** just like with local debugging.  
- In Godot’s **Remote** tab, you can browse the **Scene Tree** of the running game, inspect node properties in the **Inspector**, and even modify property values live to observe changes immediately on the device.

### 3. Project Settings for Xogot

<img width="653" height="441" alt="image" src="https://github.com/user-attachments/assets/598e233f-ed3e-4abd-9a5b-187be805d721" />

Enabling the Xogot plugin also adds new project settings to your Godot project.  
You can enable **Xogot’s iOS Virtual Controller** by opening:

**Project Settings → General → Input Devices → Virtual Controller**

This setting lets you test games with touch-based virtual controls when running on Xogot.

<img width="2622" height="1206" alt="image" src="https://github.com/user-attachments/assets/1c11798d-ac01-4708-ab24-7a086c33cea1" />


## About Xogot

[Xogot](https://xogot.com) lets you make games anywhere—on iPad and iPhone—with a native touch-first editor built on the Godot Engine.  
The Xogot Connect addon connects the desktop Godot editor with Xogot, enabling you to **deploy, debug, and test your games on real iOS devices**.
