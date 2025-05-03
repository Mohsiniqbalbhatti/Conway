import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:conway/models/user.dart' as conway_user;
import 'package:conway/helpers/database_helper.dart'; // To get current user
import 'package:conway/constants/api_config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:conway/screens/guest/verify_email_change_screen.dart'; // Import the new OTP screen
import 'package:image_picker/image_picker.dart'; // Import image_picker

// Rename to reflect editing capability
class EditProfileScreen extends StatefulWidget {
  // Pass the full user object for initial values
  final conway_user.User currentUser;

  const EditProfileScreen({super.key, required this.currentUser});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  final TextEditingController _passwordController =
      TextEditingController(); // For current password verification

  bool _isLoading = false;
  String _errorMessage = '';
  String? _profileUrlState; // To hold profile URL if fetched/updated

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>(); // Add form key
  final ImagePicker _picker = ImagePicker(); // Add ImagePicker instance

  // Define colors for consistency
  final Color primaryColor = const Color(0xFF19BFB7);
  final Color lightBackgroundColor = Colors.grey.shade50; // Lighter background
  final Color textFieldFillColor = Colors.grey.shade100; // Subtle fill

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.currentUser.fullname,
    ); // Use fullname from User model
    _emailController = TextEditingController(text: widget.currentUser.email);
    _profileUrlState = widget.currentUser.profileUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    // Basic validation (e.g., non-empty fields)
    if (!_formKey.currentState!.validate()) {
      return;
    }
    // Password validation is now part of the form validator
    // if (_passwordController.text.isEmpty) {
    //   setState(
    //     () => _errorMessage = 'Current password is required to save changes.',
    //   );
    //   return;
    // }

    final String currentFullname = widget.currentUser.fullname ?? '';
    final String currentEmail = widget.currentUser.email;
    final String newName = _nameController.text.trim();
    final String newEmail = _emailController.text.trim().toLowerCase();
    final String currentPassword =
        _passwordController.text; // Don't trim password

    // Check if anything actually changed
    final bool nameChanged = newName.isNotEmpty && newName != currentFullname;
    final bool emailChanged = newEmail.isNotEmpty && newEmail != currentEmail;

    if (!nameChanged && !emailChanged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No changes detected.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      Map<String, dynamic> payload = {
        'userId': widget.currentUser.id,
        'currentPassword': currentPassword,
      };
      if (nameChanged) payload['fullname'] = newName;
      if (emailChanged) payload['newEmail'] = newEmail;

      final response = await http
          .put(
            Uri.parse(ApiConfig.updateProfile),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      final responseData = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 && responseData['success'] == true) {
        final bool otpRequired = responseData['otpRequired'] ?? false;

        // Update local DB partially (name can be updated now)
        await DBHelper().updateUserDetails(
          widget.currentUser.id,
          fullname: nameChanged ? newName : null,
          // Email is only updated after OTP verification
        );

        if (otpRequired) {
          // Navigate to OTP screen
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('OTP sent to new email. Please verify.'),
              ),
            );
          }
          // Give snackbar time
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => VerifyEmailChangeScreen(
                    userId: widget.currentUser.id,
                    newEmail: newEmail, // Pass the new email
                    updatedFullname:
                        nameChanged
                            ? newName
                            : currentFullname, // Pass name for final DB update
                  ),
            ),
          ); // Consider handling result from OTP screen to refresh this one
        } else {
          // Only name was changed, update successful
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profile updated successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            // Pop back or update parent screen state
            Navigator.pop(
              context,
              true,
            ); // Pass true back to indicate changes were made
          }
        }
      } else {
        // Handle backend errors (e.g., wrong password, email taken, etc.)
        setState(() {
          _errorMessage = responseData['error'] ?? 'Failed to update profile';
        });
      }
    } catch (e) {
      debugPrint('Save Profile Changes error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Network error. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Upload image to backend and return URL
  Future<String?> _uploadImage(XFile image) async {
    try {
      // Create multipart request
      final url = Uri.parse(ApiConfig.uploadProfilePic);
      debugPrint('[UPLOAD DEBUG] Using URL: $url'); // Log the URL
      final request = http.MultipartRequest('POST', url);

      // Add fields
      // Add the userId to associate the picture with the user
      request.fields['userId'] = widget.currentUser.id.toString();

      // Add file
      request.files.add(
        await http.MultipartFile.fromPath(
          'profileImage', // Field name MUST match upload.single() in backend
          image.path,
          // Optionally set content type
          // contentType: MediaType('image', 'jpeg'), // Example
        ),
      );

      // Send request
      debugPrint(
        '[UPLOAD DEBUG] Full Request URL: ${request.url.toString()}',
      ); // Log the full request URL
      final streamedResponse = await request.send();

      // Read response
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return null;

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        // Update the state with the new URL from the response
        setState(() {
          _profileUrlState = responseData['profileUrl'] as String?;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture updated!')),
        );
        // Return the URL in case the caller needs it
        return responseData['profileUrl'] as String?;
      } else {
        // Handle upload error
        final errorBody = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Image upload failed: ${response.statusCode} - ${errorBody?['message'] ?? 'Unknown upload error'}',
            ),
          ),
        );
        return null;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading image: ${e.toString()}')),
        );
      }
      return null;
    }
  }

  // New function to handle picking and uploading
  Future<void> _pickAndUpdateProfileImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null && mounted) {
      await _uploadImage(image); // Call the existing function
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasProfileUrl =
        _profileUrlState != null && _profileUrlState!.isNotEmpty;
    // final Color primaryColor = const Color(0xFF19BFB7); // Moved color definition up

    return Scaffold(
      backgroundColor: lightBackgroundColor, // Apply light background
      appBar: AppBar(
        title: const Text(
          'Edit Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ), // Changed title
        backgroundColor: primaryColor,
        elevation: 1, // Add subtle elevation
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        // Make body scrollable
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            // Wrap content in a Form
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // --- Profile Picture ---
                InkWell(
                  onTap: _pickAndUpdateProfileImage, // Call the handler
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircleAvatar(
                        radius: 65, // Slightly larger
                        backgroundColor: Colors.grey.shade300,
                        child: CircleAvatar(
                          radius: 60,
                          backgroundColor: Colors.white, // Inner background
                          backgroundImage:
                              hasProfileUrl
                                  ? CachedNetworkImageProvider(
                                    _profileUrlState!,
                                  )
                                  : null,
                          child:
                              !hasProfileUrl
                                  ? Icon(
                                    Icons.person,
                                    size: 60,
                                    color: Colors.grey[500], // Softer color
                                  )
                                  : null,
                        ),
                      ),
                      // Consider adding an edit icon overlay later if needed
                    ],
                  ),
                ),
                const SizedBox(height: 40), // Increased spacing
                // --- Full Name Field ---
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline, color: primaryColor),
                    filled: true, // Use filled style
                    fillColor: textFieldFillColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        12,
                      ), // Rounded corners
                      borderSide:
                          BorderSide.none, // No visible border initially
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.grey.shade300,
                      ), // Subtle border
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: primaryColor,
                        width: 1.5,
                      ), // Highlight border on focus
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Full name cannot be empty';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20), // Increased spacing
                // --- Email Field ---
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email_outlined, color: primaryColor),
                    filled: true,
                    fillColor: textFieldFillColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: primaryColor, width: 1.5),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Email cannot be empty';
                    }
                    // Basic email format check (can be improved)
                    if (!RegExp(
                      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+", // More robust regex
                    ).hasMatch(value)) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20), // Increased spacing
                // --- Current Password Field (Required for saving) ---
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Current Password', // Simplified label
                    hintText: 'Required to save changes', // Hint text
                    prefixIcon: Icon(Icons.lock_outline, color: primaryColor),
                    filled: true,
                    fillColor: textFieldFillColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: primaryColor, width: 1.5),
                    ),
                  ),
                  validator: (value) {
                    // Added validator
                    if (value == null || value.isEmpty) {
                      return 'Current password is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 35), // Increased spacing
                // --- Error Message Display ---
                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: 20,
                    ), // Increased spacing
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 14,
                      ), // Slightly adjusted style
                      textAlign: TextAlign.center,
                    ),
                  ),

                // --- Save Button ---
                SizedBox(
                  // Control button width
                  width: double.infinity, // Make button wider
                  height: 50, // Standard button height
                  child: FilledButton(
                    // Use FilledButton
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          12,
                        ), // Match text field radius
                      ),
                    ),
                    onPressed: _isLoading ? null : _saveChanges,
                    child:
                        _isLoading
                            ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                            : const Text(
                              'SAVE CHANGES',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                  ),
                ),
                // CustomButton( // Remove old button
                //   text: 'SAVE CHANGES',
                //   isLoading: _isLoading,
                //   onPressed: _saveChanges,
                // ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
