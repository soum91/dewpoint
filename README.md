# DewPoint

A clean, ad-free iOS app for Govee Bluetooth thermo-hygrometers (built for the **H5102**, also reads H5101, H5104, H5174, H5177, H5075, H5074 and H5179), plus an ESP32 bridge that puts the sensor in **Apple Home**.

No Govee account, no cloud, no ads. The app reads the sensor's Bluetooth broadcasts directly.

## App features

- Live temperature, humidity, dew point, absolute humidity, battery and signal
- Comfort label (dry / comfortable / humid)
- Charts for temperature, humidity or dew point over 1H, 24H, 7D, 20D or everything, with min/avg/max
- **Sync history from the sensor**: downloads the up-to-20 days of minute data the H5102 stores, so gaps get filled
- Multiple sensors, rename, reorder, per-sensor calibration offsets
- Alerts for high/low temperature, high/low humidity and low battery
- CSV export
- Siri and Shortcuts actions: *Get Room Temperature*, *Get Room Humidity*
- °C / °F

Only sensors you tap **Add** on get logged, so a neighbour's sensor never ends up in your history.

## Install

There's no Xcode needed. Every push to `main` builds an unsigned IPA on GitHub Actions.

1. Download `DewPoint-unsigned.ipa` from [Releases](https://github.com/soum91/dewpoint/releases/latest).
2. Sideload with AltStore, SideStore, Sideloadly or TrollStore.
3. Close the Govee Home app before syncing history (only one app can hold the sensor's connection).

## Apple Home

An iPhone app can't add a non-HomeKit device to the Home app; Apple only accepts real accessories or bridges. So this repo includes a bridge firmware for a cheap ESP32 board that listens to the H5102 and shows up in Home as a temperature sensor, humidity sensor and battery. Once it's in Home you get Siri, Home widgets and automations (for example: turn on the AC when the bedroom goes above 25°C).

Setup is in [`Bridge/README.md`](Bridge/README.md). No Arduino install needed: CI builds the firmware and you flash it from Chrome.

## Repo layout

```
App/Sources/          SwiftUI app
project.yml           XcodeGen spec (CI generates the Xcode project)
Bridge/               ESP32 HomeKit bridge (HomeSpan + NimBLE)
.github/workflows/    ios.yml builds the IPA, bridge.yml builds the firmware
```

## Notes and limits

- iOS only delivers these Bluetooth broadcasts while the app is open or was used recently, so app alerts are best-effort. For round-the-clock alerts and automations use the bridge with a home hub (HomePod or Apple TV).
- History download uses Govee's unencrypted GATT protocol. If a future H5102 firmware switches to the encrypted protocol, the app says so instead of failing silently.
- Advertisement decoding follows the open-source [govee-ble](https://github.com/Bluetooth-Devices/govee-ble) parser; the history protocol follows [GoveeBTTempLogger](https://github.com/wcbonner/GoveeBTTempLogger).
