# Summary
This project is a client application to control an EV3 LEGO Mindstorms robot. Please note that this app was designed and tested in Android.

# Robot physical configuration
The current build ensues a tank-like configuration with a vertical claw attached to the back and an infrared sensor facing front. Movement is handled with two large motors that move continuous tracks located at each side, while the caw is attached to a medium motor that handles it's movement.

# Requirements
The application depends on a few external factors:
1. The robot runs ev3dev.
2. The robot is tethered to the device running the application via Bluetooth **Internet hotspot**.
3. The robot runs a custom Python "server" that listens to instructions from the app.
4. Gemini LLM (for voice commands).
5. Internet availability (to reach Gemini).

## Caveats
- The app's dependency on the robot running specific software makes it not very accessible for the average user. Although specific instructions may be provided, it'd still prove a tedious task to set everything up for the first time, and it also requires a MicroSD card (for running ev3dev) which might not be immediately available.

- Since the server is specifically designed for this particular configuration of the robot, it may not work properly with different (physical) builds of the LEGO robot. Sensor info should be able to be read despite the configuration, but currently it's not used for any purpose.

- While Gemini is the easiest to use LLM to normalize the instructions into something the robot can read (due to free usage and being hosted by Google), it introduces another set of issues, namely the need for an API key and the limitations of the free tier. Currently a personal API key is being used.

# Controls
The robot is controlled by passing a set of instructions via sockets to the robot, these can be either a movement vector for joystick movement or text instructions based on a voice command.

## Instruction syntax
### Joystick movement
For joystick movement, the syntax is `stick:<x-coordinate>;<y-coordinate>;<claw>`. Where the `x` and `y` coordinates are the components of the joystick vector, and `claw` is a boolean value represented as either a `1` or a `0`.

### Voice command movement
For voice commands, the command is first recognized using the platform's native voice recognition, please note that this app was designed for and Android phone, so no guarantees are made for other platforms (namely, PC and web), once the words are recognized they're processed by Gemini (Google's LLM, as of writing, using Gemini Flash 1.5 latest), which returns a set of instructions, these are then mapped to single letters that represent an action to shorten the string sent. The following is the mapping currently being used:

```dart
final instructionMap = {
  "adelante": "f",  //forward
  "atrás": "b",     //backward
  "izquierda": "l", //left
  "derecha": "r",   //right
  "agarrar": "p",   //pick up
  "soltar": "d"  ,  //drop
  "?": null,        //invalid
};
```

These include all movement options for the current configuration of the robot, plus control of the claw attached to the medium motor.

With the instructions mapped and shortened, they are joined into a single string with the following syntax: `text:<instruction>-[amount]-[unit][;...]` (E.g. `text:f-20-cm;l;b-3-m`).
Available units are meters, centimeters and seconds, each represented by their respective unit symbols. Currently, only `f` (forward) and `b` (backward) instructions take units, while `l` (left) and `r` (right) turn the robot in place. Units are obviously not applicable to claw instructions.

# Connecting to the robot
If the robot is already running ev3dev and the server application, you can connect to the robot doing the following:
1. Startup the robot and wait for ev3dev's main menu.
2. Select Bluetooth and pair your device. Remember to turn on your device's Bluetooth tethering option!
3. Once the device is paired, connect to it via the `Network Connection` option (using your device as a Bluetooth hotspot). Once connected an IP address should show up on the top left corner of the screen.
4. Run the server application via the `main.py` file.
5. Wait for the IP to show up in the screen. This should be the same address shown after step 3.
6. Run the phone app.
7. In the input box, write the robot's IP address and wait for it to connect. Once connected, the robot should make a sound, and it's ready to control.

For more detailed instructions on connecting the robot via Bluetooth tethering, visit the following [link](https://www.ev3dev.org/docs/tutorials/connecting-to-the-internet-via-bluetooth/) and read the `Android` section.