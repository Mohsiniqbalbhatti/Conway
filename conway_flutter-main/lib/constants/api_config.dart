class ApiConfig {
  // Change this to your server's IP address
  static const String baseUrl = 'http://56.228.5.124:3000/api';

  // Authentication endpoints
  static const String requestOtp = '$baseUrl/request-otp';
  static const String verifyOtp = '$baseUrl/verify-otp';
  static const String login = '$baseUrl/login';
  static const String resendOtp = '$baseUrl/resend-otp';
  static const String googleAuth = '$baseUrl/google-auth';
}
