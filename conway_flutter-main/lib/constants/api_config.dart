class ApiConfig {
  // Change this to your server's IP address
  static const String baseUrl = 'http://192.168.100.30:3000';

  // Authentication endpoints
  static const String requestOtp = '$baseUrl/api/request-otp';
  static const String verifyOtp = '$baseUrl/api/verify-otp';
  static const String login = '$baseUrl/api/login';
  static const String logout = '$baseUrl/api/logout';
  static const String resendOtp = '$baseUrl/api/resend-otp';
  static const String googleAuth = '$baseUrl/api/google-auth';
  static const String uploadProfilePic = '$baseUrl/api/user/profile-picture';
  // Add endpoints for profile update
  static const String updateProfile = '$baseUrl/api/user/profile';
  static const String verifyEmailChange =
      '$baseUrl/api/user/verify-email-change';
  // Add endpoint for password change
  static const String changePassword = '$baseUrl/api/user/change-password';
}
