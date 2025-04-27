import 'dart:io'; // For File
import 'dart:convert'; // For jsonDecode
import 'package:flutter/material.dart';
import 'package:conway/helpers/auth_guard.dart';
import 'package:conway/helpers/database_helper.dart';
import '../../services/socket_service.dart';
import 'package:image_picker/image_picker.dart'; // Import image_picker
import 'package:http/http.dart' as http; // Import http
import 'package:mime/mime.dart'; // Import mime package
import 'package:http_parser/http_parser.dart'; // Import for MediaType
import '../../constants/api_config.dart'; // For API endpoint
import 'package:cached_network_image/cached_network_image.dart'; // For image display
import '../../models/user.dart' as conway_user; // Alias User model

class SettingScreen extends StatefulWidget {
  final VoidCallback? onLogout;

  const SettingScreen({super.key, this.onLogout}); // Use super parameters

  @override
  State<SettingScreen> createState() => SettingScreenState(); // Make state public
}

class SettingScreenState extends State<SettingScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final Color primaryColor = const Color(0xFF19BFB7);
  final Color secondaryColor = const Color(0xFF59A52C);

  final SocketService _socketService = SocketService();
  final ImagePicker _picker = ImagePicker(); // Initialize ImagePicker

  conway_user.User? _currentUser;
  File? _selectedImageFile; // To hold the selected image file
  bool _isUploading = false; // To show loading indicator

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    // Ensure user is authenticated
    await AuthGuard.isAuthenticated(context);
    final user = await DBHelper().getUser();
    if (mounted && user != null) {
      setState(() {
        _currentUser = user;
        _emailController.text = user.email;
        // TODO: Load fullname and username if available from backend/DB later
        // _nameController.text = user.fullname;
        // _usernameController.text = user.username;
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load user data.')),
      );
      // Maybe navigate back or handle error
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 80, // Compress image slightly
        maxWidth: 600, // Limit image width
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImageFile = File(pickedFile.path);
        });
        _uploadProfilePicture(); // Start upload immediately after picking
      } else {
        debugPrint('No image selected.');
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _uploadProfilePicture() async {
    if (_selectedImageFile == null || _currentUser == null) return;

    setState(() {
      _isUploading = true;
    });

    try {
      // Create multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(
          '${ApiConfig.baseUrl}/user/profile-picture',
        ), // Use correct endpoint
      );

      // Add the user email to the request body
      request.fields['userEmail'] = _currentUser!.email;

      // Add the image file
      request.files.add(
        await http.MultipartFile.fromPath(
          'profileImage', // Must match the name expected by backend (multer)
          _selectedImageFile!.path,
          contentType: MediaType.parse(
            lookupMimeType(_selectedImageFile!.path) ??
                'application/octet-stream',
          ), // Set Content-Type
        ),
      );

      // Send the request
      debugPrint('Uploading image to: ${request.url}');
      final streamedResponse = await request.send();

      // Get response
      final response = await http.Response.fromStream(streamedResponse);
      debugPrint('Upload response status: ${response.statusCode}');
      debugPrint('Upload response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final newProfileUrl = responseData['profileUrl'] as String?;

        if (newProfileUrl != null && mounted) {
          // Update local user object
          final updatedUser = conway_user.User(
            id: _currentUser!.id,
            email: _currentUser!.email,
            profileUrl: newProfileUrl, // Use the new URL
            // TODO: Add fullname/username if available
          );
          // Update user in local DB
          await DBHelper().insertUser(updatedUser);
          // Update state
          setState(() {
            _currentUser = updatedUser;
            _selectedImageFile =
                null; // Clear selected file after successful upload
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile picture updated!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          throw Exception('Upload successful but no profile URL returned.');
        }
      } else {
        throw Exception(
          'Failed to upload image: ${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Error uploading image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading image: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    try {
      // Disconnect Socket FIRST
      print("[SettingScreen] Disconnecting socket before logout.");
      _socketService.disconnect();

      // Clear user data from the database
      await DBHelper().deleteUser();

      // Call the onLogout callback to update app state
      if (widget.onLogout != null) {
        widget.onLogout!();
      }

      // Show success message
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Logged out successfully")));

      // Navigate to the auth wrapper which will show login screen
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error logging out: ${e.toString()}")),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get current profile URL, handling null
    final profileUrl = _currentUser?.profileUrl;
    final hasProfileUrl = profileUrl != null && profileUrl.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context), // Add back button
        ),
      ),
      body:
          _currentUser ==
                  null // Show loading indicator until user data is loaded
              ? Center(child: CircularProgressIndicator(color: primaryColor))
              : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 20.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Profile picture with edit button
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.grey[300],
                            // Display selected image temporarily or network image
                            backgroundImage:
                                _selectedImageFile != null
                                    ? FileImage(_selectedImageFile!)
                                        as ImageProvider
                                    : (hasProfileUrl
                                        ? CachedNetworkImageProvider(profileUrl)
                                        : null),
                            child:
                                _selectedImageFile == null && !hasProfileUrl
                                    ? const Icon(
                                      Icons.person,
                                      size: 50,
                                      color: Colors.white,
                                    )
                                    : null,
                          ),
                          if (_isUploading)
                            const Positioned.fill(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          // Edit button overlay
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: secondaryColor,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                onPressed:
                                    _isUploading
                                        ? null
                                        : () {
                                          // Show options to pick from camera or gallery
                                          showModalBottomSheet(
                                            context: context,
                                            builder:
                                                (context) => SafeArea(
                                                  child: Wrap(
                                                    children: <Widget>[
                                                      ListTile(
                                                        leading: const Icon(
                                                          Icons.photo_library,
                                                        ),
                                                        title: const Text(
                                                          'Photo Library',
                                                        ),
                                                        onTap: () {
                                                          _pickImage(
                                                            ImageSource.gallery,
                                                          );
                                                          Navigator.of(
                                                            context,
                                                          ).pop();
                                                        },
                                                      ),
                                                      ListTile(
                                                        leading: const Icon(
                                                          Icons.photo_camera,
                                                        ),
                                                        title: const Text(
                                                          'Camera',
                                                        ),
                                                        onTap: () {
                                                          _pickImage(
                                                            ImageSource.camera,
                                                          );
                                                          Navigator.of(
                                                            context,
                                                          ).pop();
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                          );
                                        },
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Full Name
                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Full Name',
                          prefixIcon: const Icon(
                            Icons.person,
                            color: Colors.black54,
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[200]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: primaryColor,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Username
                      TextField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          labelText: 'Username',
                          prefixIcon: const Icon(
                            Icons.person_outline,
                            color: Colors.black54,
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[200]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: primaryColor,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Email
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        readOnly:
                            true, // Email likely shouldn't be changed here
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const Icon(
                            Icons.email,
                            color: Colors.black54,
                          ),
                          filled: true,
                          fillColor: Colors.grey[100], // Indicate read-only
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[200]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[200]!),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Password (Consider a "Change Password" button instead of field)
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'New Password (Optional)',
                          prefixIcon: const Icon(
                            Icons.lock,
                            color: Colors.black54,
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[200]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: primaryColor,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Save changes button
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [primaryColor, secondaryColor],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            // TODO: Save changes (Name, Username, Password)
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Save Changes',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Delete account button
                      OutlinedButton(
                        onPressed: () {
                          // TODO: Show confirmation and delete account
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        child: const Text(
                          'Delete Account',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Logout button
                      OutlinedButton(
                        onPressed: _logout,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: primaryColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        child: Text(
                          'Logout',
                          style: TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
    );
  }
}
