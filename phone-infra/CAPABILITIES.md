# Termux:API Capability Matrix

**Last Updated:** 2026-05-19 11:30 PT

## Executive Summary

- **Pixel 6:** Termux:API APK installed + permissions configured. 7/10 capabilities working.
- **Pixel 10:** Termux:API APK **missing**. CLI tools present but bridge daemon unavailable. 2/10 capabilities.
- **Phone-to-Phone SSH:** Working end-to-end. Ed25519 keys generated and cross-authenticated. File transfer verified.

---

## Capability Matrix

| Capability | Pixel 6 | Pixel 10 | Status |
|---|---|---|---|
| **termux-battery-status** | ✅ Works | ✅ Works | Returns full battery JSON (health, charge %, temp, voltage) |
| **termux-location -p network** | ⏳ Timeout | ❌ Missing APK | Pixel 6: Network provider hangs (may need location enabled); Pixel 10: "Termux:API not available on Google Play" |
| **termux-location -p gps** | Not tested | ❌ Missing APK | Requires Termux:API APK on both |
| **termux-clipboard-get** | ✅ Works | ⏳ Unknown | Pixel 6: returns empty (normal if clipboard empty); Pixel 10: likely works (no APK dependency) |
| **termux-clipboard-set** | Not tested | ⏳ Unknown | Should work on both (no APK dependency) |
| **termux-tts-speak** | ✅ Works | ⏳ Unknown | Pixel 6: executes silently (audio plays on device); Pixel 10: likely works |
| **termux-vibrate** | Not tested | ⏳ Unknown | Should work on both (no APK dependency) |
| **termux-camera-info** | ✅ Works | ❌ Missing APK | Pixel 6: Lists back + front camera specs (4K capable, auto-exposure modes) |
| **termux-sensor -l** | ✅ Works | ❌ Missing APK | Pixel 6: Lists accelerometer, magnetometer, gyro, light, proximity sensors |
| **termux-telephony-deviceinfo** | 🔒 Needs Permission | ❌ Missing APK | Pixel 6: Missing `android.permission.READ_PHONE_STATE` (can grant via ADB) |
| **termux-wifi-connectioninfo** | ✅ Works | ❌ Missing APK | Pixel 6: Returns SSID, IP (192.168.12.201), link speed (487 Mbps), RSSI (-33) |
| **termux-notification** | ✅ Works | ✅ Works | Both: System notifications posted successfully |

---

## Detailed Findings

### Pixel 6 (100.72.211.71:8022)
- **Termux:API Status:** APK installed (version code 1002, dated Sep 2025)
- **Location Services:** Hangs on network provider query (30s timeout). May require:
  - Device location settings enabled
  - Fresh location fix
  - NetworkProvider service running
- **Permissions Granted:** ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION
- **Permissions Missing:** READ_PHONE_STATE (for telephony-deviceinfo)
- **Battery:** 99% (wireless charging), temperature 31°C, cycle count 555
- **Cameras:** 2 (back 4000×3000 main, front 3264×2448)
- **Sensors:** Accelerometer, Magnetometer, Light, Proximity, Gyro, Barometer
- **Hardware:** Pixel 6 (oriole), Android 14+

### Pixel 10 (100.75.250.48:8022)
- **Termux:API Status:** APK **NOT installed**. CLI wrapper scripts present (`/data/data/com.termux/files/usr/bin/termux-*`) but daemon bridge missing.
- **Error Message:** "Termux:API is not yet available on Google Play - see https://github.com/termux-play-store/termux-apps/issues/29 for updates"
- **Workaround Path:** 
  1. Install from F-Droid: `https://f-droid.org/repo/com.termux.api_1002.apk` (version 1002 = current stable)
  2. Or: Max installs from Play Store directly on device if version is now available
- **Battery:** 100% (connected), temperature 33.7°C, cycle count 148
- **Hardware:** Pixel 10 (frankel), Android 15+

### Phone-to-Phone SSH
- **Status:** ✅ Fully working
- **Setup:** Ed25519 keys generated on both phones, cross-added to authorized_keys
- **SSH Aliases:** Configured on both sides (ssh pixel6, ssh pixel10 work from opposite phone)
- **Port:** 8022 (Termux SSH daemon default)
- **File Transfer:** SCP verified (copied test_pixel6.txt → Pixel 10 → read successfully)
- **Use Case:** Ready for bidirectional automation (log sync, data exchange, cross-device triggers)

---

## Remediation Tasks

### **CRITICAL: Fix Pixel 10 Termux:API**
```bash
# Option A: F-Droid (recommended if Play Store version unavailable)
# Max manually downloads from:
# https://f-droid.org/repo/com.termux.api_1002.apk
# Then installs via adb or file manager on device

# Option B: Play Store (if version now available)
# Device: Settings > Google Play Store > search "Termux:API" > install

# After install, grant permissions:
adb -s adb-59050DLCR000YM-AINs6v._adb-tls-connect._tcp shell pm grant \
  com.termux.api android.permission.ACCESS_FINE_LOCATION
adb -s adb-59050DLCR000YM-AINs6v._adb-tls-connect._tcp shell pm grant \
  com.termux.api android.permission.ACCESS_COARSE_LOCATION
```

### **Recommended: Fix Pixel 6 Telephony Permission**
```bash
adb -s 192.168.12.201:41215 shell pm grant \
  com.termux.api android.permission.READ_PHONE_STATE
```

### **Investigation: Pixel 6 Location Timeout**
- Check if location services are enabled on the device (Settings > Location)
- Verify Network provider is available (may fail indoors without WiFi location DB)
- Alternative: Test GPS provider after enabling location + getting a satellite fix outdoors
- Current hypothesis: NetworkProvider not initialized or WiFi scan results unavailable

---

## Next Steps

1. **Install Termux:API on Pixel 10** (blocker for location, sensors, camera, telephony)
2. **Verify Pixel 6 location** (outdoor test or enable all location providers)
3. **Grant Pixel 6 telephony permission** (one-liner via ADB)
4. **Run integration test:** Both phones report location every 60s to shared HARK map state file
5. **Implement phone-sync daemon:** Heartbeat + map updates via phone-to-phone SSH

---

## Technical Notes

- Termux:API relies on a companion APK that acts as a bridge between CLI scripts and Android hardware/permissions
- Without the APK, commands that require hardware access (location, camera, sensors, telephony) fail with the "not yet available" message
- Commands that read system settings or use built-in features (battery, clipboard, notifications, vibration) may still work
- ADB device selector: Use `-s` flag to target Pixel 6 (network ADB) or Pixel 10 (mDNS ADB)
- SSH keys are now persistent; future phone-to-phone operations require no manual auth
