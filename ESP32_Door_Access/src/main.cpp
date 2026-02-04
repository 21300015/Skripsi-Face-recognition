/**
 * ESP32-S3 Face Recognition Door Access System - ELOQUENT METHOD
 * Memory-Optimized Implementation using EloquentEsp32cam
 *
 * FEATURES:
 * - Standalone door access control with face recognition
 * - Only live camera enrollment (no image uploads)
 * - SD Card for activity logs (offloads RAM)
 * - SPIFFS for face embeddings
 * - WiFi AP for Flutter app communication
 * - Door relay control (GPIO 21)
 * - MJPEG live stream on port 81
 *
 * STORAGE ARCHITECTURE:
 * - SD Card: Activity logs (persistent, unlimited storage)
 * - SPIFFS: Face embeddings (/fr.bin ~2KB per face)
 * - RAM: Minimal buffer (5 logs max before flush to SD)
 */

#include <Arduino.h>
#include <WiFi.h>
#include <AsyncTCP.h>
#include <ESPAsyncWebServer.h>
#include <SPIFFS.h>
#include <SD_MMC.h>
#include <Preferences.h>
#include <vector>
#include <set>
#include <eloquent_esp32cam.h>
#include <eloquent_esp32cam/face/detection.h>
#include <eloquent_esp32cam/face/recognition.h>
#include "camera_pins.h"

using eloq::camera;
using eloq::face::detection;
using eloq::face::recognition;

// ========================================
// SYSTEM CONFIGURATION
// ========================================
// WiFi Station Mode (Primary) - Default values, can be overridden via app
#define DEFAULT_WIFI_SSID "AVARA HOUSE_EXT"
#define DEFAULT_WIFI_PASSWORD "rioavaradudut2010"
#define WIFI_CONNECT_TIMEOUT 15000 // 15 seconds timeout

// WiFi AP Mode (Fallback)
#define AP_SSID "Skripsi 21300015"
#define AP_PASSWORD "123456789"

// Preferences storage
Preferences preferences;
String configuredSSID = "";
String configuredPassword = "";

// Activity log storage - MINIMAL RAM buffer, flush to SD card
#define MAX_RAM_LOGS 5 // Small buffer, flush to SD when full
#define MAX_SD_LOGS 50 // Maximum logs stored on SD card
#define SD_LOG_FILE "/access_logs.csv"
#define SD_PROFILES_DIR "/profiles" // Directory for user profile images
struct ActivityLog
{
    String username;
    String action;
    bool success;
    float confidence;
    unsigned long timestamp;
};
ActivityLog ramLogBuffer[MAX_RAM_LOGS];
int ramLogIndex = 0;
int ramLogCount = 0;
bool sdCardReady = false;
unsigned long bootTime = 0; // Track boot time for timestamps

// ========================================
// MJPEG STREAMING (WiFiServer - Lightweight)
// ========================================
#define PART_BOUNDARY "123456789000000000000987654321"
WiFiServer streamServer(81); // MJPEG stream on port 81

// handleMJPEGStream() defined after global variables

// ========================================
// ANTI-SPOOFING & RECOGNITION CONFIG
// ========================================
#define RECOGNITION_THRESHOLD 0.92f // Stricter threshold for better accuracy (improved from 0.88)
#define RECOGNITION_CONFIRM_COUNT 3 // Must match 3 times consecutively
#define SAME_USER_COOLDOWN 5000     // 5 seconds between same user access
#define DOOR_UNLOCK_DURATION 3000
#define DOOR_RELAY_PIN 21
#define STATUS_LED_PIN 2

// Anti-spoofing: Liveness detection thresholds - BALANCED MODE
// Designed to pass real faces easily while blocking photos
#define LIVENESS_CHECK_COUNT 4          // Need 4 frames for analysis (faster response)
#define LIVENESS_MIN_MICRO_MOVEMENT 1   // Very small movements allowed (breathing)
#define LIVENESS_MAX_MICRO_MOVEMENT 20  // Max micro-movement (natural head moves)
#define LIVENESS_PHOTO_THRESHOLD 30     // Movement above this = likely photo being moved
#define LIVENESS_CONSISTENCY_REQUIRED 2 // Need 2 consistent micro-movement patterns (reduced from 3)
#define LIVENESS_SIZE_STABILITY_MAX 5   // Photo has very stable size (flat surface)

// WiFi mode tracking
bool isStationMode = false;

// Anti-false-positive tracking
String lastConfirmedUser = "";
int consecutiveMatches = 0;
unsigned long lastAccessTime = 0;
String lastAccessUser = "";

// Liveness detection tracking
struct FacePosition
{
    int cx;     // Center X
    int cy;     // Center Y
    int width;  // Face width
    int height; // Face height
    bool valid;
};
FacePosition faceHistory[LIVENESS_CHECK_COUNT];
int faceHistoryIndex = 0;
int faceHistoryCount = 0;

// Global variables - MINIMAL RAM USAGE
AsyncWebServer server(80);
bool isDoorUnlocked = false;
unsigned long doorUnlockTime = 0;
bool enrollmentMode = false;
bool enrollmentJustCompleted = false;
bool liveFeedActive = false;           // Pause scanning when live feed is active
unsigned long liveFeedLastRequest = 0; // Track last live feed request
String lastEnrolledUser = "";
String currentEnrollmentUser = "";
int enrollmentSteps = 0;
const int REQUIRED_ENROLLMENT_STEPS = 3;

// System status structure - only essentials in RAM
struct
{
    bool cameraReady = false;
    bool recognitionReady = false;
    String lastRecognizedUser = "";
    float lastConfidence = 0.0;
    unsigned long lastActivity = 0;
    int totalUsers = 0;
} systemStatus;

// ========================================
// FUNCTION DECLARATIONS
// ========================================
bool initCamera();
bool initRecognition();
void initWiFi();
void initWiFiAP();
void setupWebServer();
void handleEnrollment();
void handleRecognition();
void handleMJPEGStream();
bool checkLiveness();
void resetLivenessTracking();
void unlockDoor(const String &userName);
void logActivity(const String &userName, const String &action, bool success, float confidence = 0.0);
void updateSystemStatus();
String getSystemInfo();

// ========================================
// MJPEG STREAMING FUNCTION
// ========================================
void handleMJPEGStream()
{
    // Check for new stream client
    WiFiClient client = streamServer.available();
    if (client)
    {
        Serial.println("[STREAM] New MJPEG client connected");
        liveFeedActive = true;
        liveFeedLastRequest = millis();

        // Send HTTP header
        client.println("HTTP/1.1 200 OK");
        client.println("Content-Type: multipart/x-mixed-replace; boundary=" PART_BOUNDARY);
        client.println("Access-Control-Allow-Origin: *");
        client.println("Cache-Control: no-cache");
        client.println("Connection: close");
        client.println();

        // Stream frames continuously while client is connected
        while (client.connected())
        {
            if (!camera.capture().isOk())
            {
                delay(10);
                continue;
            }

            // Send frame boundary and headers
            client.printf("\r\n--%s\r\n", PART_BOUNDARY);
            client.printf("Content-Type: image/jpeg\r\n");
            client.printf("Content-Length: %u\r\n\r\n", camera.frame->len);

            // Send frame data
            size_t written = client.write(camera.frame->buf, camera.frame->len);
            if (written != camera.frame->len)
            {
                Serial.println("[STREAM] Write error, client disconnected");
                break;
            }

            liveFeedLastRequest = millis();
            delay(33); // ~30 FPS
        }

        // Client disconnected
        Serial.println("[STREAM] MJPEG client disconnected");
        client.stop();
        liveFeedActive = false;
    }
}

// ========================================
// SETUP FUNCTION
// ========================================
void setup()
{
    delay(3000);
    Serial.begin(115200);
    Serial.println("\n=== ESP32-S3 FACE RECOGNITION DOOR ACCESS ===");
    Serial.println("ELOQUENT METHOD - SD CARD LOGGING ENABLED");
    bootTime = millis(); // Record boot time
    Serial.printf("Initial Free Heap: %d bytes\n", ESP.getFreeHeap());
    Serial.printf("Initial Free PSRAM: %d bytes\n", ESP.getFreePsram());

    // Initialize hardware pins
    pinMode(DOOR_RELAY_PIN, OUTPUT);
    pinMode(STATUS_LED_PIN, OUTPUT);
    digitalWrite(DOOR_RELAY_PIN, LOW);
    digitalWrite(STATUS_LED_PIN, LOW);

    // Step 1: Initialize Camera with optimal settings
    Serial.println("\n1. Initializing Camera...");
    if (!initCamera())
    {
        Serial.println("ERROR: Camera initialization failed!");
        return;
    }
    systemStatus.cameraReady = true;
    Serial.printf("Free Heap after Camera init: %d bytes\n", ESP.getFreeHeap());

    // Step 1.5: Initialize SD Card for logging
    Serial.println("\n1.5. Initializing SD Card...");
    SD_MMC.setPins(SD_CLK_PIN, SD_CMD_PIN, SD_D0_PIN); // Freenove S3 pins
    if (SD_MMC.begin("/sdcard", true))                 // 1-bit mode for compatibility
    {
        sdCardReady = true;
        Serial.println("✓ SD Card initialized successfully");
        Serial.printf("   Card Size: %llu MB\n", SD_MMC.cardSize() / (1024 * 1024));

        // Create/verify log file header if new
        if (!SD_MMC.exists(SD_LOG_FILE))
        {
            File logFile = SD_MMC.open(SD_LOG_FILE, FILE_WRITE);
            if (logFile)
            {
                logFile.println("timestamp,username,action,success,confidence");
                logFile.close();
                Serial.println("   Created new log file with header");
            }
        }
        else
        {
            Serial.println("   Log file exists, will append");
        }
    }
    else
    {
        sdCardReady = false;
        Serial.println("⚠ SD Card init failed - logging to RAM only (limited)");
    }
    Serial.printf("Free Heap after SD init: %d bytes\n", ESP.getFreeHeap());

    // Step 2: Initialize Face Recognition
    Serial.println("\n2. Initializing Face Recognition...");
    if (!initRecognition())
    {
        Serial.println("ERROR: Face Recognition initialization failed!");
        return;
    }
    systemStatus.recognitionReady = true;
    Serial.printf("Free Heap after Recognition init: %d bytes\n", ESP.getFreeHeap());

    // Step 3: Initialize WiFi (Station mode first, then AP fallback)
    Serial.println("\n3. Initializing WiFi...");
    initWiFi();
    Serial.printf("Free Heap after WiFi init: %d bytes\n", ESP.getFreeHeap());

    // Step 4: Setup Web Server (minimal endpoints)
    Serial.println("\n4. Setting up Web Server...");
    setupWebServer();
    Serial.printf("Free Heap after Web Server init: %d bytes\n", ESP.getFreeHeap());

    // Step 5: Start MJPEG Stream Server on port 81
    Serial.println("\n5. Starting MJPEG Stream Server...");
    streamServer.begin();
    Serial.println("[STREAM] MJPEG stream server started on port 81");
    Serial.printf("Free Heap after Stream Server init: %d bytes\n", ESP.getFreeHeap());

    updateSystemStatus();

    Serial.println("\n=== SYSTEM READY ===");
    if (isStationMode)
    {
        Serial.println("WiFi Mode: STATION (Connected to Router)");
        Serial.printf("SSID: %s\n", configuredSSID.c_str());
        Serial.printf("IP Address: %s\n", WiFi.localIP().toString().c_str());
        Serial.printf("MJPEG Stream: http://%s:81/\n", WiFi.localIP().toString().c_str());
    }
    else
    {
        Serial.println("WiFi Mode: ACCESS POINT (Fallback)");
        Serial.printf("AP SSID: %s\n", AP_SSID);
        Serial.printf("AP Password: %s\n", AP_PASSWORD);
        Serial.printf("IP Address: %s\n", WiFi.softAPIP().toString().c_str());
        Serial.printf("MJPEG Stream: http://%s:81/\n", WiFi.softAPIP().toString().c_str());
        Serial.println("\n📱 Connect your phone to this AP, then use the app to configure WiFi!");
    }
    Serial.printf("Total Users: %d\n", systemStatus.totalUsers);
    Serial.printf("Final Free Heap: %d bytes\n", ESP.getFreeHeap());
    Serial.printf("Final Free PSRAM: %d bytes\n", ESP.getFreePsram());

    digitalWrite(STATUS_LED_PIN, HIGH); // System ready indicator
}

// ========================================
// MAIN LOOP - OPTIMIZED FOR PERFORMANCE
// ========================================
void loop()
{
    // Handle MJPEG streaming (blocks while client is connected)
    handleMJPEGStream();

    // Handle door unlock timing
    if (isDoorUnlocked && millis() - doorUnlockTime > DOOR_UNLOCK_DURATION)
    {
        digitalWrite(DOOR_RELAY_PIN, LOW);
        isDoorUnlocked = false;
        Serial.println("Door locked automatically");
    }

    // Handle face recognition or enrollment (only when not streaming)
    if (systemStatus.cameraReady && systemStatus.recognitionReady && !liveFeedActive)
    {
        if (enrollmentMode)
        {
            handleEnrollment();
        }
        else
        {
            handleRecognition();
        }
    }

    delay(50); // Small delay between iterations
}

// ========================================
// INITIALIZATION FUNCTIONS
// ========================================
bool initCamera()
{
    // Use proven EloquentEsp32cam configuration
    camera.pinout.freenove_s3();
    camera.brownout.disable();
    camera.resolution.face(); // 240x240 - optimal for face recognition
    camera.quality.high();

    // Initialize camera with retry mechanism
    int attempts = 0;
    while (!camera.begin().isOk() && attempts < 5)
    {
        Serial.printf("Camera init attempt %d failed: %s\n", attempts + 1, camera.exception.toString().c_str());
        delay(1000);
        attempts++;
    }

    return attempts < 5;
}

bool initRecognition()
{
    // Configure detection for accuracy
    detection.accurate();
    detection.confidence(0.8); // Improved from 0.7 - stricter detection

    // Configure recognition threshold
    recognition.confidence(RECOGNITION_THRESHOLD);

    // Initialize recognition system
    if (!recognition.begin().isOk())
    {
        Serial.printf("Recognition init failed: %s\n", recognition.exception.toString().c_str());
        return false;
    }

    return true;
}

void loadWiFiConfig()
{
    // Load saved WiFi config from preferences
    preferences.begin("wifi", true); // Read-only
    configuredSSID = preferences.getString("ssid", DEFAULT_WIFI_SSID);
    configuredPassword = preferences.getString("password", DEFAULT_WIFI_PASSWORD);
    preferences.end();

    Serial.printf("Loaded WiFi config - SSID: %s\n", configuredSSID.c_str());
}

void saveWiFiConfig(const String &ssid, const String &password)
{
    preferences.begin("wifi", false); // Read-write
    preferences.putString("ssid", ssid);
    preferences.putString("password", password);
    preferences.end();

    configuredSSID = ssid;
    configuredPassword = password;

    Serial.printf("Saved WiFi config - SSID: %s\n", ssid.c_str());
}

void initWiFi()
{
    // Load saved WiFi configuration
    loadWiFiConfig();

    // Try to connect to configured WiFi Station mode first
    Serial.printf("Attempting to connect to WiFi: %s\n", configuredSSID.c_str());

    WiFi.mode(WIFI_STA);
    WiFi.begin(configuredSSID.c_str(), configuredPassword.c_str());

    unsigned long startAttempt = millis();

    while (WiFi.status() != WL_CONNECTED && millis() - startAttempt < WIFI_CONNECT_TIMEOUT)
    {
        Serial.print(".");
        delay(500);
    }

    if (WiFi.status() == WL_CONNECTED)
    {
        isStationMode = true;
        Serial.println("\nWiFi connected successfully!");
        Serial.printf("IP Address: %s\n", WiFi.localIP().toString().c_str());
    }
    else
    {
        // Failed to connect, start AP mode as fallback
        Serial.println("\nFailed to connect to WiFi. Starting Access Point...");
        initWiFiAP();
    }
}

void initWiFiAP()
{
    WiFi.mode(WIFI_AP);
    WiFi.softAP(AP_SSID, AP_PASSWORD);
    isStationMode = false;

    // Wait for AP to start
    delay(2000);

    Serial.printf("Access Point started: %s\n", AP_SSID);
    Serial.printf("IP address: %s\n", WiFi.softAPIP().toString().c_str());
}

// ========================================
// WEB SERVER SETUP - MINIMAL ENDPOINTS
// ========================================
void setupWebServer()
{
    // CORS headers for Flutter app
    DefaultHeaders::Instance().addHeader("Access-Control-Allow-Origin", "*");
    DefaultHeaders::Instance().addHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
    DefaultHeaders::Instance().addHeader("Access-Control-Allow-Headers", "Content-Type");

    // System status endpoint
    server.on("/api/status", HTTP_GET, [](AsyncWebServerRequest *request)
              {
        String status = "{";
        status += "\"camera_ready\":" + String(systemStatus.cameraReady ? "true" : "false") + ",";
        status += "\"recognition_ready\":" + String(systemStatus.recognitionReady ? "true" : "false") + ",";
        status += "\"total_users\":" + String(systemStatus.totalUsers) + ",";
        status += "\"last_user\":\"" + systemStatus.lastRecognizedUser + "\",";
        status += "\"last_confidence\":" + String(systemStatus.lastConfidence, 2) + ",";
        status += "\"door_unlocked\":" + String(isDoorUnlocked ? "true" : "false") + ",";
        status += "\"free_heap\":" + String(ESP.getFreeHeap()) + ",";
        status += "\"free_psram\":" + String(ESP.getFreePsram());
        status += "}";
        
        request->send(200, "application/json", status); });

    // Start enrollment mode - LIVE CAMERA ONLY
    server.on("/api/enroll/start", HTTP_POST, [](AsyncWebServerRequest *request)
              {
        if (!request->hasParam("name", true)) {
            request->send(400, "application/json", "{\"error\":\"Missing name parameter\"}");
            return;
        }
        
        String userName = request->getParam("name", true)->value();
        userName.trim();
        
        if (userName.length() == 0) {
            request->send(400, "application/json", "{\"error\":\"Invalid name\"}");
            return;
        }
        
        enrollmentMode = true;
        currentEnrollmentUser = userName;
        enrollmentSteps = 0;
        
        Serial.printf("Starting enrollment for: %s\n", userName.c_str());
        
        request->send(200, "application/json", 
            "{\"message\":\"Enrollment started for " + userName + "\",\"steps_required\":" + String(REQUIRED_ENROLLMENT_STEPS) + "}"); });

    // Cancel enrollment
    server.on("/api/enroll/cancel", HTTP_POST, [](AsyncWebServerRequest *request)
              {
        enrollmentMode = false;
        currentEnrollmentUser = "";
        enrollmentSteps = 0;
        
        request->send(200, "application/json", "{\"message\":\"Enrollment cancelled\"}"); });

    // Clear all enrolled faces
    server.on("/api/enroll/clear", HTTP_POST, [](AsyncWebServerRequest *request)
              {
        Serial.println("[API] Clearing ALL enrolled faces...");
        
        // Delete the SPIFFS file completely
        if (SPIFFS.exists("/fr.bin")) {
            SPIFFS.remove("/fr.bin");
            Serial.println("[API] Deleted /fr.bin");
        }
        
        // Clear all enrolled IDs from recognizer
        for (uint8_t i = 0; i < 20; i++) {
            recognition.recognizer.delete_id(i);
        }
        
        // Recreate empty file
        File f = SPIFFS.open("/fr.bin", "wb");
        f.close();
        
        // Reinitialize recognition system
        recognition.begin();
        
        // Reset system status
        systemStatus.totalUsers = 0;
        systemStatus.lastRecognizedUser = "";
        systemStatus.lastConfidence = 0.0;
        
        // Reset liveness and matching state
        resetLivenessTracking();
        consecutiveMatches = 0;
        lastConfirmedUser = "";
        lastAccessUser = "";
        lastAccessTime = 0;
        
        Serial.printf("[API] All faces cleared. Users now: %d\n", recognition.recognizer.get_enrolled_id_num());
        updateSystemStatus();
        
        request->send(200, "application/json", "{\"success\":true,\"message\":\"All enrolled faces cleared\",\"total_users\":0}"); });

    // Get enrollment status
    server.on("/api/enroll/status", HTTP_GET, [](AsyncWebServerRequest *request)
              {
        String status = "{";

        if (enrollmentJustCompleted) {
            // Enrollment just completed - signal to Flutter app
            status += "\"active\":false,";
            status += "\"user\":\"" + lastEnrolledUser + "\",";
            status += "\"steps_completed\":" + String(REQUIRED_ENROLLMENT_STEPS) + ",";
            status += "\"steps_required\":" + String(REQUIRED_ENROLLMENT_STEPS) + ",";
            status += "\"complete\":true,";
            status += "\"message\":\"Enrollment completed for " + lastEnrolledUser + "\"";
            // Clear the flag after sending completion status
            enrollmentJustCompleted = false;
        } else if (enrollmentMode) {
            status += "\"active\":true,";
            status += "\"user\":\"" + currentEnrollmentUser + "\",";
            status += "\"steps_completed\":" + String(enrollmentSteps) + ",";
            status += "\"steps_required\":" + String(REQUIRED_ENROLLMENT_STEPS) + ",";
            status += "\"complete\":false,";
            status += "\"message\":\"Enrolling step " + String(enrollmentSteps + 1) + "/" + String(REQUIRED_ENROLLMENT_STEPS) + "\"";
        } else {
            status += "\"active\":false,";
            status += "\"user\":\"\",";
            status += "\"steps_completed\":0,";
            status += "\"steps_required\":" + String(REQUIRED_ENROLLMENT_STEPS) + ",";
            status += "\"complete\":false,";
            status += "\"message\":\"Ready to enroll\"";
        }

        status += "}";
        
        request->send(200, "application/json", status); });

    // Unlock door manually
    server.on("/api/door/unlock", HTTP_POST, [](AsyncWebServerRequest *request)
              {
        unlockDoor("Manual");
        request->send(200, "application/json", "{\"message\":\"Door unlocked manually\"}"); });

    // Get access logs - from SD card if available, else RAM buffer
    server.on("/api/logs", HTTP_GET, [](AsyncWebServerRequest *request)
              {
        String json = "[";
        bool first = true;
        int logCount = 0;
        
        // Optional limit parameter
        int limit = 100;  // Default limit
        if (request->hasParam("limit")) {
            limit = request->getParam("limit")->value().toInt();
        }
        
        // Read from SD card if available
        if (sdCardReady && SD_MMC.exists(SD_LOG_FILE)) {
            File logFile = SD_MMC.open(SD_LOG_FILE, FILE_READ);
            if (logFile) {
                // Skip header line
                logFile.readStringUntil('\n');
                
                // Read all lines into temporary storage to get newest first
                std::vector<String> lines;
                while (logFile.available() && lines.size() < 500) {  // Max 500 to prevent memory issues
                    String line = logFile.readStringUntil('\n');
                    line.trim();
                    if (line.length() > 0) {
                        lines.push_back(line);
                    }
                }
                logFile.close();
                
                // Output newest first (reverse order)
                int start = max(0, (int)lines.size() - limit);
                for (int i = lines.size() - 1; i >= start; i--) {
                    // Parse CSV: timestamp,username,action,success,confidence
                    String line = lines[i];
                    int p1 = line.indexOf(',');
                    int p2 = line.indexOf(',', p1+1);
                    int p3 = line.indexOf(',', p2+1);
                    int p4 = line.indexOf(',', p3+1);
                    
                    if (p1 > 0 && p2 > 0 && p3 > 0 && p4 > 0) {
                        String ts = line.substring(0, p1);
                        String user = line.substring(p1+1, p2);
                        String action = line.substring(p2+1, p3);
                        String success = line.substring(p3+1, p4);
                        String conf = line.substring(p4+1);
                        
                        if (!first) json += ",";
                        first = false;
                        
                        json += "{";
                        json += "\"username\":\"" + user + "\",";
                        json += "\"status\":\"" + action + "\",";
                        json += "\"success\":";
                        json += (success == "1") ? "true" : "false";
                        json += ",";
                        json += "\"confidence\":" + conf + ",";
                        json += "\"timestamp\":" + ts;
                        json += "}";
                        logCount++;
                    }
                }
            }
        } else {
            // Fallback: Return from RAM buffer (newest first)
            for (int i = 0; i < ramLogCount && i < limit; i++) {
                int idx = (ramLogIndex - 1 - i + MAX_RAM_LOGS) % MAX_RAM_LOGS;
                if (idx < 0) idx += MAX_RAM_LOGS;
                
                if (!first) json += ",";
                first = false;
                
                json += "{";
                json += "\"username\":\"" + ramLogBuffer[idx].username + "\",";
                json += "\"status\":\"" + ramLogBuffer[idx].action + "\",";
                json += "\"success\":" + String(ramLogBuffer[idx].success ? "true" : "false") + ",";
                json += "\"confidence\":" + String(ramLogBuffer[idx].confidence, 2) + ",";
                json += "\"timestamp\":" + String(ramLogBuffer[idx].timestamp);
                json += "}";
                logCount++;
            }
        }
        json += "]";
        
        Serial.printf("[API] GET /api/logs - returning %d logs (SD: %s)\n", logCount, sdCardReady ? "yes" : "no");
        request->send(200, "application/json", json); });

    // Clear activity logs - both RAM and SD card
    server.on("/api/logs/clear", HTTP_POST, [](AsyncWebServerRequest *request)
              {
        // Clear RAM buffer
        ramLogIndex = 0;
        ramLogCount = 0;
        
        // Clear SD card log file (recreate with header)
        if (sdCardReady) {
            SD_MMC.remove(SD_LOG_FILE);
            File logFile = SD_MMC.open(SD_LOG_FILE, FILE_WRITE);
            if (logFile) {
                logFile.println("timestamp,username,action,success,confidence");
                logFile.close();
            }
            Serial.println("[API] Activity logs cleared (RAM + SD card)");
        } else {
            Serial.println("[API] Activity logs cleared (RAM only)");
        }
        
        request->send(200, "application/json", "{\"success\":true,\"message\":\"Logs cleared\"}"); });

    // Get SD card status
    server.on("/api/sdcard/status", HTTP_GET, [](AsyncWebServerRequest *request)
              {
        String json = "{";
        json += "\"available\":" + String(sdCardReady ? "true" : "false");
        if (sdCardReady) {
            json += ",\"card_size_mb\":" + String(SD_MMC.cardSize() / (1024 * 1024));
            json += ",\"used_bytes\":" + String(SD_MMC.usedBytes());
            json += ",\"total_bytes\":" + String(SD_MMC.totalBytes());
            
            // Count log entries
            int logLines = 0;
            if (SD_MMC.exists(SD_LOG_FILE)) {
                File f = SD_MMC.open(SD_LOG_FILE, FILE_READ);
                if (f) {
                    while (f.available()) {
                        f.readStringUntil('\n');
                        logLines++;
                    }
                    f.close();
                    logLines--;  // Subtract header
                }
            }
            json += ",\"log_entries\":" + String(logLines);
        }
        json += "}";
        request->send(200, "application/json", json); });

    // ========================================
    // PROFILE IMAGE ENDPOINTS (SD Card Storage)
    // Streams directly to SD card - no RAM buffer needed
    // ========================================

    // Upload profile image - STREAMING to SD card (no RAM buffer)
    server.on("/api/profile/upload", HTTP_POST,
              // Request handler (called after upload complete)
              [](AsyncWebServerRequest *request)
              {
                  // Response sent by upload handler
              },
              // File upload handler - streams directly to SD card
              [](AsyncWebServerRequest *request, String filename, size_t index, uint8_t *data, size_t len, bool final)
              {
            static File uploadFile;
            static String uploadUsername;
            
            if (!sdCardReady) {
                if (final) {
                    request->send(503, "application/json", "{\"success\":false,\"error\":\"SD card not available\"}");
                }
                return;
            }
            
            if (index == 0) {
                // First chunk - get username and open file
                if (request->hasParam("username", true)) {
                    uploadUsername = request->getParam("username", true)->value();
                } else {
                    uploadUsername = "unknown";
                }
                
                // Create profiles directory if not exists
                if (!SD_MMC.exists(SD_PROFILES_DIR)) {
                    SD_MMC.mkdir(SD_PROFILES_DIR);
                }
                
                // Generate filename
                String filePath = String(SD_PROFILES_DIR) + "/" + uploadUsername + ".jpg";
                
                // Remove old file if exists
                if (SD_MMC.exists(filePath)) {
                    SD_MMC.remove(filePath);
                }
                
                // Open file for writing - streams directly to SD
                uploadFile = SD_MMC.open(filePath, FILE_WRITE);
                if (!uploadFile) {
                    Serial.printf("[PROFILE] Failed to create file: %s\n", filePath.c_str());
                    return;
                }
                
                Serial.printf("[PROFILE] Starting upload for: %s (streaming to SD)\n", uploadUsername.c_str());
            }
            
            // Write chunk directly to SD card - NO RAM BUFFER
            if (uploadFile) {
                uploadFile.write(data, len);
            }
            
            if (final) {
                // Last chunk - close file and respond
                size_t totalSize = index + len;
                if (uploadFile) {
                    uploadFile.close();
                    Serial.printf("[PROFILE] Upload complete: %s (%d bytes)\n", uploadUsername.c_str(), totalSize);
                    
                    String response = "{\"success\":true,\"username\":\"" + uploadUsername + "\",\"size\":" + String(totalSize) + "}";
                    request->send(200, "application/json", response);
                } else {
                    request->send(500, "application/json", "{\"success\":false,\"error\":\"File write failed\"}");
                }
            } });

    // Download profile image from SD card
    server.on("/api/profile/download", HTTP_GET, [](AsyncWebServerRequest *request)
              {
        if (!sdCardReady) {
            request->send(503, "application/json", "{\"success\":false,\"error\":\"SD card not available\"}");
            return;
        }
        
        if (!request->hasParam("username")) {
            request->send(400, "application/json", "{\"success\":false,\"error\":\"Missing username parameter\"}");
            return;
        }
        
        String username = request->getParam("username")->value();
        String filePath = String(SD_PROFILES_DIR) + "/" + username + ".jpg";
        
        if (!SD_MMC.exists(filePath)) {
            request->send(404, "application/json", "{\"success\":false,\"error\":\"Profile image not found\"}");
            return;
        }
        
        Serial.printf("[PROFILE] Serving image: %s\n", username.c_str());
        
        // Stream file directly from SD card - memory efficient
        request->send(SD_MMC, filePath, "image/jpeg"); });

    // Delete profile image
    server.on("/api/profile/delete", HTTP_DELETE, [](AsyncWebServerRequest *request)
              {
        if (!sdCardReady) {
            request->send(503, "application/json", "{\"success\":false,\"error\":\"SD card not available\"}");
            return;
        }
        
        if (!request->hasParam("username")) {
            request->send(400, "application/json", "{\"success\":false,\"error\":\"Missing username parameter\"}");
            return;
        }
        
        String username = request->getParam("username")->value();
        String filePath = String(SD_PROFILES_DIR) + "/" + username + ".jpg";
        
        if (SD_MMC.exists(filePath)) {
            SD_MMC.remove(filePath);
            Serial.printf("[PROFILE] Deleted: %s\n", username.c_str());
            request->send(200, "application/json", "{\"success\":true,\"message\":\"Profile image deleted\"}");
        } else {
            request->send(404, "application/json", "{\"success\":false,\"error\":\"Profile image not found\"}");
        } });

    // List all profile images
    server.on("/api/profile/list", HTTP_GET, [](AsyncWebServerRequest *request)
              {
        if (!sdCardReady) {
            request->send(503, "application/json", "{\"success\":false,\"error\":\"SD card not available\"}");
            return;
        }
        
        String json = "{\"profiles\":[";
        bool first = true;
        
        File dir = SD_MMC.open(SD_PROFILES_DIR);
        if (dir && dir.isDirectory()) {
            File file = dir.openNextFile();
            while (file) {
                if (!file.isDirectory()) {
                    String filename = String(file.name());
                    if (filename.endsWith(".jpg")) {
                        if (!first) json += ",";
                        first = false;
                        
                        // Extract username from filename
                        String username = filename.substring(0, filename.length() - 4);
                        json += "{\"username\":\"" + username + "\",\"size\":" + String(file.size()) + "}";
                    }
                }
                file = dir.openNextFile();
            }
            dir.close();
        }
        json += "]}";
        
        request->send(200, "application/json", json); });

    // ========================================
    // WIFI CONFIGURATION ENDPOINTS
    // ========================================

    // Get current WiFi status
    server.on("/api/wifi/status", HTTP_GET, [](AsyncWebServerRequest *request)
              {
        String json = "{";
        json += "\"mode\":\"" + String(isStationMode ? "STATION" : "AP") + "\",";
        json += "\"ssid\":\"" + String(isStationMode ? configuredSSID : AP_SSID) + "\",";
        json += "\"ip\":\"" + String(isStationMode ? WiFi.localIP().toString() : WiFi.softAPIP().toString()) + "\",";
        json += "\"rssi\":" + String(isStationMode ? WiFi.RSSI() : 0) + ",";
        json += "\"connected\":" + String(WiFi.status() == WL_CONNECTED ? "true" : "false");
        json += "}";
        request->send(200, "application/json", json); });

    // Scan available WiFi networks
    server.on("/api/wifi/scan", HTTP_GET, [](AsyncWebServerRequest *request)
              {
        Serial.println("[API] Scanning WiFi networks...");
        
        // Perform synchronous scan
        int n = WiFi.scanNetworks();
        
        String json = "{\"networks\":[";
        for (int i = 0; i < n; i++) {
            if (i > 0) json += ",";
            json += "{";
            json += "\"ssid\":\"" + WiFi.SSID(i) + "\",";
            json += "\"rssi\":" + String(WiFi.RSSI(i)) + ",";
            json += "\"encryption\":" + String(WiFi.encryptionType(i) != WIFI_AUTH_OPEN ? "true" : "false");
            json += "}";
        }
        json += "]}";
        
        WiFi.scanDelete(); // Clean up scan results
        
        Serial.printf("[API] Found %d networks\n", n);
        request->send(200, "application/json", json); });

    // Configure WiFi credentials
    server.on("/api/wifi", HTTP_POST, [](AsyncWebServerRequest *request)
              {
        if (!request->hasParam("ssid", true) || !request->hasParam("password", true)) {
            request->send(400, "application/json", "{\"success\":false,\"message\":\"Missing ssid or password\"}");
            return;
        }
        
        String newSSID = request->getParam("ssid", true)->value();
        String newPassword = request->getParam("password", true)->value();
        
        Serial.printf("[API] WiFi config received - SSID: %s\n", newSSID.c_str());
        
        // Save new configuration
        saveWiFiConfig(newSSID, newPassword);
        
        // Send response before reconnecting
        request->send(200, "application/json", 
            "{\"success\":true,\"message\":\"WiFi configuration saved. ESP32 will restart and try to connect to the new network.\"}");
        
        // Delay to allow response to be sent
        delay(1000);
        
        // Restart ESP32 to apply new WiFi config
        Serial.println("[API] Restarting ESP32 to apply new WiFi config...");
        ESP.restart(); });

    // Note: MJPEG streaming is handled by WiFiServer on port 81

    // API to control live feed state
    server.on("/api/livefeed/start", HTTP_POST, [](AsyncWebServerRequest *request)
              {
        liveFeedActive = true;
        liveFeedLastRequest = millis();
        Serial.println("[API] Live feed STARTED - Recognition PAUSED");
        request->send(200, "application/json", "{\"success\":true,\"message\":\"Live feed started, recognition paused\"}"); });

    server.on("/api/livefeed/stop", HTTP_POST, [](AsyncWebServerRequest *request)
              {
        liveFeedActive = false;
        Serial.println("[API] Live feed STOPPED - Recognition RESUMED");
        request->send(200, "application/json", "{\"success\":true,\"message\":\"Live feed stopped, recognition resumed\"}"); });

    // User management endpoints - reads actual enrolled faces from SPIFFS (returns UNIQUE users only)
    server.on("/api/users", HTTP_GET, [](AsyncWebServerRequest *request)
              {
        // Read enrolled users from SPIFFS file - return UNIQUE names only
        String json = "[";
        bool first = true;
        int userId = 0;
        std::set<String> seenNames;
        
        File file = SPIFFS.open("/fr.bin", "rb");
        if (file) {
            while (file.available()) {
                // Structure matches enrolled_face_t in recognition.h
                struct {
                    int id;
                    char name[17];
                    float embedding[512];
                    uint8_t ctrl[2];
                } enrolled;
                
                file.read((uint8_t*)&enrolled, sizeof(enrolled));
                
                // Verify control bytes
                if (enrolled.ctrl[0] != 0x14 || enrolled.ctrl[1] != 0x08) {
                    break; // Parse error, stop reading
                }
                
                // Skip empty or invalid names
                if (strlen(enrolled.name) == 0) continue;
                
                // Skip if we already added this user (unique names only)
                String userName = String(enrolled.name);
                if (seenNames.count(userName) > 0) continue;
                seenNames.insert(userName);
                
                if (!first) json += ",";
                first = false;
                
                json += "{";
                json += "\"id\":" + String(userId) + ",";
                json += "\"name\":\"" + userName + "\",";
                json += "\"jabatan\":\"\",";
                json += "\"departemen\":\"\",";
                json += "\"masaBerlaku\":\"2025-12-31\"";
                json += "}";
                userId++;
            }
            file.close();
        }
        json += "]";
        
        Serial.printf("[API] GET /api/users - returning %d unique users\n", userId);
        request->send(200, "application/json", json); });

    server.on("/api/users", HTTP_POST, [](AsyncWebServerRequest *request)
              {
        // Dummy response - user data handled by face recognition system
        request->send(200, "application/json", "{\"success\":true,\"message\":\"User data received\"}"); });

    // Delete user endpoint - SAFE IMPLEMENTATION (no dynamic memory)
    server.on("/api/users", HTTP_DELETE, [](AsyncWebServerRequest *request)
              {
        if (!request->hasParam("id") && !request->hasParam("name")) {
            request->send(400, "application/json", "{\"success\":false,\"message\":\"Missing id or name parameter\"}");
            return;
        }
        
        String targetName = "";
        int targetId = -1;
        
        if (request->hasParam("name")) {
            targetName = request->getParam("name")->value();
        }
        if (request->hasParam("id")) {
            targetId = request->getParam("id")->value().toInt();
        }
        
        Serial.printf("[API] DELETE user request - id: %d, name: %s\n", targetId, targetName.c_str());
        
        // Use temporary file approach - safer for memory
        File readFile = SPIFFS.open("/fr.bin", "rb");
        if (!readFile) {
            request->send(500, "application/json", "{\"success\":false,\"message\":\"Cannot open faces file\"}");
            return;
        }
        
        File writeFile = SPIFFS.open("/fr_temp.bin", "wb");
        if (!writeFile) {
            readFile.close();
            request->send(500, "application/json", "{\"success\":false,\"message\":\"Cannot create temp file\"}");
            return;
        }
        
        // Structure for enrolled face - static allocation
        struct EnrolledFace {
            int id;
            char name[17];
            float embedding[512];
            uint8_t ctrl[2];
        };
        
        int currentId = 0;
        int deletedCount = 0;
        int keptCount = 0;
        
        while (readFile.available() >= sizeof(EnrolledFace)) {
            EnrolledFace enrolled;
            size_t bytesRead = readFile.read((uint8_t*)&enrolled, sizeof(EnrolledFace));
            
            if (bytesRead != sizeof(EnrolledFace)) break;
            if (enrolled.ctrl[0] != 0x14 || enrolled.ctrl[1] != 0x08) break;
            
            // Check if this face should be deleted
            bool shouldDelete = false;
            if (targetName.length() > 0 && String(enrolled.name) == targetName) {
                shouldDelete = true;
            }
            
            if (shouldDelete) {
                deletedCount++;
                Serial.printf("[API] Deleting face: %s (record: %d)\n", enrolled.name, currentId);
            } else {
                // Keep this face - write to temp file
                writeFile.write((uint8_t*)&enrolled, sizeof(EnrolledFace));
                keptCount++;
            }
            currentId++;
        }
        
        readFile.close();
        writeFile.close();
        
        if (deletedCount == 0) {
            // No faces deleted, remove temp file
            SPIFFS.remove("/fr_temp.bin");
            request->send(404, "application/json", "{\"success\":false,\"message\":\"User not found\"}");
            return;
        }
        
        // Replace original file with temp file
        SPIFFS.remove("/fr.bin");
        SPIFFS.rename("/fr_temp.bin", "/fr.bin");
        
        Serial.printf("[API] Deleted %d face records, kept %d\n", deletedCount, keptCount);
        
        // Reload recognition system
        recognition.begin();
        updateSystemStatus();
        
        String response = "{\"success\":true,\"message\":\"Deleted " + String(deletedCount) + " face records\",\"remaining\":" + String(keptCount) + "}";
        request->send(200, "application/json", response); });

    server.begin();

    Serial.println("Web server started");
}

// ========================================
// FACE RECOGNITION FUNCTIONS
// ========================================
void handleEnrollment()
{
    if (!enrollmentMode || currentEnrollmentUser.length() == 0)
    {
        return;
    }

    // Capture image
    if (!camera.capture().isOk())
    {
        return;
    }

    // Detect face
    if (!recognition.detect().isOk())
    {
        return; // No face detected, continue waiting
    }

    // Enroll face
    if (recognition.enroll(currentEnrollmentUser).isOk())
    {
        enrollmentSteps++;
        Serial.printf("Enrollment step %d/%d completed for %s\n",
                      enrollmentSteps, REQUIRED_ENROLLMENT_STEPS, currentEnrollmentUser.c_str());

        if (enrollmentSteps >= REQUIRED_ENROLLMENT_STEPS)
        {
            // Enrollment complete
            Serial.printf("Enrollment completed for %s\n", currentEnrollmentUser.c_str());

            // Set completion flag so Flutter app can see it
            enrollmentJustCompleted = true;
            lastEnrolledUser = currentEnrollmentUser;

            enrollmentMode = false;
            currentEnrollmentUser = "";
            enrollmentSteps = 0;

            updateSystemStatus();
        }

        delay(2000); // Pause between enrollment steps
    }
}

void handleRecognition()
{
    static unsigned long lastRecognitionAttempt = 0;
    static unsigned long lastStatusPrint = 0;
    const unsigned long RECOGNITION_INTERVAL = 1000;   // 1 second between attempts (faster for liveness)
    const unsigned long STATUS_PRINT_INTERVAL = 10000; // 10 seconds status update
    const unsigned long LIVE_FEED_TIMEOUT = 5000;      // Auto-resume after 5 seconds of no live feed requests

    // Auto-disable live feed if no requests for 5 seconds
    if (liveFeedActive && (millis() - liveFeedLastRequest > LIVE_FEED_TIMEOUT))
    {
        liveFeedActive = false;
        Serial.println("📷 Live feed timeout - Recognition RESUMED");
    }

    // Skip recognition if live feed is active
    if (liveFeedActive)
    {
        return;
    }

    if (millis() - lastRecognitionAttempt < RECOGNITION_INTERVAL)
    {
        return;
    }

    lastRecognitionAttempt = millis();

    // Print periodic status
    if (millis() - lastStatusPrint > STATUS_PRINT_INTERVAL)
    {
        lastStatusPrint = millis();
        Serial.printf("[SYSTEM] Scanning active | Free heap: %d bytes | Users: %d\n",
                      ESP.getFreeHeap(), systemStatus.totalUsers);
    }

    // Capture image
    if (!camera.capture().isOk())
    {
        return;
    }

    // Detect face
    if (!recognition.detect().isOk())
    {
        // No face - reset liveness tracking
        resetLivenessTracking();
        return;
    }

    // Face detected - record position for liveness check
    FacePosition currentPos;
    currentPos.cx = detection.first.cx;
    currentPos.cy = detection.first.cy;
    currentPos.width = detection.first.width;
    currentPos.height = detection.first.height;
    currentPos.valid = true;

    // Store in history
    faceHistory[faceHistoryIndex] = currentPos;
    faceHistoryIndex = (faceHistoryIndex + 1) % LIVENESS_CHECK_COUNT;
    if (faceHistoryCount < LIVENESS_CHECK_COUNT)
        faceHistoryCount++;

    Serial.printf("[FACE] Detected at (%d,%d) size %dx%d [%d/%d frames]\n",
                  currentPos.cx, currentPos.cy, currentPos.width, currentPos.height,
                  faceHistoryCount, LIVENESS_CHECK_COUNT);

    // Skip recognition if no users enrolled
    if (systemStatus.totalUsers == 0)
    {
        Serial.println("[WARNING] No users enrolled - please enroll a user first");
        return;
    }

    // Recognize face
    if (recognition.recognize().isOk())
    {
        String recognizedName = recognition.match.name.c_str();
        float confidence = recognition.match.similarity;

        // Skip if name is empty or unknown
        if (recognizedName.length() == 0 || recognizedName == "empty" || recognizedName == "unknown")
        {
            Serial.println("[ERROR] Name empty/unknown - rejecting");
            resetLivenessTracking();
            consecutiveMatches = 0;
            lastConfirmedUser = "";
            return;
        }

        // Check confidence threshold (STRICT)
        if (confidence < RECOGNITION_THRESHOLD)
        {
            Serial.printf("[REJECTED] Low confidence %.2f < %.2f for %s\n",
                          confidence, RECOGNITION_THRESHOLD, recognizedName.c_str());
            resetLivenessTracking();
            consecutiveMatches = 0;
            lastConfirmedUser = "";
            logActivity(recognizedName, "DENIED_LOW_CONFIDENCE", false, confidence);
            return;
        }

        // Check for consecutive match confirmation (same person)
        if (recognizedName == lastConfirmedUser)
        {
            consecutiveMatches++;
        }
        else
        {
            // Different person detected - reset
            consecutiveMatches = 1;
            lastConfirmedUser = recognizedName;
            resetLivenessTracking();
            faceHistory[0] = currentPos;
            faceHistoryCount = 1;
            faceHistoryIndex = 1;
        }

        Serial.printf("[MATCH] %d/%d: %s (confidence: %.2f)\n",
                      consecutiveMatches, RECOGNITION_CONFIRM_COUNT, recognizedName.c_str(), confidence);

        // Require consecutive matches before proceeding
        if (consecutiveMatches < RECOGNITION_CONFIRM_COUNT)
        {
            return; // Wait for more confirmations
        }

        // ========================================
        // LIVENESS CHECK - Anti-spoofing
        // ========================================
        if (!checkLiveness())
        {
            Serial.println("[LIVENESS_FAILED] Possible photo/spoof attack!");
            logActivity(recognizedName, "DENIED_LIVENESS_FAIL", false, confidence);
            // Don't reset - let them try again with movement
            return;
        }

        // Check cooldown for same user
        if (recognizedName == lastAccessUser && (millis() - lastAccessTime) < SAME_USER_COOLDOWN)
        {
            Serial.printf("[COOLDOWN] Active for %s (%.1f sec remaining)\n",
                          recognizedName.c_str(), (SAME_USER_COOLDOWN - (millis() - lastAccessTime)) / 1000.0);
            return;
        }

        // ========================================
        // ACCESS GRANTED - Passed ALL checks!
        // ========================================
        Serial.println("========================================");
        Serial.printf("[SUCCESS] ACCESS GRANTED: %s\n", recognizedName.c_str());
        Serial.printf("   Confidence: %.2f (threshold: %.2f)\n", confidence, RECOGNITION_THRESHOLD);
        Serial.printf("   Consecutive matches: %d\n", consecutiveMatches);
        Serial.println("   Liveness: PASSED");
        Serial.println("========================================");

        systemStatus.lastRecognizedUser = recognizedName;
        systemStatus.lastConfidence = confidence;
        systemStatus.lastActivity = millis();

        // Update access tracking
        lastAccessUser = recognizedName;
        lastAccessTime = millis();

        // Reset for next recognition
        resetLivenessTracking();
        consecutiveMatches = 0;
        lastConfirmedUser = "";

        // Unlock door for recognized user
        unlockDoor(recognizedName);
        logActivity(recognizedName, "ACCESS_GRANTED", true, confidence);
    }
    else
    {
        // Face detected but not recognized at all
        resetLivenessTracking();
        consecutiveMatches = 0;
        lastConfirmedUser = "";
        logActivity("Unknown", "DENIED_NOT_ENROLLED", false);
        Serial.println("[ERROR] Face not recognized - not enrolled");
    }
}

// ========================================
// LIVENESS DETECTION - Anti-Spoofing (STRICT)
// ========================================
bool checkLiveness()
{
    // Need enough history to check
    if (faceHistoryCount < LIVENESS_CHECK_COUNT)
    {
        Serial.printf("[LIVENESS] Need %d frames, have %d\n", LIVENESS_CHECK_COUNT, faceHistoryCount);
        return false;
    }

    // Analyze movement patterns across all frames
    int posChanges[LIVENESS_CHECK_COUNT - 1];
    int sizeChanges[LIVENESS_CHECK_COUNT - 1];
    int validComparisons = 0;
    int microMovementCount = 0; // Natural tiny movements
    int largeMovementCount = 0; // Suspicious large movements (photo being moved)
    int zeroMovementCount = 0;  // Completely static (printed photo on stand)

    for (int i = 0; i < LIVENESS_CHECK_COUNT - 1; i++)
    {
        int idx1 = i;
        int idx2 = i + 1;

        if (!faceHistory[idx1].valid || !faceHistory[idx2].valid)
            continue;

        int posChange = abs(faceHistory[idx2].cx - faceHistory[idx1].cx) +
                        abs(faceHistory[idx2].cy - faceHistory[idx1].cy);
        int sizeChange = abs(faceHistory[idx2].width - faceHistory[idx1].width) +
                         abs(faceHistory[idx2].height - faceHistory[idx1].height);

        posChanges[validComparisons] = posChange;
        sizeChanges[validComparisons] = sizeChange;

        // Categorize movement type
        if (posChange == 0 && sizeChange == 0)
        {
            zeroMovementCount++; // Completely static - suspicious
        }
        else if (posChange <= LIVENESS_MAX_MICRO_MOVEMENT)
        {
            // Any small movement (including very tiny ones) counts as natural micro-movement
            // Real humans always have SOME movement from breathing, pulse, etc.
            microMovementCount++; // Natural human micro-movements
        }
        else if (posChange > LIVENESS_PHOTO_THRESHOLD)
        {
            largeMovementCount++; // Suspicious - photo being shaken/moved
        }

        validComparisons++;
    }

    if (validComparisons == 0)
    {
        Serial.println("[WARNING] Liveness: No valid comparisons");
        return false;
    }

    // Calculate statistics
    int totalPosChange = 0;
    int totalSizeChange = 0;
    int maxPosChange = 0;
    int minPosChange = 999;

    for (int i = 0; i < validComparisons; i++)
    {
        totalPosChange += posChanges[i];
        totalSizeChange += sizeChanges[i];
        if (posChanges[i] > maxPosChange)
            maxPosChange = posChanges[i];
        if (posChanges[i] < minPosChange)
            minPosChange = posChanges[i];
    }

    int avgPosChange = totalPosChange / validComparisons;
    int avgSizeChange = totalSizeChange / validComparisons;
    int posChangeVariance = maxPosChange - minPosChange;

    Serial.println("📊 LIVENESS ANALYSIS:");
    Serial.printf("   Avg pos change: %d, Avg size change: %d\n", avgPosChange, avgSizeChange);
    Serial.printf("   Micro-movements: %d/%d, Large movements: %d, Zero movements: %d\n",
                  microMovementCount, LIVENESS_CONSISTENCY_REQUIRED, largeMovementCount, zeroMovementCount);
    Serial.printf("   Position variance: %d (min:%d, max:%d)\n", posChangeVariance, minPosChange, maxPosChange);

    // ========================================
    // ANTI-SPOOFING CHECKS
    // ========================================

    // CHECK 1: Completely static = printed photo on stand
    if (zeroMovementCount >= validComparisons - 1)
    {
        Serial.println("[REJECTED] Face completely static - likely printed photo on stand");
        return false;
    }

    // CHECK 2: Large erratic movements = photo being shaken
    if (largeMovementCount >= 2)
    {
        Serial.println("[REJECTED] Large erratic movements detected - likely photo being moved");
        return false;
    }

    // CHECK 3: Very uniform large movement = phone/tablet being moved
    if (avgPosChange > LIVENESS_PHOTO_THRESHOLD && posChangeVariance < 5)
    {
        Serial.println("[REJECTED] Uniform large movement - likely device/photo being moved");
        return false;
    }

    // CHECK 4: Face size too stable = flat photo surface
    // Real 3D faces have slight size variations due to distance changes
    if (avgSizeChange == 0 && avgPosChange > 10)
    {
        Serial.println("[REJECTED] Size too stable with position change - likely flat photo");
        return false;
    }

    // CHECK 5: Need natural micro-movements pattern (human breathing, tiny head movements)
    // Real humans have small natural movements between 2-15 pixels
    if (microMovementCount < LIVENESS_CONSISTENCY_REQUIRED)
    {
        Serial.printf("[REJECTED] Insufficient natural micro-movements (%d/%d required)\n",
                      microMovementCount, LIVENESS_CONSISTENCY_REQUIRED);
        Serial.println("   Real faces show natural tiny movements from breathing/head micro-movements");
        return false;
    }

    Serial.println("[SUCCESS] LIVENESS PASSED: Natural movement pattern detected");
    return true;
}

void resetLivenessTracking()
{
    faceHistoryIndex = 0;
    faceHistoryCount = 0;
    for (int i = 0; i < LIVENESS_CHECK_COUNT; i++)
    {
        faceHistory[i].valid = false;
    }
}

// ========================================
// UTILITY FUNCTIONS
// ========================================
void unlockDoor(const String &userName)
{
    digitalWrite(DOOR_RELAY_PIN, HIGH);
    isDoorUnlocked = true;
    doorUnlockTime = millis();

    Serial.printf("Door unlocked for: %s\n", userName.c_str());

    // Blink status LED
    for (int i = 0; i < 3; i++)
    {
        digitalWrite(STATUS_LED_PIN, LOW);
        delay(100);
        digitalWrite(STATUS_LED_PIN, HIGH);
        delay(100);
    }
}

// Trim SD log file to keep only last MAX_SD_LOGS entries
void trimSDLogFile()
{
    if (!sdCardReady || !SD_MMC.exists(SD_LOG_FILE))
        return;

    File logFile = SD_MMC.open(SD_LOG_FILE, FILE_READ);
    if (!logFile)
        return;

    // Read all lines
    std::vector<String> lines;
    String header = logFile.readStringUntil('\n'); // Keep header
    while (logFile.available())
    {
        String line = logFile.readStringUntil('\n');
        line.trim();
        if (line.length() > 0)
        {
            lines.push_back(line);
        }
    }
    logFile.close();

    // If under limit, no need to trim
    if (lines.size() <= MAX_SD_LOGS)
        return;

    // Keep only the last MAX_SD_LOGS entries
    int startIdx = lines.size() - MAX_SD_LOGS;

    // Rewrite file with trimmed data
    logFile = SD_MMC.open(SD_LOG_FILE, FILE_WRITE);
    if (logFile)
    {
        logFile.println(header); // Write header
        for (int i = startIdx; i < lines.size(); i++)
        {
            logFile.println(lines[i]);
        }
        logFile.close();
        Serial.printf("📝 SD LOG: Trimmed to %d entries (was %d)\n", MAX_SD_LOGS, lines.size());
    }
}

void logActivity(const String &userName, const String &action, bool success, float confidence)
{
    unsigned long timestamp = millis();

    // Write directly to SD card if available (offload RAM)
    if (sdCardReady)
    {
        File logFile = SD_MMC.open(SD_LOG_FILE, FILE_APPEND);
        if (logFile)
        {
            // CSV format: timestamp,username,action,success,confidence
            logFile.printf("%lu,%s,%s,%d,%.2f\n",
                           timestamp, userName.c_str(), action.c_str(),
                           success ? 1 : 0, confidence);
            logFile.close();
            Serial.printf("📝 SD LOG: %s - %s - %s - %.2f\n",
                          userName.c_str(), action.c_str(), success ? "YES" : "NO", confidence);

            // Trim log file if it gets too large
            trimSDLogFile();
        }
        else
        {
            // SD write failed, fall back to RAM
            goto store_in_ram;
        }
    }
    else
    {
    store_in_ram:
        // Store in small RAM buffer (circular, overwrites old)
        ramLogBuffer[ramLogIndex].username = userName;
        ramLogBuffer[ramLogIndex].action = action;
        ramLogBuffer[ramLogIndex].success = success;
        ramLogBuffer[ramLogIndex].confidence = confidence;
        ramLogBuffer[ramLogIndex].timestamp = timestamp;

        ramLogIndex = (ramLogIndex + 1) % MAX_RAM_LOGS;
        if (ramLogCount < MAX_RAM_LOGS)
            ramLogCount++;

        Serial.printf("📝 RAM LOG: %s - %s - %s - %.2f (buffer: %d/%d)\n",
                      userName.c_str(), action.c_str(), success ? "YES" : "NO",
                      confidence, ramLogCount, MAX_RAM_LOGS);
    }
}

void updateSystemStatus()
{
    // Count UNIQUE enrolled users by reading names from SPIFFS
    std::set<String> uniqueNames;

    File file = SPIFFS.open("/fr.bin", "rb");
    if (file)
    {
        while (file.available())
        {
            struct
            {
                int id;
                char name[17];
                float embedding[512];
                uint8_t ctrl[2];
            } enrolled;

            file.read((uint8_t *)&enrolled, sizeof(enrolled));

            if (enrolled.ctrl[0] != 0x14 || enrolled.ctrl[1] != 0x08)
                break;
            if (strlen(enrolled.name) > 0)
            {
                uniqueNames.insert(String(enrolled.name));
            }
        }
        file.close();
    }

    systemStatus.totalUsers = uniqueNames.size();
    Serial.printf("System status updated - Users: %d\n", systemStatus.totalUsers);
}