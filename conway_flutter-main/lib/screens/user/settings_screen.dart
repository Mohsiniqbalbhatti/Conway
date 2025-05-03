import 'dart:io'; // For File
import 'dart:convert'; // For jsonDecode
import 'package:flutter/material.dart';
import 'package:conway/helpers/database_helper.dart';
import '../../services/socket_service.dart';
import 'package:image_picker/image_picker.dart'; // Import image_picker
import 'package:http/http.dart' as http; // Import http
import 'package:mime/mime.dart'; // Import mime package
import 'package:http_parser/http_parser.dart'; // Import for MediaType
import '../../constants/api_config.dart'; // For API endpoint
import 'package:cached_network_image/cached_network_image.dart'; // For image display
import '../../models/user.dart' as conway_user; // Alias User model
import 'user_profile_screen.dart'; // Renamed profile screen

// Define colors for consistency outside the class
const Color primaryColor = Color(0xFF19BFB7);
const Color lightBackgroundColor = Color(
  0xFFFAFAFA,
); // Slightly different shade for better contrast
const Color textFieldFillColor = Color(0xFFF0F0F0); // Adjusted fill color
const Color errorColor = Colors.redAccent;
const Color destructiveColor = Color(0xFFD32F2F); // Material Red 700

class SettingScreen extends StatefulWidget {
  final VoidCallback? onLogout;
  final conway_user.User currentUser; // Add currentUser field

  const SettingScreen({
    super.key,
    this.onLogout,
    required this.currentUser, // Require currentUser in constructor
  });

  @override
  State<SettingScreen> createState() => SettingScreenState();
}

class SettingScreenState extends State<SettingScreen> {
  // Existing controllers
  // final TextEditingController _nameController = TextEditingController(); // Moved to EditProfileScreen
  // final TextEditingController _usernameController = TextEditingController(); // Moved to EditProfileScreen
  // final TextEditingController _emailController = TextEditingController(); // Moved to EditProfileScreen

  // New controllers for password change
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final GlobalKey<FormState> _passwordFormKey = GlobalKey<FormState>();
  bool _isChangingPassword = false;
  String _changePasswordError = '';
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  final SocketService _socketService = SocketService();
  final ImagePicker _picker = ImagePicker();

  // conway_user.User? _currentUser; // Remove internal state variable
  File? _selectedImageFile;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    // _loadUserData(); // Remove call to load user data
  }

  // Future<void> _loadUserData() async { // Remove entire method
  //   await AuthGuard.isAuthenticated(context);
  //   final user = await DBHelper().getUser();
  //   if (mounted && user != null) {
  //     setState(() {
  //       _currentUser = user;
  //     });
  //   } else if (mounted) {
  //     // ... error handling ...
  //   }
  // }

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
    if (_selectedImageFile == null) return; // Check only for selected file

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
      request.fields['userEmail'] =
          widget.currentUser.email; // Use widget.currentUser

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
          // Update the user details in the local database
          await DBHelper().updateUserDetails(
            widget.currentUser.id, // Use widget.currentUser
            profileUrl: newProfileUrl,
          );

          // Create updated user object locally for immediate UI update
          // This part becomes tricky as we shouldn't modify the passed-in widget.currentUser directly.
          // The parent screen that owns the user state should be responsible for refreshing.
          // For now, just update the DB and rely on potential refresh when popping back.
          // Consider using a state management solution (Provider, Riverpod, Bloc)
          // to handle this more cleanly across screens.
          // final updatedUser = conway_user.User(
          //   id: widget.currentUser.id,
          //   email: widget.currentUser.email,
          //   fullname: widget.currentUser.fullname, // Assume fullname hasn't changed here
          //   profileUrl: newProfileUrl,
          // );
          // setState(() {
          //   // Cannot update _currentUser anymore
          //   // Maybe force a refresh on the parent?
          //   _selectedImageFile = null;
          // });

          // We can update the selected image file state though
          setState(() {
            _selectedImageFile =
                null; // Clear selection after successful upload
          });

          // Check mounted before showing snackbar
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profile picture updated!'),
                backgroundColor: Colors.green,
              ),
            );
          }
          // Optionally: Could return `true` when popping if the parent needs to know
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

  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) {
      return; // Form validation failed
    }
    // Check for user removed - using widget.currentUser directly
    // if (widget.currentUser == null) { // This check is technically unnecessary now
    //   setState(() => _changePasswordError = 'User data not loaded.');
    //   return;
    // }

    setState(() {
      _isChangingPassword = true;
      _changePasswordError = '';
    });

    try {
      final response = await http
          .put(
            Uri.parse(ApiConfig.changePassword), // Use new API endpoint
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': widget.currentUser.id, // Use widget.currentUser
              'currentPassword': _currentPasswordController.text,
              'newPassword': _newPasswordController.text,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final responseData = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 && responseData['success'] == true) {
        // Check mounted before showing snackbar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Password changed successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        // Clear password fields after success
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        // Hide keyboard
        FocusScope.of(context).unfocus();
      } else {
        setState(() {
          _changePasswordError =
              responseData['error'] ?? 'Failed to change password.';
        });
        // Show error SnackBar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_changePasswordError),
            backgroundColor: errorColor,
          ),
        );
      }
    } catch (e) {
      debugPrint('Change Password error: $e');
      if (mounted) {
        setState(() {
          _changePasswordError = 'Network error. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isChangingPassword = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    try {
      // Use passed-in user data
      // final user = await DBHelper().getUser(); // No need to fetch again
      // if (user == null) { // Check removed
      //   throw Exception('No user found to logout');
      // }

      // 1. Disconnect Socket (if connected)
      if (_socketService.isConnected) {
        debugPrint("[SettingScreen] Disconnecting socket before logout.");
        _socketService.disconnect(); // Corrected: no arguments needed
      }

      // Send logout request to backend with error handling
      try {
        final response = await http.post(
          Uri.parse(ApiConfig.logout),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': widget.currentUser.email, // Use widget.currentUser
            'userId': widget.currentUser.id, // Use widget.currentUser
          }),
        );

        if (response.statusCode != 200) {
          debugPrint(
            "Backend logout returned: ${response.statusCode} ${response.body}",
          );
          // Continue with logout even if the backend request fails
        } else {
          debugPrint("Backend logout successful");
        }
      } catch (e) {
        // Just log the error and continue with local logout
        debugPrint("Error calling logout endpoint: $e");
      }

      // Clear user data from the database
      await DBHelper().deleteUser();

      // Call the onLogout callback to update app state
      if (widget.onLogout != null) {
        widget.onLogout!();
      }

      // Show success message (ensure context is still valid)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Logged out successfully")),
        );
        // Navigate BACK instead of pushing /auth
        // Let the state change handle showing the LoginScreen
        // Ensure HomeScreen (or its parent) correctly handles rebuild
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      // Error during DB deletion or socket disconnection
      debugPrint("Logout error: $e");
      if (mounted) {
        // Add mounted check before showing SnackBar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error logging out: ${e.toString()}")),
        );
      }
    }
  }

  @override
  void dispose() {
    // Dispose new controllers
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    // Existing disposals (remove unused ones)
    // _nameController.dispose();
    // _usernameController.dispose();
    // _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use widget.currentUser directly
    final profileUrl = widget.currentUser.profileUrl;
    final hasProfileUrl = profileUrl != null && profileUrl.isNotEmpty;

    return Scaffold(
      backgroundColor: lightBackgroundColor, // Use light background
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        backgroundColor: primaryColor,
        elevation: 1, // Add subtle elevation
        iconTheme: const IconThemeData(
          color: Colors.white,
        ), // Keep back arrow white
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 20.0,
        ), // Adjusted padding
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Profile Section --- (Using Card for better separation)
            Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 25), // Space below card
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias, // Clip content to shape
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                leading: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.grey.shade300,
                      backgroundImage:
                          hasProfileUrl
                              ? CachedNetworkImageProvider(profileUrl)
                              : null,
                      child:
                          !hasProfileUrl
                              ? Icon(
                                Icons.person,
                                size: 30,
                                color: Colors.grey[600],
                              )
                              : null,
                    ),
                    // Show selected image preview before upload
                    if (_selectedImageFile != null)
                      CircleAvatar(
                        radius: 30,
                        backgroundImage: FileImage(_selectedImageFile!),
                      ),
                    if (_isUploading)
                      const Positioned.fill(
                        child: CircleAvatar(
                          // Add background to progress indicator
                          radius: 30,
                          backgroundColor: Colors.black45,
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color:
                                  Colors
                                      .white, // White indicator on dark background
                            ),
                          ),
                        ),
                      ),
                    // Add an icon button to trigger image picking
                    Positioned(
                      bottom: -5,
                      right: -10,
                      child: IconButton(
                        icon: CircleAvatar(
                          radius: 12,
                          backgroundColor: primaryColor,
                          child: Icon(
                            Icons.edit,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                        onPressed: () => _pickImage(ImageSource.gallery),
                        tooltip: 'Change profile picture',
                      ),
                    ),
                  ],
                ),
                title: Text(
                  widget.currentUser.fullname ??
                      'No Name', // Use widget.currentUser
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 17,
                  ),
                ),
                subtitle: Text(
                  widget.currentUser.email,
                ), // Use widget.currentUser
                trailing: IconButton(
                  icon: Icon(
                    Icons.edit_outlined,
                    color: primaryColor,
                  ), // Outlined edit icon
                  tooltip: 'Edit Profile',
                  onPressed: () {
                    // Removed null check, currentUser is required
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => EditProfileScreen(
                              currentUser:
                                  widget.currentUser, // Pass widget.currentUser
                            ),
                      ),
                    ).then((changesMade) {
                      // If changes were made (e.g., name updated), we should ideally refresh the user data
                      // This currently relies on the parent screen refreshing if needed.
                      // A better approach uses state management (Provider, Riverpod, etc.)
                      // to update the user state globally.
                      // For now, we can trigger a manual refresh of the parent if changes were made
                      if (changesMade == true && mounted) {
                        // Potentially pop and push again, or use a state management solution.
                        // Simplest for now: just note that parent might need refresh.
                      }
                    });
                  },
                ),
                // onTap: () => _pickImage(ImageSource.gallery), // Moved to IconButton overlay
              ),
            ),
            // const Divider(height: 30), // Remove divider, using Card now

            // --- Change Password Section Title ---
            Padding(
              padding: const EdgeInsets.only(
                left: 4.0,
                bottom: 15.0,
              ), // Indent title slightly
              child: Text(
                'Change Password',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            Form(
              key: _passwordFormKey,
              child: Column(
                children: [
                  _buildPasswordTextField(
                    controller: _currentPasswordController,
                    labelText: 'Current Password',
                    isObscured: _obscureCurrentPassword,
                    toggleVisibility:
                        () => setState(
                          () =>
                              _obscureCurrentPassword =
                                  !_obscureCurrentPassword,
                        ),
                  ),
                  const SizedBox(height: 15), // Consistent spacing
                  _buildPasswordTextField(
                    controller: _newPasswordController,
                    labelText: 'New Password',
                    isObscured: _obscureNewPassword,
                    toggleVisibility:
                        () => setState(
                          () => _obscureNewPassword = !_obscureNewPassword,
                        ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'New password cannot be empty.';
                      }
                      if (value.length < 8) {
                        return 'Password must be at least 8 characters.';
                      }
                      // Add more complex validation if needed
                      return null;
                    },
                  ),
                  const SizedBox(height: 15), // Consistent spacing
                  _buildPasswordTextField(
                    controller: _confirmPasswordController,
                    labelText: 'Confirm New Password',
                    isObscured: _obscureConfirmPassword,
                    toggleVisibility:
                        () => setState(
                          () =>
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword,
                        ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please confirm your new password.';
                      }
                      if (value != _newPasswordController.text) {
                        return 'Passwords do not match.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 25), // Space before button
                  if (_changePasswordError.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: 15,
                      ), // Space below error
                      child: Text(
                        _changePasswordError,
                        style: TextStyle(color: errorColor, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  SizedBox(
                    // Control button width
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _isChangingPassword ? null : _changePassword,
                      child:
                          _isChangingPassword
                              ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                              : const Text(
                                'CHANGE PASSWORD',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                    ),
                  ),
                  // CustomButton( // Remove old button
                  //   text: 'CHANGE PASSWORD',
                  //   isLoading: _isChangingPassword,
                  //   onPressed: _changePassword,
                  // ),
                ],
              ),
            ),
            const SizedBox(height: 30), // Space before logout
            const Divider(height: 20), // Divider before logout
            // --- Logout Button (OutlinedButton with Confirmation) ---
            Center(
              // Center the button horizontally
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 10.0,
                ), // Add vertical padding
                child: OutlinedButton.icon(
                  icon: Icon(Icons.logout, color: destructiveColor),
                  label: Text(
                    'Logout',
                    style: TextStyle(
                      color: destructiveColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: destructiveColor.withAlpha(128),
                    ), // Border color
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 12,
                    ),
                    foregroundColor: destructiveColor.withAlpha(
                      26,
                    ), // Splash color
                  ),
                  onPressed: () => _showLogoutConfirmationDialog(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Confirmation Dialog for Logout ---
  Future<void> _showLogoutConfirmationDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must tap button!
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[Text('Are you sure you want to log out?')],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Dismiss the dialog
              },
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: destructiveColor,
              ), // Style the logout action
              child: const Text('Logout'),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Dismiss the dialog
                _logout(); // Proceed with logout
              },
            ),
          ],
        );
      },
    );
  }

  // Helper for password fields (updated style)
  Widget _buildPasswordTextField({
    required TextEditingController controller,
    required String labelText,
    required bool isObscured,
    required VoidCallback toggleVisibility,
    FormFieldValidator<String>? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isObscured,
      decoration: InputDecoration(
        labelText: labelText,
        filled: true, // Use filled style
        fillColor: textFieldFillColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), // Rounded corners
          borderSide: BorderSide.none, // No border initially
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300), // Subtle border
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: primaryColor,
            width: 1.5,
          ), // Highlight focus
        ),
        prefixIcon: const Icon(
          Icons.lock_outline,
          size: 20,
        ), // Slightly smaller icon
        suffixIcon: IconButton(
          icon: Icon(
            isObscured
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 20, // Smaller icon
            color: Colors.grey.shade600, // Subtle color
          ),
          onPressed: toggleVisibility,
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 12,
        ), // Adjust padding
      ),
      validator: validator,
    );
  }
}
