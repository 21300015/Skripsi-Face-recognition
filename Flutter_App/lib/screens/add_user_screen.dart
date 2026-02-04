import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/user.dart';
import '../services/esp32_service.dart';

class AddUserScreen extends StatefulWidget {
  final User? userToEdit;

  const AddUserScreen({Key? key, this.userToEdit}) : super(key: key);

  @override
  _AddUserScreenState createState() => _AddUserScreenState();
}

class _AddUserScreenState extends State<AddUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _namaController = TextEditingController();
  final _jabatanController = TextEditingController();
  final _departemenController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoading = false;
  String _statusMessage = '';
  DateTime _masaBerlaku = DateTime.now().add(const Duration(days: 365));
  String _profileImagePath = ''; // Profile image path

  // Live enrollment state - ONLY ESP32 CAMERA
  bool _enrollmentActive = false;
  Timer? _enrollmentStatusTimer;
  String _enrollmentStatus = '';
  int _enrollmentStepsCompleted = 0;
  int _enrollmentStepsRequired = 3; // Default, will be updated from ESP32

  @override
  void initState() {
    super.initState();
    if (widget.userToEdit != null) {
      _populateEditForm();
    }
  }

  @override
  void dispose() {
    _stopEnrollmentMonitoring();
    _namaController.dispose();
    _jabatanController.dispose();
    _departemenController.dispose();
    super.dispose();
  }

  void _populateEditForm() {
    final user = widget.userToEdit!;
    _namaController.text = user.nama;
    _jabatanController.text = user.jabatan;
    _departemenController.text = user.departemen;
    _masaBerlaku = user.masaBerlaku;
    _profileImagePath = user.thumbnailPath; // Load existing profile image
  }

  Future<void> _startLiveCameraEnrollment() async {
    if (_namaController.text.trim().isEmpty) {
      _showMessage('Please enter user name first', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
      _enrollmentActive = true;
      _enrollmentStepsCompleted = 0;
      _statusMessage = 'Starting live camera enrollment...';
    });

    try {
      // Start live enrollment on ESP32
      final success = await ESP32Service.startEnrollment(
        _namaController.text.trim(),
      );

      if (success) {
        _startEnrollmentMonitoring();
        _showMessage(
          'Live enrollment started! Look at the ESP32 camera and follow instructions.',
        );
      } else {
        _stopEnrollment();
        _showMessage(
          'Failed to start enrollment. Check ESP32 connection.',
          isError: true,
        );
      }
    } catch (e) {
      _stopEnrollment();
      _showMessage('Error: $e', isError: true);
    }
  }

  void _startEnrollmentMonitoring() {
    _enrollmentStatusTimer = Timer.periodic(const Duration(milliseconds: 800), (
      timer,
    ) async {
      try {
        final status = await ESP32Service.getEnrollmentStatus();
        if (status != null) {
          setState(() {
            _enrollmentStatus = status['message'] ?? 'Enrolling...';
            _enrollmentStepsCompleted = status['steps_completed'] ?? 0;
            _enrollmentStepsRequired = status['steps_required'] ?? 3;

            if (status['complete'] == true) {
              _completeEnrollment();
            }
          });
        }
      } catch (e) {
        // Error checking enrollment status handled silently
      }
    });
  }

  void _stopEnrollmentMonitoring() {
    _enrollmentStatusTimer?.cancel();
    _enrollmentStatusTimer = null;
  }

  Future<void> _cancelEnrollment() async {
    try {
      await ESP32Service.cancelEnrollment();
    } catch (e) {
      // Error cancelling enrollment handled silently
    }
    _stopEnrollment();
  }

  void _stopEnrollment() {
    _stopEnrollmentMonitoring();
    setState(() {
      _enrollmentActive = false;
      _isLoading = false;
      _enrollmentStatus = '';
      _statusMessage = '';
      _enrollmentStepsCompleted = 0;
    });
  }

  Future<void> _completeEnrollment() async {
    _stopEnrollmentMonitoring();

    setState(() {
      _enrollmentActive = false;
      _isLoading = false;
    });

    // Show profile image selection dialog
    await _showProfileImageDialog();
  }

  Future<void> _showProfileImageDialog() async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('✅ Face Enrolled Successfully!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Would you like to add a profile photo for this user?'),
            const SizedBox(height: 16),
            // Show current profile image if selected
            if (_profileImagePath.isNotEmpty)
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  image: DecorationImage(
                    image: FileImage(File(_profileImagePath)),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'skip'),
            child: const Text('Skip'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.photo_library),
            label: const Text('Gallery'),
            onPressed: () => Navigator.pop(context, 'gallery'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.camera_alt),
            label: const Text('Camera'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(context, 'camera'),
          ),
        ],
      ),
    );

    if (result == 'gallery') {
      await _pickImageFromGallery();
    } else if (result == 'camera') {
      await _captureImageFromCamera();
    }

    // Save user and finish
    await _finishAndSaveUser();
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image != null) {
        await _saveProfileImage(image.path);
      }
    } catch (e) {
      _showMessage('Error selecting image: $e', isError: true);
    }
  }

  Future<void> _captureImageFromCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );

      if (image != null) {
        await _saveProfileImage(image.path);
      }
    } catch (e) {
      _showMessage('Error capturing image: $e', isError: true);
    }
  }

  Future<void> _saveProfileImage(String sourcePath) async {
    try {
      // Get app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final profilesDir = Directory('${appDir.path}/profiles');

      // Create profiles directory if it doesn't exist
      if (!await profilesDir.exists()) {
        await profilesDir.create(recursive: true);
      }

      // Copy image to app directory with user ID
      final fileName =
          '${_namaController.text.trim().replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final destPath = '${profilesDir.path}/$fileName';

      await File(sourcePath).copy(destPath);

      setState(() {
        _profileImagePath = destPath;
      });

      _showMessage('Profile image saved!');
    } catch (e) {
      _showMessage('Error saving image: $e', isError: true);
    }
  }

  Future<void> _finishAndSaveUser() async {
    try {
      // Save user to local database
      await _saveUser();
      _showMessage('User enrolled successfully!');

      // Return to previous screen after delay
      Timer(const Duration(seconds: 2), () {
        Navigator.of(context).pop(true);
      });
    } catch (e) {
      _showMessage('Error saving user: $e', isError: true);
    }
  }

  Future<void> _saveUser() async {
    if (!_formKey.currentState!.validate()) return;

    final userBox = Hive.box<User>('users');
    final userName = _namaController.text.trim();

    final user = User(
      id: widget.userToEdit?.id ?? DateTime.now().millisecondsSinceEpoch,
      nama: userName,
      jabatan: _jabatanController.text.trim(),
      departemen: _departemenController.text.trim(),
      masaBerlaku: _masaBerlaku,
      thumbnailPath: _profileImagePath, // Save profile image path
    );

    await userBox.put(user.id, user);
    await ESP32Service.addUser(user);

    // Upload profile image to ESP32 SD card if available
    if (_profileImagePath.isNotEmpty) {
      final imageFile = File(_profileImagePath);
      if (imageFile.existsSync()) {
        // Upload in background - don't block enrollment
        ESP32Service.uploadProfileImage(userName, imageFile).then((success) {
          if (success) {
            debugPrint('[PROFILE] Image uploaded to ESP32 SD card: $userName');
          }
        });
      }
    }
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
        title: Text(widget.userToEdit == null ? 'Add User' : 'Edit User'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // User Information Form
                TextFormField(
                  controller: _namaController,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter user name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _jabatanController,
                  decoration: const InputDecoration(
                    labelText: 'Position',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _departemenController,
                  decoration: const InputDecoration(
                    labelText: 'Department',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Expiry Date
                ListTile(
                  title: const Text('Access Expiry'),
                  subtitle: Text(
                    '${_masaBerlaku.day}/${_masaBerlaku.month}/${_masaBerlaku.year}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _masaBerlaku,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (date != null) {
                      setState(() => _masaBerlaku = date);
                    }
                  },
                ),
                const SizedBox(height: 24),

                // ESP32 Camera Enrollment Section ONLY
                Card(
                  color: _enrollmentActive
                      ? Colors.orange.shade50
                      : Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Icon(
                          _enrollmentActive ? Icons.camera_alt : Icons.face,
                          size: 48,
                          color: _enrollmentActive
                              ? Colors.orange
                              : Colors.blue,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _enrollmentActive
                              ? 'ENROLLING VIA ESP32 CAMERA...'
                              : 'READY FOR ESP32 CAMERA ENROLLMENT',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _enrollmentActive
                                ? Colors.orange
                                : Colors.blue,
                          ),
                        ),
                        if (_enrollmentStatus.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _enrollmentStatus,
                            style: const TextStyle(fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ],

                        // Progress bar for enrollment steps
                        if (_enrollmentActive) ...[
                          const SizedBox(height: 16),
                          Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(_enrollmentStepsRequired, (
                                  index,
                                ) {
                                  final isCompleted =
                                      index < _enrollmentStepsCompleted;
                                  final isActive =
                                      index == _enrollmentStepsCompleted;
                                  return Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isCompleted
                                                ? Colors.green
                                                : isActive
                                                ? Colors.orange
                                                : Colors.grey.shade300,
                                            border: isActive
                                                ? Border.all(
                                                    color: Colors.orange,
                                                    width: 3,
                                                  )
                                                : null,
                                          ),
                                          child: Center(
                                            child: isCompleted
                                                ? const Icon(
                                                    Icons.check,
                                                    color: Colors.white,
                                                    size: 24,
                                                  )
                                                : isActive
                                                ? const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                            Color
                                                          >(Colors.white),
                                                    ),
                                                  )
                                                : Text(
                                                    '${index + 1}',
                                                    style: TextStyle(
                                                      color:
                                                          Colors.grey.shade600,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Step ${index + 1}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: isCompleted
                                                ? Colors.green
                                                : Colors.grey,
                                            fontWeight: isCompleted
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ),
                              const SizedBox(height: 12),
                              LinearProgressIndicator(
                                value: _enrollmentStepsRequired > 0
                                    ? _enrollmentStepsCompleted /
                                          _enrollmentStepsRequired
                                    : 0,
                                backgroundColor: Colors.grey.shade300,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  _enrollmentStepsCompleted >=
                                          _enrollmentStepsRequired
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                                minHeight: 8,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${_enrollmentStepsCompleted}/${_enrollmentStepsRequired} captures completed',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      _enrollmentStepsCompleted >=
                                          _enrollmentStepsRequired
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),

                        if (!_enrollmentActive) ...[
                          const Text(
                            'ELOQUENT FACE RECOGNITION ENROLLMENT:\n'
                            '1. Fill in user details above\n'
                            '2. Click "Start ESP32 Camera Enrollment"\n'
                            '3. Look directly at the ESP32 camera\n'
                            '4. System will capture 3 face samples automatically\n'
                            '5. Enrollment completes when all samples are captured',
                            style: TextStyle(fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _isLoading
                                ? null
                                : _startLiveCameraEnrollment,
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Start ESP32 Camera Enrollment'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 24,
                              ),
                            ),
                          ),
                        ] else ...[
                          const Text(
                            'Enrollment in progress...\n'
                            'Position your face in front of the ESP32 camera.\n'
                            'Hold still for each capture step.',
                            style: TextStyle(fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _cancelEnrollment,
                            icon: const Icon(Icons.cancel),
                            label: const Text('Cancel Enrollment'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Status Message
                if (_statusMessage.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _statusMessage,
                      style: const TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Loading indicator
                if (_isLoading) ...[
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
