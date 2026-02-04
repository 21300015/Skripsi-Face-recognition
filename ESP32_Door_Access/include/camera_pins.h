// Camera Pins Configuration for ESP32-S3 WROOM
// Compatible with Freenove ESP32-S3 WROOM and similar boards
#ifndef CAMERA_PINS_H
#define CAMERA_PINS_H

#ifdef USE_ESP32S3_WROOM

// Camera Pins for ESP32-S3 WROOM (ESP32-S3-EYE compatible)
#define PWDN_GPIO_NUM -1
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM 15
#define SIOD_GPIO_NUM 4
#define SIOC_GPIO_NUM 5

#define Y9_GPIO_NUM 16
#define Y8_GPIO_NUM 17
#define Y7_GPIO_NUM 18
#define Y6_GPIO_NUM 12
#define Y5_GPIO_NUM 10
#define Y4_GPIO_NUM 8
#define Y3_GPIO_NUM 9
#define Y2_GPIO_NUM 11
#define VSYNC_GPIO_NUM 6
#define HREF_GPIO_NUM 7
#define PCLK_GPIO_NUM 13

// SD Card Pins for ESP32-S3 WROOM (SDMMC interface)
#define SD_CMD_PIN 38
#define SD_CLK_PIN 39
#define SD_D0_PIN 40
#define SD_D1_PIN 41
#define SD_D2_PIN 42
#define SD_D3_PIN 1

// Door Control Relay Pin (available GPIO for ESP32-S3)
// Note: DOOR_RELAY_PIN is defined in main.cpp as GPIO 21

// Status LED (optional - can be disabled to save pins)
// #define LED_GPIO_NUM      21  // Commented out as per requirements

#else

// Fallback: ESP32-CAM AI-Thinker Pin Configuration
#define PWDN_GPIO_NUM 32
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM 0
#define SIOD_GPIO_NUM 26
#define SIOC_GPIO_NUM 27

#define Y9_GPIO_NUM 35
#define Y8_GPIO_NUM 34
#define Y7_GPIO_NUM 39
#define Y6_GPIO_NUM 36
#define Y5_GPIO_NUM 21
#define Y4_GPIO_NUM 19
#define Y3_GPIO_NUM 18
#define Y2_GPIO_NUM 5
#define VSYNC_GPIO_NUM 25
#define HREF_GPIO_NUM 23
#define PCLK_GPIO_NUM 22

// SD Card Pins for ESP32-CAM (SDMMC Slot 1)
#define SD_CMD_PIN 15
#define SD_CLK_PIN 14
#define SD_D0_PIN 2
#define SD_D1_PIN 4
#define SD_D2_PIN 12
#define SD_D3_PIN 13

// Door Control Relay Pin
#define DOOR_RELAY_PIN 16

#endif

#endif // CAMERA_PINS_H