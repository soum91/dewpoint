# Changelog

## [build-26] - 2026-11-22

## Verified changes since build-25

- Retain DewPoint Govee LAN send until UDP completion or timeout ([`289836ac`](https://github.com/soum91/dewpoint/commit/289836ac37443fb3e9322d24a46e848c46e9072d); `App/Sources/BridgeSource.swift`)

[Inspect exact code changes](https://github.com/soum91/dewpoint/compare/build-25...build-26)

## [build-25] - 2026-11-22

## Verified changes since build-23

- iOS: send Bluetooth feed on main actor; clarify Keystone-only firmware ownership ([`4c5eed2d`](https://github.com/soum91/dewpoint/commit/4c5eed2dae5edf601c5e3b3247aa681591660fab); `App/Sources/BLEManager.swift`, `App/Sources/HomeBridgeView.swift`, `project.yml`)
- iOS: forward direct Govee BLE readings to Keystone ESP32 without extra firmware ([`2308cc8f`](https://github.com/soum91/dewpoint/commit/2308cc8f84b2294e9dcc40a2631e54eea6a3d6d5); `App/Sources/BLEManager.swift`, `App/Sources/BridgeSource.swift`, `App/Sources/HomeBridgeView.swift`)
- Revert unintended DewPoint ESP32 firmware changes; keep Keystone as firmware owner ([`3a87f010`](https://github.com/soum91/dewpoint/commit/3a87f010d7a1dc7a23a090eddca052519dc4e4aa); `.github/workflows/bridge.yml`, `Bridge/DewPointBridge/DewPointBridge.ino`, `Bridge/README.md`)
- CI: pin Arduino ESP32 3.3.12 for HomeSpan compatibility ([`d884a83c`](https://github.com/soum91/dewpoint/commit/d884a83c4dc6c1756b7d965b7a2034e185a5640d); `.github/workflows/bridge.yml`)
- Bridge: continuously relay pinned Govee readings to Keystone over local UDP ([`b7da318b`](https://github.com/soum91/dewpoint/commit/b7da318b649a07d2690c8a6fd0f2ba59df17dac6); `Bridge/DewPointBridge/DewPointBridge.ino`, `Bridge/README.md`)

[Inspect exact code changes](https://github.com/soum91/dewpoint/compare/build-23...build-25)

This log records verified, release-specific changes. The [Factual release changelog](.github/workflows/release-changelog.yml) GitHub Action adds entries based on the actual commits between published releases. Entries are not fabricated for older versions that have not been audited.

