import 'dart:async';
import 'dart:convert';
// import 'package:conway/models/user.dart' as conway_user; // Removed unused import
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pinput/pinput.dart';
import 'package:conway/helpers/database_helper.dart'; // To update local user
import 'package:conway/constants/colors.dart';
import 'package:conway/constants/api_config.dart';
// import 'package:conway/widgets/custom_button.dart'; // Remove unused import

// Define colors here if not importing from constants/colors.dart
const Color primaryColor = Color(0xFF19BFB7);
const Color lightBackgroundColor = Color(0xFFFAFAFA);
const Color textFieldFillColor = Color(0xFFF0F0F0);
const Color errorColor = Colors.redAccent;

class VerifyEmailChangeScreen extends StatefulWidget {
  final String userId;
  final String newEmail;
  final String? updatedFullname; // Pass the new name if it was also changed

  const VerifyEmailChangeScreen({
    super.key,
    required this.userId,
    required this.newEmail,
    this.updatedFullname,
  });

  @override
  State<VerifyEmailChangeScreen> createState() =>
      _VerifyEmailChangeScreenState();
}

class _VerifyEmailChangeScreenState extends State<VerifyEmailChangeScreen> {
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocusNode = FocusNode();
  bool _isLoading = false;
  String _errorMessage = '';

  // Define colors locally or import
  // final Color primaryColor = const Color(0xFF19BFB7);
  // final Color lightBackgroundColor = Colors.grey.shade50;
  // final Color textFieldFillColor = Colors.grey.shade100;
  // final Color errorColor = Colors.redAccent;

  @override
  void dispose() {
    _otpController.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  Future<void> _verifyEmailChangeOtp(String otpCode) async {
    if (otpCode.length != 6) {
      setState(() => _errorMessage = 'Please enter a valid 6-digit OTP');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await http
          .post(
            Uri.parse(
              ApiConfig.verifyEmailChange,
            ), // Use the correct API endpoint
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': widget.userId,
              'otp': otpCode,
              // 'newEmail': widget.newEmail, // Backend gets new email from user document
            }),
          )
          .timeout(const Duration(seconds: 15));

      final responseData = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 && responseData['success'] == true) {
        final Map<String, dynamic>? updatedUserJson = responseData['user'];

        // Update local database with confirmed new details
        await DBHelper().updateUserDetails(
          widget.userId,
          // Use updated name if provided, otherwise keep original (or fetch if needed)
          // For simplicity, let's assume the parent screen handles refreshing/passing updated user
          // Or update specific fields if backend returns them:
          email: widget.newEmail, // Use the new email that was verified
          fullname: widget.updatedFullname, // Use the updated name if passed
          // profileUrl: keep existing or update if backend returns it
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email address updated successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          // Pop back potentially two screens (OTP -> Profile -> Settings)
          // Or use a result to signal profile screen to refresh
          int popCount = 0;
          Navigator.of(
            context,
          ).popUntil((_) => popCount++ >= 1); // Pop OTP screen
          // Consider passing true back to profile screen to trigger refresh
        }
      } else {
        setState(() {
          _errorMessage = responseData['error'] ?? 'Failed to verify OTP';
        });
      }
    } catch (e) {
      print('Verify Email Change OTP error: $e');
      if (mounted) {
        setState(() {
          _errorMessage =
              'Network error. Please try again.'; // Simplified error
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultPinTheme = PinTheme(
      width: 50, // Slightly wider
      height: 55, // Slightly taller
      textStyle: const TextStyle(
        fontSize: 22, // Larger font
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
      decoration: BoxDecoration(
        color: textFieldFillColor, // Use themed fill color
        borderRadius: BorderRadius.circular(12), // More rounded
        border: Border.all(color: Colors.grey.shade300), // Subtle border
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration!.copyWith(
        border: Border.all(color: primaryColor, width: 2), // Use primary color
      ),
    );

    // Define submitted and error themes if needed for visual feedback
    final submittedPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration!.copyWith(
        color: Colors.teal.shade50, // Example: light teal background on submit
      ),
    );
    final errorPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration!.copyWith(
        border: Border.all(color: errorColor), // Use error color
      ),
    );

    return Scaffold(
      backgroundColor: lightBackgroundColor, // Use light background
      appBar: AppBar(
        title: const Text(
          'Verify New Email',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        backgroundColor: primaryColor, // Use primary color
        elevation: 1, // Add subtle elevation
        iconTheme: const IconThemeData(color: Colors.white), // White back arrow
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 30,
          ), // Adjusted padding
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Text(
                'Enter OTP',
                style: TextStyle(
                  fontSize: 26, // Slightly smaller
                  fontWeight: FontWeight.bold,
                  color: primaryColor, // Use primary color
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Enter the 6-digit code sent to',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[700],
                  ), // Darker grey
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.newEmail, // Show the new email address
                style: const TextStyle(
                  fontSize: 17, // Slightly larger
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 45), // Increased spacing
              Pinput(
                length: 6,
                controller: _otpController,
                focusNode: _otpFocusNode,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                defaultPinTheme: defaultPinTheme,
                focusedPinTheme: focusedPinTheme,
                submittedPinTheme: submittedPinTheme, // Apply submitted theme
                errorPinTheme: errorPinTheme, // Apply error theme
                pinputAutovalidateMode: PinputAutovalidateMode.onSubmit,
                showCursor: true,
                cursor: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 9),
                      width: 22,
                      height: 2,
                      color: primaryColor,
                    ),
                  ],
                ),
                onCompleted: _verifyEmailChangeOtp,
                onChanged: (value) {
                  if (_errorMessage.isNotEmpty && value.isNotEmpty) {
                    setState(() => _errorMessage = '');
                  }
                },
              ),
              const SizedBox(height: 25), // Spacer
              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 15,
                  ), // Error message padding
                  child: Text(
                    _errorMessage,
                    style: TextStyle(
                      color: errorColor,
                      fontSize: 14,
                    ), // Use themed error color
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 30), // Increased spacing
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed:
                      _isLoading
                          ? null
                          : () => _verifyEmailChangeOtp(_otpController.text),
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
                            'VERIFY EMAIL',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                ),
              ),
              // CustomButton( // Remove old button
              //   text: 'VERIFY EMAIL',
              //   isLoading: _isLoading,
              //   onPressed: () => _verifyEmailChangeOtp(_otpController.text),
              // ),
              const SizedBox(height: 20), // Space at bottom
              // Consider adding a resend option for email change OTP?
              // Requires another backend endpoint to resend based on pendingEmail.
            ],
          ),
        ),
      ),
    );
  }
}
