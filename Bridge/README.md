# DewPoint Bridge (Apple Home)

ESP32 firmware that listens to your Govee H5102 over Bluetooth and exposes it to Apple Home as:

- Temperature sensor
- Humidity sensor
- Battery (with low battery warning)

It marks itself "Not Responding" if the sensor goes quiet for 10 minutes, so you notice dead batteries or a moved sensor.

## What you need

- Any ESP32, ESP32-S3 or ESP32-C3 dev board with a USB port (about $8 to $12)
- A USB cable and a computer with Chrome or Edge (for flashing, once)
- 2.4 GHz Wi-Fi
- A home hub (HomePod, HomePod mini or Apple TV) if you want remote access and automations while away

Put the board somewhere powered within Bluetooth range of the sensor (same room or next room is ideal).

## 1. Get the firmware

CI builds it on every push. Download from the [firmware release](https://github.com/soum91/dewpoint/releases/tag/firmware-latest):

| Board | File |
|---|---|
| ESP32 (classic, most common) | `DewPointBridge-esp32-full.bin` |
| ESP32-S3 | `DewPointBridge-esp32s3-full.bin` |
| ESP32-C3 | `DewPointBridge-esp32c3-full.bin` |

The `-full.bin` files include bootloader and partition table. The `-app.bin` files are for later updates only.

## 2. Flash it

1. Open https://espressif.github.io/esptool-js/ in Chrome or Edge.
2. Plug in the board, click **Connect**, pick its serial port. (Hold the BOOT button while connecting if it won't connect.)
3. Set **Flash Address** to `0x0`, choose the `-full.bin` file, click **Program**.
4. Press the board's RESET/EN button when it's done.

## 3. Put it on Wi-Fi

1. On your phone, join the Wi-Fi network **HomeSpan-Setup** (password `homespan`).
2. A setup page opens. Enter your 2.4 GHz Wi-Fi name, password and an 8 digit setup code (or keep the default `466-37-726`).
3. The board reboots and joins your Wi-Fi.

The setup network stays up for 5 minutes after boot if no Wi-Fi is saved; reset the board to get it back.

## 4. Add to Apple Home

1. Home app > **+** > **Add Accessory** > **More options...**
2. Pick **DewPoint Bridge**, tap **Add Anyway** on the "Uncertified Accessory" warning.
3. Enter the setup code.

## Which sensor does it bridge?

On first boot the bridge listens for 30 seconds and locks onto the **strongest** Govee sensor it hears, then remembers it across reboots. Keep the board right next to your H5102 for that first boot.

To pin a specific sensor instead, put its Bluetooth name (shown in the DewPoint app under Apple Home, e.g. `GVH5102_9A4C`) into `SENSOR_NAME` at the top of `DewPointBridge.ino` and push; CI rebuilds the firmware.

Serial console (115200 baud, the esptool-js page has a Console tab):

- `@g` shows the locked sensor and last reading
- `@G` forgets the locked sensor and picks again
- `?` lists HomeSpan's own commands (Wi-Fi reset, unpair, etc.)

## Automations that make sense

- An AC or heater that is already in Home (HomeKit or Matter) on when temperature crosses X
- Humidifier or dehumidifier plug on/off by humidity
- Notify yourself via a Home automation + Shortcuts when it's too cold

## Building locally (optional)

Arduino IDE or arduino-cli with the ESP32 core 3.x, and libraries **HomeSpan** 2.x and **NimBLE-Arduino** 2.x. Use the "Minimal SPIFFS" partition scheme so the app fits.
