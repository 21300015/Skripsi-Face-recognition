import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class WiFiConfigScreen extends StatefulWidget {
  const WiFiConfigScreen({super.key});

  @override
  State<WiFiConfigScreen> createState() => _WiFiConfigScreenState();
}

class _WiFiConfigScreenState extends State<WiFiConfigScreen> {
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _esp32IPController = TextEditingController(
    text: '192.168.4.1',
  );

  String _currentWiFi = 'Unknown';
  String _currentIP = 'Unknown';
  bool _isConfiguring = false;
  bool _isScanning = false;
  List<String> _availableNetworks = [];

  @override
  void initState() {
    super.initState();
    _initializeNetworkInfo();
  }

  Future<void> _initializeNetworkInfo() async {
    await _requestPermissions();
    await _getCurrentNetworkInfo();
  }

  Future<void> _requestPermissions() async {
    // Simplified - no longer requiring permission handlers
  }

  Future<void> _getCurrentNetworkInfo() async {
    try {
      setState(() {
        _currentWiFi = 'Currently connected WiFi'; // Simplified version
        _currentIP = 'Current IP address'; // Simplified version
      });
    } catch (e) {
      // Error getting network info handled silently
    }
  }

  Future<void> _scanAvailableNetworks() async {
    setState(() => _isScanning = true);

    try {
      // Get available networks from ESP32
      final response = await http
          .get(Uri.parse('http://${_esp32IPController.text}/api/wifi/scan'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List<String> networks = [];

        if (data['networks'] != null) {
          for (var network in data['networks']) {
            networks.add(network['ssid']);
          }
        }

        setState(() {
          _availableNetworks = networks;
          _isScanning = false;
        });

        if (networks.isEmpty) {
          _showMessage('No WiFi networks found', isError: true);
        }
      } else {
        throw Exception('Failed to scan networks: ${response.statusCode}');
      }
    } catch (e) {
      // Fallback to simulated networks if ESP32 scan fails
      setState(() {
        _availableNetworks = [
          'Home_WiFi',
          'Office_Network',
          'Guest_Network',
          'Mobile_Hotspot',
        ];
        _isScanning = false;
      });
      _showMessage('Using fallback networks: $e', isError: true);
    }
  }

  Future<void> _configureESP32WiFi() async {
    if (_ssidController.text.isEmpty || _passwordController.text.isEmpty) {
      _showMessage('Please enter WiFi SSID and password', isError: true);
      return;
    }

    setState(() => _isConfiguring = true);

    try {
      // Send WiFi configuration to ESP32
      final response = await http
          .post(
            Uri.parse('http://${_esp32IPController.text}/api/wifi'),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Accept': 'application/json',
            },
            body:
                'ssid=${Uri.encodeComponent(_ssidController.text)}&password=${Uri.encodeComponent(_passwordController.text)}',
          )
          .timeout(const Duration(seconds: 15));

      // WiFi config response logged silently

      if (response.statusCode == 200) {
        _showMessage('WiFi configuration sent successfully!');
        _showConfigurationInstructions();
      } else {
        _showMessage(
          'Failed to configure WiFi: ${response.statusCode}',
          isError: true,
        );
      }
    } catch (e) {
      // WiFi configuration error handled via _showMessage
      _showMessage('Error configuring WiFi: $e', isError: true);
    } finally {
      setState(() => _isConfiguring = false);
    }
  }

  Future<void> _testESP32Connection() async {
    try {
      final response = await http
          .get(
            Uri.parse('http://${_esp32IPController.text}/api/status'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        _showMessage('ESP32 connection successful!');
      } else {
        _showMessage(
          'ESP32 responded with code: ${response.statusCode}',
          isError: true,
        );
      }
    } catch (e) {
      _showMessage('Cannot connect to ESP32: $e', isError: true);
    }
  }

  void _showConfigurationInstructions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configuration Sent'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('WiFi configuration has been sent to ESP32.'),
            SizedBox(height: 12),
            Text('Next steps:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('1. ESP32 will attempt to connect to your WiFi'),
            Text('2. Check your router\'s admin panel for ESP32\'s new IP'),
            Text('3. Update the app with the new IP address'),
            Text('4. Test the connection'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 WiFi Configuration'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Current Network Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Network Info',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('WiFi: $_currentWiFi'),
                    Text('IP: $_currentIP'),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _getCurrentNetworkInfo,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Instructions
            Card(
              color: Colors.blue.shade50,
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue),
                        SizedBox(width: 8),
                        Text(
                          'Setup Instructions',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text('1. Put ESP32 in AP mode (hotspot mode)'),
                    Text('2. Connect your phone to ESP32 hotspot'),
                    Text('3. Enter your home WiFi credentials'),
                    Text('4. Send configuration to ESP32'),
                    Text('5. ESP32 will connect to your WiFi'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ESP32 IP Configuration
            Text(
              'ESP32 Configuration',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _esp32IPController,
              decoration: InputDecoration(
                labelText: 'ESP32 IP Address',
                hintText: '192.168.4.1 (AP mode) or 192.168.x.x (STA mode)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.connect_without_contact),
                  onPressed: _testESP32Connection,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // WiFi Network Selection
            Text(
              'WiFi Network Configuration',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ssidController,
                    decoration: const InputDecoration(
                      labelText: 'WiFi SSID (Network Name)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isScanning ? null : _scanAvailableNetworks,
                  icon: _isScanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_find),
                  label: const Text('Scan'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Available Networks (if any)
            if (_availableNetworks.isNotEmpty) ...[
              const Text(
                'Available Networks:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 120,
                child: ListView.builder(
                  itemCount: _availableNetworks.length,
                  itemBuilder: (context, index) {
                    final network = _availableNetworks[index];
                    return ListTile(
                      dense: true,
                      title: Text(network),
                      leading: const Icon(Icons.wifi),
                      onTap: () {
                        _ssidController.text = network;
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],

            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'WiFi Password',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),

            // Configure Button
            ElevatedButton.icon(
              onPressed: _isConfiguring ? null : _configureESP32WiFi,
              icon: _isConfiguring
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(
                _isConfiguring ? 'Configuring...' : 'Configure ESP32 WiFi',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 8),

            // Test Connection Button
            OutlinedButton.icon(
              onPressed: _testESP32Connection,
              icon: const Icon(Icons.network_ping),
              label: const Text('Test ESP32 Connection'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    _esp32IPController.dispose();
    super.dispose();
  }
}
