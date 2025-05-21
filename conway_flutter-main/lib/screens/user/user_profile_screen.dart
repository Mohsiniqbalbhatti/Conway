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
import 'package:intl/intl.dart';

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
  DateTime? _dateOfBirth;

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

    // Ensure we're correctly setting the initial date of birth
    _dateOfBirth = widget.currentUser.dateOfBirth;
    debugPrint(
      "[EditProfileScreen] InitState with dateOfBirth: ${widget.currentUser.dateOfBirth}",
    );
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

    // ADD DEBUG PRINT FOR TIMEZONE
    debugPrint(
      '[EditProfileScreen] Timezone from widget.currentUser.timezone before creating payload: ${widget.currentUser.timezone}',
    );

    final String currentFullname = widget.currentUser.fullname ?? '';
    final String currentEmail = widget.currentUser.email;
    final String newName = _nameController.text.trim();
    final String newEmail = _emailController.text.trim().toLowerCase();
    final String currentPassword =
        _passwordController.text; // Don't trim password

    // Fix DOB comparison - compare dates more accurately
    final DateTime? initialDateOfBirth = widget.currentUser.dateOfBirth;

    // Debug DOB values
    debugPrint('Initial DOB: ${initialDateOfBirth?.toIso8601String()}');
    debugPrint('New DOB: ${_dateOfBirth?.toIso8601String()}');

    // A proper date comparison that handles null values
    final bool dobChanged =
        (_dateOfBirth != null && initialDateOfBirth == null) ||
        (initialDateOfBirth != null && _dateOfBirth == null) ||
        (_dateOfBirth != null &&
            initialDateOfBirth != null &&
            !_isSameDate(_dateOfBirth!, initialDateOfBirth));

    // Debug change detection
    debugPrint('DOB changed: $dobChanged');

    // Check if anything actually changed
    final bool nameChanged = newName.isNotEmpty && newName != currentFullname;
    final bool emailChanged = newEmail.isNotEmpty && newEmail != currentEmail;
    final bool onlyDobChanged = !nameChanged && !emailChanged && dobChanged;

    if (!nameChanged && !emailChanged && !dobChanged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No changes detected.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Password is required UNLESS only the date of birth was changed
    if (currentPassword.isEmpty && !onlyDobChanged) {
      setState(
        () => _errorMessage = 'Current password is required to save changes.',
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
        'timezone': widget.currentUser.timezone ?? 'UTC',
      };

      // Only include password if required
      if (!onlyDobChanged) {
        payload['currentPassword'] = currentPassword;
      }

      if (nameChanged) payload['fullname'] = newName;
      if (emailChanged) payload['newEmail'] = newEmail;

      // Always include dateOfBirth in payload when it's changed, using UTC to normalize
      if (dobChanged) {
        if (_dateOfBirth != null) {
          // Normalize to UTC midnight to ensure consistent date handling
          final utcDate = DateTime.utc(
            _dateOfBirth!.year,
            _dateOfBirth!.month,
            _dateOfBirth!.day,
          );
          payload['dateOfBirth'] = utcDate.toIso8601String();
          debugPrint(
            'Including normalized DOB in payload: ${utcDate.toIso8601String()}',
          );
        } else {
          payload['dateOfBirth'] = null;
          debugPrint('Including null DOB in payload');
        }
      }

      debugPrint('Sending payload to server: ${jsonEncode(payload)}');

      final response = await http
          .put(
            Uri.parse(ApiConfig.updateProfile),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      final responseData = jsonDecode(response.body);

      // Debug print to check server response
      debugPrint('Server response: ${response.body}');

      if (!mounted) return;

      if (response.statusCode == 200 && responseData['success'] == true) {
        final bool otpRequired = responseData['otpRequired'] ?? false;

        // After successful update, fetch the latest user data from the backend
        conway_user.User updatedUser;

        if (!otpRequired) {
          try {
            // Fetch the latest user data from the backend
            final userResponse = await http
                .get(
                  Uri.parse(ApiConfig.getUserDetails(widget.currentUser.id)),
                  headers: {'Content-Type': 'application/json'},
                )
                .timeout(const Duration(seconds: 10));

            if (userResponse.statusCode == 200) {
              final userData = jsonDecode(userResponse.body);

              // Create user model from fetched data
              updatedUser = conway_user.User(
                id: widget.currentUser.id,
                email: userData['email'] ?? widget.currentUser.email,
                fullname: userData['fullname'],
                profileUrl: userData['profileUrl'],
                dateOfBirth:
                    userData['dateOfBirth'] != null
                        ? DateTime.tryParse(userData['dateOfBirth'])
                        : _dateOfBirth, // Fallback to selected date if server doesn't return it
              );

              // Update local DB with the latest data from server
              await DBHelper().updateUserDetails(
                updatedUser.id,
                fullname: updatedUser.fullname,
                email: updatedUser.email,
                dateOfBirth: updatedUser.dateOfBirth,
                profileUrl: updatedUser.profileUrl,
              );
            } else {
              // If fetching latest data fails, fallback to our local update
              updatedUser = conway_user.User(
                id: widget.currentUser.id,
                email:
                    emailChanged && !otpRequired
                        ? newEmail
                        : widget.currentUser.email,
                fullname: nameChanged ? newName : widget.currentUser.fullname,
                profileUrl: widget.currentUser.profileUrl,
                dateOfBirth:
                    _dateOfBirth, // Always use the selected date of birth
              );

              // Update local DB with our changes
              await DBHelper().updateUserDetails(
                widget.currentUser.id,
                fullname: nameChanged ? newName : null,
                email: emailChanged && !otpRequired ? newEmail : null,
                dateOfBirth: dobChanged ? _dateOfBirth : null,
              );
            }
          } catch (e) {
            // If fetching latest data fails, fallback to our local update
            debugPrint('Error fetching updated user data: $e');
            updatedUser = conway_user.User(
              id: widget.currentUser.id,
              email:
                  emailChanged && !otpRequired
                      ? newEmail
                      : widget.currentUser.email,
              fullname: nameChanged ? newName : widget.currentUser.fullname,
              profileUrl: widget.currentUser.profileUrl,
              dateOfBirth:
                  _dateOfBirth, // Always use the selected date of birth
            );

            // Update local DB with our changes
            await DBHelper().updateUserDetails(
              widget.currentUser.id,
              fullname: nameChanged ? newName : null,
              email: emailChanged && !otpRequired ? newEmail : null,
              dateOfBirth: dobChanged ? _dateOfBirth : null,
            );
          }

          // Show a brief success message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile updated successfully.'),
              duration: Duration(seconds: 2),
            ),
          );

          // Go back to the previous screen and pass the updated user object
          Navigator.pop(context, updatedUser);
        } else {
          // For OTP case, we can't refresh email yet as it's pending verification
          updatedUser = conway_user.User(
            id: widget.currentUser.id,
            email: widget.currentUser.email, // Don't update email yet
            fullname: nameChanged ? newName : widget.currentUser.fullname,
            profileUrl: widget.currentUser.profileUrl,
            dateOfBirth: _dateOfBirth, // Always use selected date
          );

          // Update local DB
          await DBHelper().updateUserDetails(
            widget.currentUser.id,
            fullname: nameChanged ? newName : null,
            dateOfBirth: dobChanged ? _dateOfBirth : null,
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
                    (context) => VerifyEmailChangeScreen(
                      userId: widget.currentUser.id,
                      newEmail: newEmail,
                    ),
              ),
            ).then((result) {
              if (result == true) {
                // If email verification was successful
                setState(() {
                  _errorMessage = '';
                  _emailController.text = newEmail;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Email changed successfully.')),
                );
              }
            });
          }
        }
      } else {
        // Handle errors from the API
        String errorMessage = responseData['error'] ?? 'Update failed.';
        setState(() {
          _errorMessage = errorMessage;
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

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final initialDate =
        _dateOfBirth ?? DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() {
        _dateOfBirth = picked;
      });
    }
  }

  // Helper method to compare two dates ignoring time component
  bool _isSameDate(DateTime date1, DateTime date2) {
    // Normalize dates to remove time component completely
    final normalizedDate1 = DateTime.utc(date1.year, date1.month, date1.day);
    final normalizedDate2 = DateTime.utc(date2.year, date2.month, date2.day);

    debugPrint(
      'Comparing dates: ${normalizedDate1.toIso8601String()} and ${normalizedDate2.toIso8601String()}',
    );
    return normalizedDate1.isAtSameMomentAs(normalizedDate2);
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
                    hintText:
                        'Required for name/email changes', // Updated hint text
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
                    // Get current form values to check if only DOB changed
                    final String currentFullname =
                        widget.currentUser.fullname ?? '';
                    final String currentEmail = widget.currentUser.email;
                    final String newName = _nameController.text.trim();
                    final String newEmail =
                        _emailController.text.trim().toLowerCase();
                    final bool nameChanged =
                        newName.isNotEmpty && newName != currentFullname;
                    final bool emailChanged =
                        newEmail.isNotEmpty && newEmail != currentEmail;

                    // Password is only required if changing name or email
                    if ((nameChanged || emailChanged) &&
                        (value == null || value.isEmpty)) {
                      return 'Password required for name/email changes';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _pickDateOfBirth,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Date of Birth',
                      prefixIcon: Icon(Icons.cake, color: primaryColor),
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
                    child: Text(
                      _dateOfBirth != null
                          ? DateFormat.yMMMd().format(_dateOfBirth!)
                          : 'Select your birth date',
                      style: TextStyle(
                        color:
                            _dateOfBirth != null
                                ? Colors.black87
                                : Colors.grey[600],
                      ),
                    ),
                  ),
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
