class ApiConfig {
  // Change this to your server's IP address
  static const String baseUrl = 'http://192.168.1.25:5000';

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
  static const String updateTimezone = '$baseUrl/api/user/timezone';
  static const String verifyEmailChange =
      '$baseUrl/api/user/verify-email-change';
  // Add endpoint for password change
  static const String changePassword = '$baseUrl/api/user/change-password';
  // Add endpoint for user search
  static const String searchUser = '$baseUrl/api/search-user';
  // Forgot Password Flow
  static const String forgotPassword = '$baseUrl/api/user/forgot-password';
  static const String verifyForgotPassword =
      '$baseUrl/api/user/forgot-password/verify';
  static const String resetPassword = '$baseUrl/api/user/forgot-password/reset';

  // User details endpoint - pass user ID
  static String getUserDetails(String userId) => '$baseUrl/api/user/$userId';
}
