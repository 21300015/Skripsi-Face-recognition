# DOKUMENTASI TEKNIS SISTEM KEAMANAN MENGGUNAKAN METODE FACE RECOGNITION UNTUK KONTROL AKSES PINTU RUANGAN TATA USAHA PADA SMK IT NURUL QOLBI

**Penulis: Taufik Hidayat**  
**NIM: 21300015**  
**Tanggal Dokumentasi: 6 Desember 2025**

---

## DAFTAR ISI

1. [Arsitektur Sistem](#1-arsitektur-sistem)
2. [Spesifikasi Hardware](#2-spesifikasi-hardware)
3. [Konfigurasi Firmware ESP32-S3](#3-konfigurasi-firmware-esp32-s3)
4. [Aplikasi Mobile Flutter](#4-aplikasi-mobile-flutter)
5. [Protokol Komunikasi](#5-protokol-komunikasi)
6. [Algoritma Face Recognition](#6-algoritma-face-recognition)
7. [Sistem Anti-Spoofing (Liveness Detection)](#7-sistem-anti-spoofing-liveness-detection)
8. [Manajemen User dan Database](#8-manajemen-user-dan-database)
9. [Diagram Alur Sistem](#9-diagram-alur-sistem)
10. [Konfigurasi Jaringan](#10-konfigurasi-jaringan)
11. [Serial Monitor Log (Contoh Output)](#11-serial-monitor-log-contoh-output)
12. [SD Card Integration](#12-sd-card-integration)

---

## 1. ARSITEKTUR SISTEM

### 1.1 Overview Arsitektur

Sistem ini menggunakan arsitektur **Client-Server** dengan komponen utama:

```
┌─────────────────────┐     WiFi      ┌────────────────────────┐
│   Aplikasi Flutter  │◄─────────────►│     ESP32-S3 WROOM     │
│   (Client/Admin)    │   HTTP/REST   │    (Server/Camera)     │
└─────────────────────┘               └───────────┬────────────┘
                                                  │
                                    ┌─────────────┼─────────────┐
                                    │             │             │
                                    │ GPIO 21     │ SD_MMC      │
                                    ▼             │             ▼
                        ┌────────────────┐    ┌────────────────────┐
                        │  Relay Module  │    │     SD Card        │
                        │  (Door Lock)   │    │  (Logs/Profiles)   │
                        └────────────────┘    └────────────────────┘
```

### 1.2 Komponen Utama Sistem

| Komponen         | Fungsi                                          | Teknologi                 |
| ---------------- | ----------------------------------------------- | ------------------------- |
| ESP32-S3 WROOM   | Pengolahan gambar, face recognition, web server | C++, Arduino Framework    |
| Kamera OV2640    | Capture gambar wajah                            | 240x240 pixel (face mode) |
| Aplikasi Flutter | Manajemen user, monitoring, konfigurasi         | Dart, Flutter 3.x         |
| Relay Module     | Kontrol penguncian pintu                        | 5V Relay, GPIO control    |
| SPIFFS           | Penyimpanan data embedding wajah                | Flash memory internal     |
| SD Card          | Penyimpanan activity log & profile image        | 16GB, SD_MMC interface    |

---

## 2. SPESIFIKASI HARDWARE

### 2.1 Microcontroller: Freenove ESP32-S3 WROOM

```
┌─────────────────────────────────────────────────────────────┐
│                 SPESIFIKASI ESP32-S3 WROOM                  │
├─────────────────────────────────────────────────────────────┤
│ Platform        : Espressif32 (versi 6.12.0)                │
│ Board           : Freenove ESP32-S3 WROOM                   │
│ MCU             : ESP32-S3                                  │
│ CPU Frequency   : 240 MHz (Dual Core Xtensa LX7)            │
│ Flash Memory    : 8 MB                                      │
│ PSRAM           : 8 MB (QIO PSRAM)                          │
│ SRAM            : 320 KB                                    │
│ WiFi            : 802.11 b/g/n                              │
│ Bluetooth       : BLE 5.0                                   │
│ Upload Speed    : 921600 baud                               │
│ Monitor Speed   : 115200 baud                               │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Konfigurasi PlatformIO (platformio.ini)

```ini
[env:freenove_esp32_s3_wroom]
platform = espressif32
board = freenove_esp32_s3_wroom
framework = arduino

; Board configuration
board_build.mcu = esp32s3
board_build.f_cpu = 240000000L
board_build.flash_size = 8MB
board_build.psram_type = qio_psram
board_build.partitions = huge_app.csv

; Library dependencies
lib_deps =
    https://github.com/dvarrel/AsyncTCP.git
    https://github.com/mathieucarbou/ESPAsyncWebServer.git@^3.0.0

; Build flags
build_flags =
    -DCONFIG_IDF_TARGET_ESP32S3=1
    -DBOARD_HAS_PSRAM
    -DCORE_DEBUG_LEVEL=3
    -DUSE_ESP32S3_WROOM=1
    -DESP32S3_FACE_RECOGNITION=1
    -DHTTP_METHOD_MAP=XX

; Communication settings
monitor_speed = 115200
upload_speed = 921600
```

### 2.3 Pin Configuration

| Pin ESP32-S3 | Fungsi         | Keterangan                     |
| ------------ | -------------- | ------------------------------ |
| GPIO 21      | DOOR_RELAY_PIN | Output ke relay pengunci pintu |
| GPIO 2       | STATUS_LED_PIN | LED indikator sistem           |
| GPIO 1-20    | Camera Pins    | Koneksi ke modul kamera OV2640 |

### 2.4 Memory Usage (Hasil Kompilasi)

```
RAM:   [===       ]  33.1% (used 108,444 bytes from 327,680 bytes)
Flash: [==========]  96.5% (used 3,035,017 bytes from 3,145,728 bytes)
```

---

## 3. KONFIGURASI FIRMWARE ESP32-S3

### 3.1 Parameter Sistem Utama

```cpp
// ========================================
// SYSTEM CONFIGURATION
// ========================================

// WiFi Station Mode (Primary)
#define DEFAULT_WIFI_SSID "AVARA HOUSE_EXT"
#define DEFAULT_WIFI_PASSWORD "rioavaradudut2010"
#define WIFI_CONNECT_TIMEOUT 15000  // 15 detik timeout

// WiFi AP Mode (Fallback)
#define AP_SSID "Skripsi 21300015"
#define AP_PASSWORD "123456789"

// Server Ports
// Port 80  : REST API (AsyncWebServer)
// Port 81  : MJPEG Live Stream (WiFiServer)

// MJPEG Streaming
#define PART_BOUNDARY "123456789000000000000987654321"
WiFiServer streamServer(81);  // MJPEG stream on port 81
```

### 3.2 Parameter Face Recognition

```cpp
// ========================================
// ANTI-SPOOFING & RECOGNITION CONFIG
// ========================================

#define RECOGNITION_THRESHOLD 0.88f       // Threshold balanced untuk akurasi (tuned)
#define RECOGNITION_CONFIRM_COUNT 3       // Harus match 3x berturut-turut
#define SAME_USER_COOLDOWN 5000           // 5 detik cooldown user yang sama
#define DOOR_UNLOCK_DURATION 3000         // Pintu terbuka 3 detik

// Anti-spoofing: Liveness detection thresholds - BALANCED MODE
#define LIVENESS_CHECK_COUNT 4            // Jumlah frame untuk liveness check (optimized untuk response cepat)
#define LIVENESS_MIN_MICRO_MOVEMENT 1     // Minimal gerakan mikro (pixel)
#define LIVENESS_MAX_MICRO_MOVEMENT 20    // Maksimal gerakan mikro alami
#define LIVENESS_PHOTO_THRESHOLD 30       // Gerakan di atas ini = curiga foto
#define LIVENESS_CONSISTENCY_REQUIRED 2   // Perlu 2 pola gerakan mikro konsisten
#define LIVENESS_SIZE_STABILITY_MAX 5     // Foto memiliki ukuran sangat stabil
```

### 3.3 Parameter Enrollment

```cpp
#define REQUIRED_ENROLLMENT_STEPS 3       // 3 langkah enrollment wajah
#define MAX_ACTIVITY_LOGS 50              // Circular buffer untuk activity log
```

### 3.4 Struktur Data Activity Log

```cpp
struct ActivityLog {
    String username;          // Nama pengguna
    String action;            // Jenis aksi (ACCESS_GRANTED, DENIED_LOW_CONFIDENCE, dll)
    bool success;             // Status keberhasilan
    float confidence;         // Nilai confidence recognition
    unsigned long timestamp;  // Waktu kejadian (millis)
};
ActivityLog activityLogs[MAX_ACTIVITY_LOGS];
```

### 3.5 Struktur Data Liveness Detection

```cpp
struct FacePosition {
    int cx;       // Center X position
    int cy;       // Center Y position
    int width;    // Lebar wajah terdeteksi
    int height;   // Tinggi wajah terdeteksi
    bool valid;   // Flag validitas data
};
FacePosition faceHistory[LIVENESS_CHECK_COUNT];
```

### 3.6 Struktur Data System Status

```cpp
struct {
    bool cameraReady = false;           // Status kamera
    bool recognitionReady = false;      // Status face recognition
    String lastRecognizedUser = "";     // User terakhir yang dikenali
    float lastConfidence = 0.0;         // Confidence terakhir
    unsigned long lastActivity = 0;     // Waktu aktivitas terakhir
    int totalUsers = 0;                 // Total user terdaftar
} systemStatus;
```

---

## 4. APLIKASI MOBILE FLUTTER

### 4.1 Informasi Aplikasi

```yaml
name: akses_kontrol_pintu
description: "Taufik Hidayat-21300015"
version: 1.0.0+1

environment:
  sdk: ">=3.8.0-265.0.dev <4.0.0"
```

### 4.2 Dependencies (Library yang Digunakan)

| Library         | Versi   | Fungsi                                |
| --------------- | ------- | ------------------------------------- |
| flutter         | SDK     | Framework utama                       |
| hive            | ^2.2.3  | Local database (NoSQL)                |
| hive_flutter    | ^1.1.0  | Hive integration untuk Flutter        |
| http            | ^1.1.0  | HTTP client untuk REST API            |
| image           | ^4.0.17 | Image processing                      |
| image_picker    | ^1.0.4  | Akses kamera/galeri untuk foto profil |
| path_provider   | ^2.1.1  | Akses file system                     |
| intl            | ^0.20.2 | Internationalization (format tanggal) |
| cupertino_icons | ^1.0.8  | iOS-style icons                       |

### 4.3 Struktur Folder Aplikasi

```
akses_kontrol_pintu/
├── lib/
│   ├── main.dart                    # Entry point aplikasi
│   ├── models/
│   │   ├── user.dart                # Model data User
│   │   ├── user.g.dart              # Generated Hive adapter
│   │   ├── activity.dart            # Model data Activity
│   │   └── activity.g.dart          # Generated Hive adapter
│   ├── screens/
│   │   ├── home_screen.dart         # Halaman utama + live feed
│   │   ├── add_user_screen.dart     # Tambah/edit user + enrollment
│   │   ├── manage_user_screen.dart  # Daftar user
│   │   ├── door_activity_screen.dart# Log aktivitas pintu
│   │   └── wifi_config_screen.dart  # Konfigurasi WiFi ESP32
│   ├── services/
│   │   └── esp32_service.dart       # HTTP client untuk ESP32 API
│   └── widgets/
│       └── mjpeg_viewer.dart        # Custom MJPEG stream viewer
├── assets/
│   ├── logo.png                     # Logo aplikasi
│   ├── offline.jpg                  # Placeholder offline
│   └── app_logo.png                 # Icon aplikasi
└── pubspec.yaml                     # Project configuration
```

### 4.4 Model Data User

```dart
@HiveType(typeId: 0)
class User extends HiveObject {
  @HiveField(0)
  int id;                    // ID unique user

  @HiveField(1)
  String nama;               // Nama lengkap

  @HiveField(2)
  String jabatan;            // Jabatan/posisi

  @HiveField(3)
  String departemen;         // Departemen/divisi

  @HiveField(4)
  DateTime masaBerlaku;      // Masa berlaku akses

  @HiveField(5)
  String thumbnailPath;      // Path foto profil lokal
}
```

### 4.5 Model Data Activity

```dart
@HiveType(typeId: 1)
class Activity extends HiveObject {
  @HiveField(0)
  String status;             // Status: ACCESS_GRANTED, DENIED, dll

  @HiveField(1)
  String username;           // Nama user

  @HiveField(2)
  DateTime time;             // Waktu kejadian
}
```

### 4.6 MJPEG Viewer Widget

Widget custom untuk menampilkan live stream MJPEG dari ESP32:

```dart
class MjpegViewer extends StatefulWidget {
  final String streamUrl;        // URL stream (http://IP:81/)
  final BoxFit fit;              // Image fit mode
  final Widget? loadingWidget;   // Widget saat loading
  final Widget? errorWidget;     // Widget saat error
}
```

**Algoritma Parsing MJPEG:**

1. Koneksi HTTP GET ke stream URL
2. Receive data chunk dari response stream
3. Buffer data dan cari JPEG marker:
   - Start marker: `0xFF 0xD8`
   - End marker: `0xFF 0xD9`
4. Extract complete JPEG frame dari buffer
5. Display frame dengan `Image.memory()` dan `gaplessPlayback: true`
6. Loop untuk frame berikutnya

---

## 5. PROTOKOL KOMUNIKASI

### 5.1 Arsitektur Server ESP32

```
┌─────────────────────────────────────────────────────────────┐
│                    ESP32-S3 SERVER                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │        AsyncWebServer (Port 80)                      │   │
│  │        ─────────────────────────                     │   │
│  │        REST API Endpoints:                           │   │
│  │        • /api/status          GET                    │   │
│  │        • /api/enroll/start    POST                   │   │
│  │        • /api/enroll/cancel   POST                   │   │
│  │        • /api/enroll/status   GET                    │   │
│  │        • /api/enroll/clear    POST                   │   │
│  │        • /api/door/unlock     POST                   │   │
│  │        • /api/logs            GET                    │   │
│  │        • /api/logs/clear      POST                   │   │
│  │        • /api/users           GET/POST/DELETE        │   │
│  │        • /api/wifi/status     GET                    │   │
│  │        • /api/wifi/scan       GET                    │   │
│  │        • /api/wifi            POST                   │   │
│  │        • /api/livefeed/start  POST                   │   │
│  │        • /api/livefeed/stop   POST                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │        WiFiServer (Port 81)                          │   │
│  │        ─────────────────────                         │   │
│  │        MJPEG Live Streaming                          │   │
│  │        Content-Type: multipart/x-mixed-replace       │   │
│  │        Frame Rate: ~30 FPS                           │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 REST API Endpoints

#### 5.2.1 System Status

```http
GET /api/status HTTP/1.1
Host: 192.168.x.x

Response:
{
  "camera_ready": true,
  "recognition_ready": true,
  "total_users": 5,
  "last_user": "Taufik",
  "last_confidence": 0.95,
  "door_unlocked": false,
  "free_heap": 152000,
  "free_psram": 4000000
}
```

#### 5.2.2 Start Enrollment

```http
POST /api/enroll/start HTTP/1.1
Host: 192.168.x.x
Content-Type: application/x-www-form-urlencoded

name=Taufik

Response:
{
  "message": "Enrollment started for Taufik",
  "steps_required": 3
}
```

#### 5.2.3 Get Enrollment Status

```http
GET /api/enroll/status HTTP/1.1
Host: 192.168.x.x

Response (in progress):
{
  "active": true,
  "user": "Taufik",
  "steps_completed": 2,
  "steps_required": 3,
  "complete": false,
  "message": "Enrolling step 3/3"
}

Response (completed):
{
  "active": false,
  "user": "Taufik",
  "steps_completed": 3,
  "steps_required": 3,
  "complete": true,
  "message": "Enrollment completed for Taufik"
}
```

#### 5.2.4 Unlock Door

```http
POST /api/door/unlock HTTP/1.1
Host: 192.168.x.x
Content-Type: application/json

Response:
{
  "message": "Door unlocked manually"
}
```

#### 5.2.5 Get Access Logs

```http
GET /api/logs HTTP/1.1
Host: 192.168.x.x

Response:
[
  {
    "username": "Taufik",
    "status": "ACCESS_GRANTED",
    "success": true,
    "confidence": 0.95,
    "timestamp": 1234567890
  }
]
```

#### 5.2.6 Get Users

```http
GET /api/users HTTP/1.1
Host: 192.168.x.x

Response:
[
  {
    "id": 0,
    "name": "Taufik",
    "jabatan": "",
    "departemen": "",
    "masaBerlaku": "2025-12-31"
  }
]
```

#### 5.2.7 Delete User

```http
DELETE /api/users?name=Taufik HTTP/1.1
Host: 192.168.x.x

Response:
{
  "success": true,
  "message": "User deleted"
}
```

#### 5.2.8 WiFi Configuration

```http
GET /api/wifi/status HTTP/1.1
Response:
{
  "mode": "STATION",
  "ssid": "AVARA HOUSE_EXT",
  "ip": "192.168.0.128",
  "rssi": -45,
  "connected": true
}

GET /api/wifi/scan HTTP/1.1
Response:
{
  "networks": [
    {"ssid": "Network1", "rssi": -40, "encryption": true},
    {"ssid": "Network2", "rssi": -65, "encryption": false}
  ]
}

POST /api/wifi HTTP/1.1
Content-Type: application/x-www-form-urlencoded
ssid=NewNetwork&password=password123

Response:
{
  "success": true,
  "message": "WiFi configuration saved. ESP32 will restart..."
}
```

### 5.3 MJPEG Streaming Protocol

```http
GET / HTTP/1.1
Host: 192.168.x.x:81

HTTP/1.1 200 OK
Content-Type: multipart/x-mixed-replace; boundary=123456789000000000000987654321
Access-Control-Allow-Origin: *
Cache-Control: no-cache
Connection: close

--123456789000000000000987654321
Content-Type: image/jpeg
Content-Length: 12345

[JPEG Binary Data]

--123456789000000000000987654321
Content-Type: image/jpeg
Content-Length: 12346

[JPEG Binary Data]

... (continues at ~30 FPS)
```

---

## 6. ALGORITMA FACE RECOGNITION

### 6.1 Library yang Digunakan

Sistem menggunakan **EloquentEsp32cam** library untuk face recognition:

```cpp
#include <eloquent_esp32cam.h>
#include <eloquent_esp32cam/face/detection.h>
#include <eloquent_esp32cam/face/recognition.h>

using eloq::camera;
using eloq::face::detection;
using eloq::face::recognition;
```

### 6.2 Inisialisasi Kamera

```cpp
bool initCamera() {
    camera.pinout.freenove_s3();         // Pin configuration untuk Freenove S3
    camera.brownout.disable();            // Disable brownout detector
    camera.resolution.face();             // 240x240 pixel - optimal untuk face recognition
    camera.quality.high();                // Kualitas tinggi

    // Retry mechanism
    int attempts = 0;
    while (!camera.begin().isOk() && attempts < 5) {
        Serial.printf("Camera init attempt %d failed\n", attempts + 1);
        delay(1000);
        attempts++;
    }
    return attempts < 5;
}
```

### 6.3 Inisialisasi Face Recognition

```cpp
bool initRecognition() {
    detection.accurate();                  // Mode akurat untuk deteksi
    detection.confidence(0.7);             // Detection confidence threshold 70%
    recognition.confidence(0.93f);         // Recognition confidence threshold 93%

    return recognition.begin().isOk();
}
```

### 6.4 Alur Face Recognition

```
┌─────────────────┐
│ Camera Capture  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐    No Face    ┌─────────────────┐
│ Face Detection  │──────────────►│ Reset Liveness  │
└────────┬────────┘               │ Continue Loop   │
         │ Face Found             └─────────────────┘
         ▼
┌─────────────────┐
│ Record Position │
│ for Liveness    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐    No Users   ┌─────────────────┐
│ Check Enrolled  │──────────────►│ Show Warning    │
│ Users Count     │               │ Continue Loop   │
└────────┬────────┘               └─────────────────┘
         │ Users > 0
         ▼
┌─────────────────┐    Not Match  ┌─────────────────┐
│ Face Recognition│──────────────►│ Log & Reset     │
│ (Matching)      │               │ Continue Loop   │
└────────┬────────┘               └─────────────────┘
         │ Match Found
         ▼
┌─────────────────┐    Low        ┌─────────────────┐
│ Check Confidence│──────────────►│ Log DENIED      │
│ >= 0.93 ?       │               │ Reset & Continue│
└────────┬────────┘               └─────────────────┘
         │ Confidence OK
         ▼
┌─────────────────┐    Not 3x     ┌─────────────────┐
│ Consecutive     │──────────────►│ Increment Count │
│ Matches >= 3?   │               │ Continue Loop   │
└────────┬────────┘               └─────────────────┘
         │ 3 Matches
         ▼
┌─────────────────┐    Failed     ┌─────────────────┐
│ Liveness Check  │──────────────►│ Log LIVENESS    │
│ (Anti-Spoofing) │               │ FAIL, Continue  │
└────────┬────────┘               └─────────────────┘
         │ Passed
         ▼
┌─────────────────┐    Active     ┌─────────────────┐
│ Cooldown Check  │──────────────►│ Show Remaining  │
│ (5 seconds)     │               │ Time, Continue  │
└────────┬────────┘               └─────────────────┘
         │ Not in Cooldown
         ▼
┌─────────────────────────────────────────────────────┐
│              ✅ ACCESS GRANTED                       │
│              Unlock Door (3 seconds)                │
│              Log Activity                           │
│              Reset All Counters                     │
└─────────────────────────────────────────────────────┘
```

### 6.5 Proses Enrollment Wajah

```cpp
void handleEnrollment() {
    // 1. Capture image
    if (!camera.capture().isOk()) return;

    // 2. Detect face
    if (!recognition.detect().isOk()) return;

    // 3. Enroll face dengan nama user
    if (recognition.enroll(currentEnrollmentUser).isOk()) {
        enrollmentSteps++;

        if (enrollmentSteps >= REQUIRED_ENROLLMENT_STEPS) {
            // Enrollment selesai
            enrollmentJustCompleted = true;
            lastEnrolledUser = currentEnrollmentUser;
            enrollmentMode = false;
        }

        delay(2000);  // Pause antar step enrollment
    }
}
```

---

## 7. SISTEM ANTI-SPOOFING (LIVENESS DETECTION)

### 7.1 Konsep Liveness Detection

Sistem ini mencegah serangan menggunakan foto/gambar statis dengan memeriksa **5 kriteria anti-spoofing** menggunakan **4 frame** untuk analisis (dioptimalkan dari 5 frame untuk response lebih cepat):

1. **Completely Static Check** - Wajah yang diam total = foto di stand
2. **Large Erratic Movements** - Gerakan besar tidak teratur = foto digoyang
3. **Uniform Large Movement** - Gerakan besar seragam = HP/tablet digerakkan
4. **Flat Surface Detection** - Ukuran stabil dengan posisi berubah = foto datar
5. **Micro-movements Pattern** - Wajah asli memiliki gerakan mikro dari napas/denyut jantung

**Perubahan Optimasi:**

- Frame sebelumnya: 5 frame untuk analisis (lebih lambat)
- Frame sekarang: 4 frame untuk analisis (lebih cepat, tetap akurat)

### 7.2 Parameter Liveness (Balanced Mode - Optimized)

```cpp
// Anti-spoofing: Liveness detection thresholds - BALANCED MODE
#define LIVENESS_CHECK_COUNT 4            // Jumlah frame yang diperiksa (optimized untuk response cepat)
#define LIVENESS_MIN_MICRO_MOVEMENT 1     // Minimal gerakan mikro (pixel)
#define LIVENESS_MAX_MICRO_MOVEMENT 20    // Maksimal gerakan mikro alami
#define LIVENESS_PHOTO_THRESHOLD 30       // Gerakan di atas ini = curiga foto
#define LIVENESS_CONSISTENCY_REQUIRED 2   // Perlu 2 pola gerakan mikro konsisten
#define LIVENESS_SIZE_STABILITY_MAX 5     // Foto memiliki ukuran sangat stabil
```

### 7.3 Algoritma Liveness Detection (4-Frame Optimized)

```cpp
bool checkLiveness() {
    // Butuh minimal 4 frame history (optimized dari 5)
    if (faceHistoryCount < LIVENESS_CHECK_COUNT) {
        Serial.printf("⏳ Liveness: Need %d frames, have %d\n",
                      LIVENESS_CHECK_COUNT, faceHistoryCount);
        return false;
    }

    int microMovementCount = 0;  // Natural tiny movements
    int largeMovementCount = 0;  // Suspicious large movements
    int zeroMovementCount = 0;   // Completely static

    // Analyze movement patterns across all frames (3 comparisons untuk 4 frame)
    for (int i = 0; i < LIVENESS_CHECK_COUNT - 1; i++) {
        int posChange = abs(faceHistory[i+1].cx - faceHistory[i].cx) +
                        abs(faceHistory[i+1].cy - faceHistory[i].cy);
        int sizeChange = abs(faceHistory[i+1].width - faceHistory[i].width) +
                         abs(faceHistory[i+1].height - faceHistory[i].height);

        // Categorize movement type
        if (posChange == 0 && sizeChange == 0) {
            zeroMovementCount++;  // Completely static
        } else if (posChange <= LIVENESS_MAX_MICRO_MOVEMENT) {
            microMovementCount++; // Natural human micro-movements
        } else if (posChange > LIVENESS_PHOTO_THRESHOLD) {
            largeMovementCount++; // Suspicious - photo being moved
        }
    }

    // ========================================
    // ANTI-SPOOFING CHECKS (5-Check System)
    // ========================================

    // CHECK 1: Completely static = printed photo on stand
    if (zeroMovementCount >= validComparisons - 1) {
        Serial.println("🚫 REJECTED: Face completely static");
        return false;
    }

    // CHECK 2: Large erratic movements = photo being shaken
    if (largeMovementCount >= 2) {
        Serial.println("🚫 REJECTED: Large erratic movements");
        return false;
    }

    // CHECK 3: Very uniform large movement = phone/tablet being moved
    if (avgPosChange > LIVENESS_PHOTO_THRESHOLD && posChangeVariance < 5) {
        Serial.println("🚫 REJECTED: Uniform large movement");
        return false;
    }

    // CHECK 4: Face size too stable = flat photo surface
    if (avgSizeChange == 0 && avgPosChange > 10) {
        Serial.println("🚫 REJECTED: Size too stable - flat photo");
        return false;
    }

    // CHECK 5: Need natural micro-movements pattern
    if (microMovementCount < LIVENESS_CONSISTENCY_REQUIRED) {
        Serial.println("🚫 REJECTED: Insufficient micro-movements");
        return false;
    }

    Serial.println("✅ LIVENESS PASSED: Natural movement pattern detected");
    return true;
}
```

### 7.4 Diagram Alur Liveness Check (5-Check System)

```
┌─────────────────────────────────────┐
│     Face Detected (5 frames)        │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│   Analyze Movement Patterns         │
│   For each frame pair:              │
│   - Calculate position change       │
│   - Calculate size change           │
│   - Categorize: zero/micro/large    │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│                    5 ANTI-SPOOFING CHECKS                   │
├─────────────────────────────────────────────────────────────┤
│ CHECK 1: Completely Static?                                 │
│   ➜ YES = 🚫 REJECTED (foto di stand)                       │
├─────────────────────────────────────────────────────────────┤
│ CHECK 2: Large Erratic Movements ≥ 2?                       │
│   ➜ YES = 🚫 REJECTED (foto digoyang)                       │
├─────────────────────────────────────────────────────────────┤
│ CHECK 3: Uniform Large Movement?                            │
│   ➜ YES = 🚫 REJECTED (HP/tablet digerakkan)                │
├─────────────────────────────────────────────────────────────┤
│ CHECK 4: Size Stable + Position Change?                     │
│   ➜ YES = 🚫 REJECTED (foto datar)                          │
├─────────────────────────────────────────────────────────────┤
│ CHECK 5: Micro-movements ≥ 2?                               │
│   ➜ NO = 🚫 REJECTED (bukan wajah hidup)                    │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│    ✅ LIVENESS PASSED               │
│    Natural movement pattern OK      │
└─────────────────────────────────────┘
```

### 7.5 Contoh Output Serial Monitor (Liveness Analysis)

**Wajah Asli (PASSED):**

```
👤 Face at (127,134) size 112x147 [5/5 frames]
🔍 Match 6/3: thidayat (confidence: 0.91)
📊 LIVENESS ANALYSIS:
   Avg pos change: 13, Avg size change: 10
   Micro-movements: 3/2, Large movements: 0, Zero movements: 0
   Position variance: 15 (min:8, max:23)
✅ LIVENESS PASSED: Natural movement pattern detected
========================================
✅ ACCESS GRANTED: thidayat
   Confidence: 0.91 (threshold: 0.88)
   Consecutive matches: 6
   Liveness: PASSED
========================================
```

**Foto Digoyang (REJECTED):**

```
👤 Face at (150,120) size 100x130 [5/5 frames]
🔍 Match 5/3: user1 (confidence: 0.95)
📊 LIVENESS ANALYSIS:
   Avg pos change: 35, Avg size change: 2
   Micro-movements: 1/2, Large movements: 3, Zero movements: 0
   Position variance: 45 (min:5, max:50)
🚫 REJECTED: Large erratic movements detected - likely photo being moved
🚫 LIVENESS FAILED - Possible photo/spoof attack!
```

**Foto Statis (REJECTED):**

```
👤 Face at (100,100) size 80x100 [5/5 frames]
🔍 Match 5/3: user1 (confidence: 0.97)
📊 LIVENESS ANALYSIS:
   Avg pos change: 0, Avg size change: 0
   Micro-movements: 0/2, Large movements: 0, Zero movements: 4
   Position variance: 0 (min:0, max:0)
🚫 REJECTED: Face completely static - likely printed photo on stand
🚫 LIVENESS FAILED - Possible photo/spoof attack!
```

---

## 8. MANAJEMEN USER DAN DATABASE

### 8.1 Penyimpanan Data di ESP32

Data wajah disimpan di **SPIFFS** (SPI Flash File System) dalam file `/fr.bin`:

```cpp
// Struktur data enrolled face
struct enrolled_face_t {
    int id;                    // ID internal
    char name[17];             // Nama user (max 16 karakter + null)
    float embedding[512];      // Face embedding vector (512 dimensi)
    uint8_t ctrl[2];           // Control bytes (0x14, 0x08) untuk validasi
};
```

### 8.2 Penyimpanan Data di Flutter (Hive)

```dart
// Box untuk menyimpan data user
Hive.box<User>('users')

// Box untuk menyimpan activity log
Hive.box<Activity>('activities')

// Box untuk menyimpan settings ESP32
Hive.box('esp32_settings')
```

### 8.3 Sinkronisasi Data

Flutter app sebagai **Master** data user:

1. User ditambahkan/diedit di Flutter app
2. Data disinkronkan ke ESP32 via `/api/users` endpoint
3. ESP32 menyimpan face embedding di SPIFFS

### 8.4 Default Users (Sample Data)

```dart
// 5 sample users yang dibuat saat pertama kali install
userBox.addAll([
  User(id: 1, nama: 'Roqhim', jabatan: 'Sales', departemen: 'Sales', ...),
  User(id: 2, nama: 'Ikhsan', jabatan: 'Finance', departemen: 'Finance', ...),
  User(id: 3, nama: 'Icha', jabatan: 'Accountant', departemen: 'Akunting', ...),
  User(id: 4, nama: 'Adi', jabatan: 'HR Manager', departemen: 'HR', ...),
  User(id: 5, nama: 'Rio', jabatan: 'Programmer', departemen: 'IT', ...),
]);
```

---

## 9. DIAGRAM ALUR SISTEM

### 9.1 Use Case Diagram

```
                    ┌─────────────────────────────────────────┐
                    │           SISTEM AKSES PINTU            │
                    │         FACE RECOGNITION                │
                    └─────────────────────────────────────────┘
                                      │
          ┌───────────────────────────┼───────────────────────────┐
          │                           │                           │
          ▼                           ▼                           ▼
    ┌───────────┐             ┌───────────────┐           ┌──────────────┐
    │   Admin   │             │   Karyawan    │           │    ESP32     │
    └─────┬─────┘             └───────┬───────┘           └──────┬───────┘
          │                           │                          │
          │ ┌─────────────────┐       │                          │
          ├─►Manage Users     │       │                          │
          │ └─────────────────┘       │                          │
          │ ┌─────────────────┐       │                          │
          ├─►Enroll Face      │       │                          │
          │ └─────────────────┘       │                          │
          │ ┌─────────────────┐       │                          │
          ├─►View Logs        │       │ ┌─────────────────┐      │
          │ └─────────────────┘       ├─►Face Recognition │──────┤
          │ ┌─────────────────┐       │ └─────────────────┘      │
          ├─►Configure WiFi   │       │ ┌─────────────────┐      │
          │ └─────────────────┘       ├─►Unlock Door      │──────┤
          │ ┌─────────────────┐       │ └─────────────────┘      │
          └─►Unlock Door      │───────┘                          │
            └─────────────────┘                                  │
                                                                 │
                                      ┌──────────────────────────┘
                                      │
                                      ▼
                              ┌───────────────┐
                              │  Relay/Door   │
                              └───────────────┘
```

### 9.2 Sequence Diagram - Face Recognition

```
┌──────────┐    ┌─────────────┐    ┌──────────────┐    ┌──────────┐
│ Karyawan │    │   Kamera    │    │    ESP32     │    │   Relay  │
└────┬─────┘    └──────┬──────┘    └──────┬───────┘    └────┬─────┘
     │                 │                  │                 │
     │ Hadapkan wajah  │                  │                 │
     │────────────────►│                  │                 │
     │                 │ Capture frame    │                 │
     │                 │─────────────────►│                 │
     │                 │                  │                 │
     │                 │                  │ Face Detection  │
     │                 │                  │◄───────────────►│
     │                 │                  │                 │
     │                 │                  │ Face Recognition│
     │                 │                  │◄───────────────►│
     │                 │                  │                 │
     │                 │                  │ Confidence Check│
     │                 │                  │ (>= 0.93)       │
     │                 │                  │                 │
     │                 │                  │ Consecutive     │
     │                 │                  │ Match Check (3x)│
     │                 │                  │                 │
     │                 │                  │ Liveness Check  │
     │                 │                  │                 │
     │                 │                  │ Cooldown Check  │
     │                 │                  │                 │
     │                 │                  │ ACCESS GRANTED  │
     │                 │                  │────────────────►│
     │                 │                  │                 │ Unlock
     │◄────────────────────────────────────────────────────│
     │   Door Opens (3 seconds)          │                 │
     │                 │                  │                 │
     │                 │                  │                 │ Lock
     │◄────────────────────────────────────────────────────│
     │   Door Closes                     │                 │
```

### 9.3 Activity Diagram - Enrollment Wajah

```
          ┌─────────────────┐
          │     START       │
          └────────┬────────┘
                   │
                   ▼
          ┌─────────────────┐
          │ Admin buka app  │
          │ Flutter         │
          └────────┬────────┘
                   │
                   ▼
          ┌─────────────────┐
          │ Pilih "Add User"│
          └────────┬────────┘
                   │
                   ▼
          ┌─────────────────┐
          │ Input nama user │
          │ dan data lainnya│
          └────────┬────────┘
                   │
                   ▼
          ┌─────────────────┐
          │ Klik "Start     │
          │ Live Enrollment"│
          └────────┬────────┘
                   │
                   ▼
          ┌─────────────────┐
          │ ESP32 mulai     │
          │ enrollment mode │
          └────────┬────────┘
                   │
                   ▼
    ┌──────────────────────────────┐
    │   Loop: Step 1-3             │
    │   ┌─────────────────────┐    │
    │   │ User hadapkan wajah │    │
    │   │ ke kamera ESP32     │    │
    │   └──────────┬──────────┘    │
    │              │               │
    │              ▼               │
    │   ┌─────────────────────┐    │
    │   │ Detect & Capture    │    │
    │   │ face embedding      │    │
    │   └──────────┬──────────┘    │
    │              │               │
    │              ▼               │
    │   ┌─────────────────────┐    │
    │   │ Save to SPIFFS      │    │
    │   │ /fr.bin             │    │
    │   └──────────┬──────────┘    │
    │              │               │
    └──────────────┼───────────────┘
                   │
                   ▼
          ┌─────────────────┐
          │ Enrollment      │
          │ Complete!       │
          └────────┬────────┘
                   │
                   ▼
          ┌─────────────────┐
          │ Optional: Add   │
          │ Profile Photo   │
          └────────┬────────┘
                   │
                   ▼
          ┌─────────────────┐
          │ Save user data  │
          │ to Hive DB      │
          └────────┬────────┘
                   │
                   ▼
          ┌─────────────────┐
          │      END        │
          └─────────────────┘
```

---

## 10. KONFIGURASI JARINGAN

### 10.1 Mode WiFi

**Mode 1: Station Mode (Primary)**

- ESP32 terhubung ke router WiFi yang ada
- IP Address dinamis dari DHCP atau static
- Ideal untuk penggunaan normal

**Mode 2: Access Point Mode (Fallback)**

- ESP32 membuat hotspot WiFi sendiri
- SSID: `Skripsi 21300015`
- Password: `123456789`
- IP Address: `192.168.4.1`
- Digunakan saat konfigurasi awal atau router tidak tersedia

### 10.2 Konfigurasi Default

```cpp
// Station Mode
DEFAULT_WIFI_SSID     = "AVARA HOUSE_EXT"
DEFAULT_WIFI_PASSWORD = "rioavaradudut2010"
WIFI_CONNECT_TIMEOUT  = 15000 ms (15 detik)

// Access Point Mode
AP_SSID     = "Skripsi 21300015"
AP_PASSWORD = "123456789"
```

### 10.3 Port Configuration

| Port | Protocol   | Service                          |
| ---- | ---------- | -------------------------------- |
| 80   | HTTP (TCP) | REST API via AsyncWebServer      |
| 81   | HTTP (TCP) | MJPEG Live Stream via WiFiServer |

### 10.4 CORS Configuration

```cpp
DefaultHeaders::Instance().addHeader("Access-Control-Allow-Origin", "*");
DefaultHeaders::Instance().addHeader("Access-Control-Allow-Methods",
                                      "GET, POST, PUT, DELETE, OPTIONS");
DefaultHeaders::Instance().addHeader("Access-Control-Allow-Headers",
                                      "Content-Type");
```

### 10.5 Alur Koneksi WiFi

```
┌─────────────────────────────────────────┐
│              ESP32 Boot                 │
└────────────────────┬────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────┐
│   Load WiFi config dari Preferences     │
│   (SSID, Password)                      │
└────────────────────┬────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────┐
│   Try connect ke Station Mode           │
│   WiFi.begin(ssid, password)            │
└────────────────────┬────────────────────┘
                     │
              ┌──────┴──────┐
              │             │
        Connected    Timeout (15s)
              │             │
              ▼             ▼
┌─────────────────┐  ┌─────────────────────┐
│ Station Mode    │  │ Start Access Point  │
│ Active          │  │ Mode (Fallback)     │
│                 │  │                     │
│ IP: DHCP        │  │ SSID: Skripsi 21300015
│                 │  │ IP: 192.168.4.1     │
└─────────────────┘  └─────────────────────┘
```

---

## 11. SERIAL MONITOR LOG (CONTOH OUTPUT)

### 11.1 Log Inisialisasi Sistem (Boot)

```
=== ESP32-S3 FACE RECOGNITION DOOR ACCESS ===
ELOQUENT METHOD - NO SD CARD
Initial Free Heap: 282456 bytes
Initial Free PSRAM: 8388608 bytes

1. Initializing Camera...
Camera initialized successfully
Free Heap after Camera init: 198432 bytes

2. Initializing Face Recognition...
Face recognition initialized
Free Heap after Recognition init: 178256 bytes

3. Initializing WiFi...
Loaded WiFi config - SSID: AVARA HOUSE_EXT
Attempting to connect to WiFi: AVARA HOUSE_EXT
..............
WiFi connected successfully!
IP Address: 192.168.0.128
Free Heap after WiFi init: 165892 bytes

4. Setting up Web Server...
Web server started
Free Heap after Web Server init: 158432 bytes

5. Starting MJPEG Stream Server...
[STREAM] MJPEG stream server started on port 81
Free Heap after Stream Server init: 152768 bytes

=== SYSTEM READY ===
WiFi Mode: STATION (Connected to Router)
SSID: AVARA HOUSE_EXT
IP Address: 192.168.0.128
MJPEG Stream: http://192.168.0.128:81/
Total Users: 3
Final Free Heap: 152768 bytes
Final Free PSRAM: 4194304 bytes
```

### 11.2 Log Scanning Wajah (Periodic Status)

```
🔍 Scanning active | Free heap: 152456 bytes | Users: 3
🔍 Scanning active | Free heap: 152128 bytes | Users: 3
🔍 Scanning active | Free heap: 152456 bytes | Users: 3
```

### 11.3 Log Face Detection (Wajah Terdeteksi)

```
👤 Face at (120,115) size 85x92 [1/4 frames]
👤 Face at (118,117) size 86x91 [2/4 frames]
👤 Face at (121,114) size 84x93 [3/4 frames]
👤 Face at (119,116) size 85x92 [4/4 frames]
```

### 11.4 Log AKSES DIIJINKAN (ACCESS GRANTED)

**Skenario: Pengguna "Taufik" berhasil dikenali dan akses diberikan**

```
👤 Face at (120,115) size 85x92 [1/4 frames]
🔍 Match 1/3: Taufik (confidence: 0.95)
👤 Face at (118,117) size 86x91 [2/4 frames]
🔍 Match 2/3: Taufik (confidence: 0.96)
👤 Face at (121,114) size 84x93 [3/4 frames]
🔍 Match 3/3: Taufik (confidence: 0.95)
👤 Face at (119,116) size 85x92 [4/4 frames]
📊 Liveness check: pos_change=8 (min:3, max:50), size_change=4 (min:2)
========================================
✅ ACCESS GRANTED: Taufik
   Confidence: 0.95 (threshold: 0.88)
   Consecutive matches: 3
   Liveness: PASSED
========================================
Door unlocked for: Taufik
LOG: Taufik - ACCESS_GRANTED - Success: YES - Confidence: 0.95
Door locked automatically
```

### 11.5 Log AKSES DITOLAK - Confidence Rendah (DENIED_LOW_CONFIDENCE)

**Skenario: Wajah mirip tapi confidence di bawah threshold 88%**

```
👤 Face at (125,110) size 80x88 [1/4 frames]
🔍 Match 1/3: Roqhim (confidence: 0.87)
👤 Face at (123,112) size 81x87 [2/4 frames]
🔍 Match 2/3: Roqhim (confidence: 0.85)
👤 Face at (126,109) size 79x89 [3/4 frames]
❌ REJECTED: Low confidence 0.85 < 0.88 for Roqhim
LOG: Roqhim - DENIED_LOW_CONFIDENCE - Success: NO - Confidence: 0.85
```

### 11.6 Log AKSES DITOLAK - Liveness Gagal (DENIED_LIVENESS_FAIL)

**Skenario: Terdeteksi menggunakan foto (serangan spoofing)**

```
👤 Face at (120,115) size 85x92 [1/4 frames]
🔍 Match 1/3: Taufik (confidence: 0.97)
👤 Face at (120,115) size 85x92 [2/4 frames]
🔍 Match 2/3: Taufik (confidence: 0.97)
👤 Face at (120,115) size 85x92 [3/4 frames]
🔍 Match 3/3: Taufik (confidence: 0.97)
👤 Face at (120,115) size 85x92 [4/4 frames]
📊 Liveness check: pos_change=0 (min:3, max:50), size_change=0 (min:2)
🚫 STATIC FACE DETECTED - Move slightly to prove liveness
🚫 LIVENESS FAILED - Possible photo/spoof attack!
LOG: Taufik - DENIED_LIVENESS_FAIL - Success: NO - Confidence: 0.97
```

### 11.7 Log AKSES DITOLAK - Wajah Tidak Terdaftar (DENIED_NOT_ENROLLED)

**Skenario: Wajah terdeteksi tapi tidak ada di database**

```
👤 Face at (115,120) size 90x95 [1/4 frames]
👤 Face at (117,118) size 89x94 [2/4 frames]
👤 Face at (116,121) size 91x96 [3/4 frames]
👤 Face at (116,119) size 90x95 [4/4 frames]
❌ Face not recognized - not enrolled
LOG: Unknown - DENIED_NOT_ENROLLED - Success: NO - Confidence: 0.00
```

### 11.8 Log AKSES DITOLAK - Cooldown Aktif

**Skenario: User yang sama mencoba akses dalam 5 detik**

```
👤 Face at (120,115) size 85x92 [1/4 frames]
🔍 Match 1/3: Taufik (confidence: 0.95)
👤 Face at (118,117) size 86x91 [2/4 frames]
🔍 Match 2/3: Taufik (confidence: 0.96)
👤 Face at (121,114) size 84x93 [3/4 frames]
🔍 Match 3/3: Taufik (confidence: 0.95)
👤 Face at (119,116) size 85x92 [4/4 frames]
📊 Liveness check: pos_change=8 (min:3, max:50), size_change=4 (min:2)
⏳ Cooldown active for Taufik (3.2 sec remaining)
```

### 11.9 Log Enrollment Wajah Baru

**Skenario: Admin mendaftarkan wajah baru via aplikasi Flutter**

```
[API] POST /api/enroll/start
Starting enrollment for: Budi
Enrollment step 1/3 completed for Budi
Enrollment step 2/3 completed for Budi
Enrollment step 3/3 completed for Budi
Enrollment completed for Budi
System status updated - Users: 4
```

### 11.10 Log MJPEG Streaming

**Skenario: User membuka live feed di aplikasi Flutter**

```
[STREAM] New MJPEG client connected
[API] Live feed STARTED - Recognition PAUSED
...
[STREAM] MJPEG client disconnected
📷 Live feed timeout - Recognition RESUMED
```

### 11.11 Log Konfigurasi WiFi

**Skenario: Admin mengubah konfigurasi WiFi via aplikasi**

```
[API] Scanning WiFi networks...
[API] Found 8 networks
[API] WiFi config received - SSID: NEW_NETWORK_NAME
Saved WiFi config - SSID: NEW_NETWORK_NAME
[API] Restarting ESP32 to apply new WiFi config...
```

### 11.12 Log Delete User

**Skenario: Admin menghapus user dari sistem**

```
[API] DELETE user request - id: 2, name: Ikhsan
[API] Deleting user: Ikhsan (id: 2)
System status updated - Users: 3
```

### 11.13 Log Clear All Faces

**Skenario: Admin menghapus semua data wajah**

```
[API] Clearing ALL enrolled faces...
[API] Deleted /fr.bin
[API] All faces cleared. Users now: 0
System status updated - Users: 0
```

### 11.14 Ringkasan Kode Status Log

| Kode Status           | Deskripsi                             | Success |
| --------------------- | ------------------------------------- | ------- |
| ACCESS_GRANTED        | Akses diijinkan, pintu terbuka        | ✅ YES  |
| DENIED_LOW_CONFIDENCE | Confidence di bawah threshold (0.88)  | ❌ NO   |
| DENIED_LIVENESS_FAIL  | Terdeteksi sebagai foto/gambar statis | ❌ NO   |
| DENIED_NOT_ENROLLED   | Wajah tidak terdaftar di sistem       | ❌ NO   |

### 11.15 Format Log Activity

```
LOG: [USERNAME] - [STATUS] - Success: [YES/NO] - Confidence: [0.00-1.00]
```

**Contoh:**

```
LOG: Taufik - ACCESS_GRANTED - Success: YES - Confidence: 0.95
LOG: Unknown - DENIED_NOT_ENROLLED - Success: NO - Confidence: 0.00
LOG: Roqhim - DENIED_LOW_CONFIDENCE - Success: NO - Confidence: 0.85
LOG: Taufik - DENIED_LIVENESS_FAIL - Success: NO - Confidence: 0.97
```

---

## LAMPIRAN

### A. Daftar File Source Code

| File                      | Lokasi        | Deskripsi                |
| ------------------------- | ------------- | ------------------------ |
| main.cpp                  | src/          | Firmware ESP32 utama     |
| camera_pins.h             | include/      | Pin mapping kamera       |
| platformio.ini            | /             | Konfigurasi PlatformIO   |
| main.dart                 | lib/          | Entry point Flutter app  |
| home_screen.dart          | lib/screens/  | Halaman utama            |
| add_user_screen.dart      | lib/screens/  | Tambah user & enrollment |
| manage_user_screen.dart   | lib/screens/  | Manajemen user           |
| door_activity_screen.dart | lib/screens/  | Activity log             |
| wifi_config_screen.dart   | lib/screens/  | Konfigurasi WiFi         |
| esp32_service.dart        | lib/services/ | HTTP client ESP32        |
| mjpeg_viewer.dart         | lib/widgets/  | MJPEG stream widget      |
| user.dart                 | lib/models/   | Model User               |
| activity.dart             | lib/models/   | Model Activity           |
| pubspec.yaml              | /             | Flutter dependencies     |

### B. Ringkasan Teknis

| Parameter                  | Nilai                        |
| -------------------------- | ---------------------------- |
| Resolusi Kamera            | 240 x 240 pixel              |
| Recognition Threshold      | 0.88 (88%)                   |
| Consecutive Match Required | 3 frame                      |
| Liveness Check Frames      | 5 frame                      |
| Cooldown Same User         | 5 detik                      |
| Door Unlock Duration       | 3 detik                      |
| Enrollment Steps           | 3 langkah                    |
| Max Activity Logs (RAM)    | 10 entries (circular buffer) |
| SD Card Activity Logs      | Unlimited (persistent)       |
| MJPEG Frame Rate           | ~30 FPS                      |
| WiFi Connect Timeout       | 15 detik                     |
| Face Embedding Size        | 512 dimensi (float)          |
| Profile Image Max Size     | 200 KB (auto-compressed)     |
| Profile Image Resolution   | 400 x 400 pixel (max)        |

### C. Build Information

```
Platform: Espressif32 v6.12.0
Framework: Arduino
Board: Freenove ESP32-S3 WROOM
Flash: 8MB
PSRAM: 8MB
SD Card: 16GB (SD_MMC interface)
RAM Usage: 32.7%
Flash Usage: 98.8%
Flutter SDK: >=3.8.0
APK Size: ~52 MB
```

---

## 12. SD CARD INTEGRATION

### 12.1 Tujuan Penggunaan SD Card

SD Card digunakan untuk mengurangi beban memori ESP32 dan menyimpan data secara persisten:

| Fungsi         | Tanpa SD Card      | Dengan SD Card             |
| -------------- | ------------------ | -------------------------- |
| Activity Logs  | RAM (max 50 entry) | File persisten (unlimited) |
| Profile Images | Tidak tersimpan    | /profiles/{username}.jpg   |
| System Boot    | Log hilang         | Log tetap ada              |
| Memory Usage   | Tinggi             | Minimal (streaming)        |

### 12.2 Pin Configuration SD Card (Freenove ESP32-S3)

```cpp
// SD Card Pins for ESP32-S3 WROOM (SDMMC interface)
#define SD_CMD_PIN 38
#define SD_CLK_PIN 39
#define SD_D0_PIN  40
#define SD_D1_PIN  41
#define SD_D2_PIN  42
#define SD_D3_PIN  1
```

**Catatan**: Pin SD Card TIDAK konflik dengan pin kamera karena menggunakan GPIO yang berbeda.

### 12.3 Struktur File SD Card

```
SD Card (16GB)
├── /logs/
│   └── access_log.csv          # Activity log persisten
└── /profiles/
    ├── thidayat.jpg            # Profile image user
    ├── admin.jpg
    └── {username}.jpg          # Auto-generated per user
```

### 12.4 Format Activity Log (CSV)

```csv
timestamp,username,action,success,confidence
1733480400,thidayat,ACCESS_GRANTED,1,0.91
1733480350,thidayat,DENIED_LIVENESS_FAIL,0,0.97
1733480300,unknown,DENIED_LOW_CONFIDENCE,0,0.65
```

| Field      | Type   | Deskripsi                           |
| ---------- | ------ | ----------------------------------- |
| timestamp  | ulong  | Unix timestamp (seconds since boot) |
| username   | string | Nama user yang terdeteksi           |
| action     | string | Jenis aksi (lihat tabel di bawah)   |
| success    | int    | 1 = granted, 0 = denied             |
| confidence | float  | Nilai confidence recognition        |

### 12.5 Jenis Action Log

| Action                | Success | Deskripsi                                    |
| --------------------- | ------- | -------------------------------------------- |
| ACCESS_GRANTED        | 1       | Akses diberikan, pintu terbuka               |
| DENIED_LIVENESS_FAIL  | 0       | Ditolak karena liveness detection gagal      |
| DENIED_LOW_CONFIDENCE | 0       | Ditolak karena confidence di bawah threshold |
| DENIED_NOT_ENROLLED   | 0       | Wajah tidak terdaftar dalam sistem           |
| DENIED_COOLDOWN       | 0       | User dalam periode cooldown                  |

### 12.6 Profile Image Upload Flow

```
┌─────────────────────┐
│ Flutter App         │
│ 1. Pilih foto       │
│ 2. Auto-resize      │
│    (max 400x400)    │
│ 3. Compress JPEG    │
│    (max 200KB)      │
└─────────┬───────────┘
          │ HTTP POST
          │ Multipart
          ▼
┌─────────────────────┐
│ ESP32-S3            │
│ 4. Stream langsung  │
│    ke SD Card       │
│ 5. NO RAM buffer    │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ SD Card             │
│ /profiles/user.jpg  │
└─────────────────────┘
```

### 12.7 API Endpoints SD Card

| Endpoint              | Method | Fungsi                           |
| --------------------- | ------ | -------------------------------- |
| /api/sdcard/status    | GET    | Status SD Card (size, free)      |
| /api/profile/upload   | POST   | Upload profile image (multipart) |
| /api/profile/download | GET    | Download profile image           |
| /api/profile/delete   | DELETE | Hapus profile image              |
| /api/profile/list     | GET    | List semua profile images        |
| /api/logs             | GET    | Ambil activity logs dari SD      |
| /api/logs/clear       | DELETE | Hapus semua logs                 |

### 12.8 Contoh Response API SD Card

**GET /api/sdcard/status**

```json
{
  "available": true,
  "totalSize": 14910,
  "usedSize": 128,
  "freeSize": 14782,
  "unit": "MB"
}
```

**GET /api/logs?limit=5**

```json
{
  "source": "sdcard",
  "count": 5,
  "logs": [
    {
      "username": "thidayat",
      "status": "ACCESS_GRANTED",
      "success": true,
      "confidence": 0.91,
      "timestamp": 1733480400
    }
  ]
}
```

### 12.9 Memory Optimization dengan SD Card

| Metric                | Sebelum SD Card | Sesudah SD Card |
| --------------------- | --------------- | --------------- |
| Free Heap (boot)      | ~142 KB         | ~149 KB         |
| Activity Log Buffer   | 50 x struct     | 10 x struct     |
| Profile Images in RAM | N/A             | 0 (streaming)   |
| Max Concurrent Users  | ~50             | >100            |
| Log Persistence       | Tidak           | Ya              |

### 12.10 Kode Inisialisasi SD Card

```cpp
// ========================================
// SD CARD INITIALIZATION
// ========================================
#include <SD_MMC.h>

#define SD_LOGS_DIR "/logs"
#define SD_PROFILES_DIR "/profiles"
#define SD_LOG_FILE "/logs/access_log.csv"

bool sdCardReady = false;

void initSDCard() {
    Serial.println("1.5. Initializing SD Card...");

    // Initialize SD_MMC with 1-bit mode for Freenove board
    if (SD_MMC.begin("/sdcard", true)) {  // true = 1-bit mode
        sdCardReady = true;
        uint64_t cardSize = SD_MMC.cardSize() / (1024 * 1024);
        Serial.printf("✓ SD Card initialized successfully\n");
        Serial.printf("   Card Size: %llu MB\n", cardSize);

        // Create directories
        if (!SD_MMC.exists(SD_LOGS_DIR)) SD_MMC.mkdir(SD_LOGS_DIR);
        if (!SD_MMC.exists(SD_PROFILES_DIR)) SD_MMC.mkdir(SD_PROFILES_DIR);
    } else {
        Serial.println("⚠ SD Card initialization failed");
        sdCardReady = false;
    }
}
```

### 12.11 Contoh Serial Monitor dengan SD Card

```
=== ESP32-S3 FACE RECOGNITION DOOR ACCESS ===
ELOQUENT METHOD - SD CARD LOGGING ENABLED
Initial Free Heap: 241996 bytes
Initial Free PSRAM: 8386035 bytes

1. Initializing Camera...
Free Heap after Camera init: 221728 bytes

1.5. Initializing SD Card...
✓ SD Card initialized successfully
   Card Size: 14910 MB
   Log file exists, will append
Free Heap after SD init: 220396 bytes

2. Initializing Face Recognition...
[FR] Enrolled face thidayat
[FR] Enrolled 3 faces in total
Free Heap after Recognition init: 209420 bytes

...

👤 Face at (125,132) size 111x146 [4/4 frames]
🔍 Match 3/3: thidayat (confidence: 0.91)
📊 LIVENESS ANALYSIS:
   Avg pos change: 13, Avg size change: 10
   Micro-movements: 2/2, Large movements: 0, Zero movements: 0
   Position variance: 15 (min:8, max:23)
✅ LIVENESS PASSED: Natural movement pattern detected
========================================
✅ ACCESS GRANTED: thidayat
   Confidence: 0.91 (threshold: 0.88)
   Consecutive matches: 3
   Liveness: PASSED
========================================
Door unlocked for: thidayat
📝 SD LOG: thidayat - ACCESS_GRANTED - YES - 0.91
Door locked automatically
```

### 12.12 Flutter Profile Image Resize

```dart
/// Resize image to target size (max 200KB, 400x400 pixels)
static Future<File> _resizeImageForUpload(File imageFile, String username) async {
    // Read original image
    final bytes = await imageFile.readAsBytes();
    final originalImage = img.decodeImage(bytes);

    // Target: 400x400 max dimension, JPEG quality 85
    const int maxDimension = 400;
    const int targetQuality = 85;
    const int maxSizeBytes = 200 * 1024; // 200KB

    // Resize maintaining aspect ratio
    final resizedImage = img.copyResize(
        originalImage,
        width: newWidth,
        height: newHeight,
        interpolation: img.Interpolation.linear,
    );

    // Encode to JPEG, reduce quality if still too large
    var quality = targetQuality;
    List<int> jpegBytes = img.encodeJpg(resizedImage, quality: quality);

    while (jpegBytes.length > maxSizeBytes && quality > 30) {
        quality -= 10;
        jpegBytes = img.encodeJpg(resizedImage, quality: quality);
    }

    return resizedFile;
}
```

---

**Dokumen ini dibuat untuk keperluan dokumentasi teknis skripsi.**

**© 2025 Taufik Hidayat - 21300015**
