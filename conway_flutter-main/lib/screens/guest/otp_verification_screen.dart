import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../constants/colors.dart';
import '../../constants/api_config.dart';
import '../../widgets/custom_button.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String email;
  final VoidCallback onVerificationComplete;

  const OtpVerificationScreen({
    Key? key,
    required this.email,
    required this.onVerificationComplete,
  }) : super(key: key);

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    6,
    (_) => FocusNode(),
  );
  
  bool _isLoading = false;
  bool _isResending = false;
  String _errorMessage = '';
  int _remainingTime = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _remainingTime = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingTime > 0) {
          _remainingTime--;
        } else {
          _timer?.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    _timer?.cancel();
    super.dispose();
  }

  String get _otpCode {
    return _otpControllers.map((controller) => controller.text).join();
  }

  void _onOtpDigitChanged(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpCode.length != 6) {
      setState(() {
        _errorMessage = 'Please enter all 6 digits';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await http.post(
        Uri.parse(ApiConfig.verifyOtp),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': widget.email,
          'otp': _otpCode,
        }),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Connection timed out. Server might be unreachable.');
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Show success toast
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        
        // Allow time for the toast to be visible before navigating away
        await Future.delayed(const Duration(milliseconds: 1500));
        
        if (!mounted) return;
        Navigator.pop(context);
        widget.onVerificationComplete();
      } else {
        setState(() {
          _errorMessage = responseData['message'] ?? 'Failed to verify OTP';
        });
      }
    } catch (e) {
      print('OTP verification error details: $e');
      
      String errorMessage = 'Network error. Please try again later.';
      
      if (e.toString().contains('SocketException') || 
          e.toString().contains('Connection refused') ||
          e.toString().contains('Network is unreachable')) {
        errorMessage = 'Cannot connect to server. Check your network connection and server address.';
      } else if (e.toString().contains('timed out')) {
        errorMessage = 'Connection timed out. Server might be unreachable.';
      } else if (e is FormatException) {
        errorMessage = 'Invalid response from server. Please try again.';
      }
      
      setState(() {
        _errorMessage = errorMessage;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _resendOtp() async {
    if (_remainingTime > 0) return;

    setState(() {
      _isResending = true;
      _errorMessage = '';
    });

    try {
      final response = await http.post(
        Uri.parse(ApiConfig.resendOtp),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': widget.email,
        }),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Connection timed out. Server might be unreachable.');
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Clear all OTP input fields
        for (var controller in _otpControllers) {
          controller.clear();
        }
        
        // Set focus to the first field
        if (_focusNodes.isNotEmpty) {
          _focusNodes[0].requestFocus();
        }
        
        _startTimer();
        setState(() {
          _errorMessage = '';
        });
        
        // Show success toast
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('New OTP sent to your email'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() {
          _errorMessage = responseData['message'] ?? 'Failed to resend OTP';
        });
      }
    } catch (e) {
      print('Resend OTP error details: $e');
      
      String errorMessage = 'Network error. Please try again later.';
      
      if (e.toString().contains('SocketException') || 
          e.toString().contains('Connection refused') ||
          e.toString().contains('Network is unreachable')) {
        errorMessage = 'Cannot connect to server. Check your network connection and server address.';
      } else if (e.toString().contains('timed out')) {
        errorMessage = 'Connection timed out. Server might be unreachable.';
      } else if (e is FormatException) {
        errorMessage = 'Invalid response from server. Please try again.';
      }
      
      setState(() {
        _errorMessage = errorMessage;
      });
    } finally {
      setState(() {
        _isResending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primaryColor),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              const Text(
                'OTP Verification',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryColor,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Enter the 6-digit code sent to',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                widget.email,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(
                  6,
                  (index) => _buildOtpTextField(index),
                ),
              ),
              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 40),
              CustomButton(
                text: 'VERIFY',
                isLoading: _isLoading,
                onPressed: _verifyOtp,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Didn\'t receive the code? ',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  _remainingTime > 0
                      ? Text(
                          'Resend in ${_remainingTime}s',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : GestureDetector(
                          onTap: _isResending ? null : _resendOtp,
                          child: _isResending
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primaryColor,
                                  ),
                                )
                              : const Text(
                                  'Resend',
                                  style: TextStyle(
                                    color: AppColors.primaryColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOtpTextField(int index) {
    return SizedBox(
      width: 45,
      height: 50,
      child: TextField(
        controller: _otpControllers[index],
        focusNode: _focusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          counterText: '',
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.primaryColor, width: 2),
          ),
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
        onChanged: (value) => _onOtpDigitChanged(index, value),
      ),
    );
  }
} 