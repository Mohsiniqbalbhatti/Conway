import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;

class CryptoHelper {
  // IMPORTANT: Replace with your actual secure key stored safely!
  // This key should ideally be fetched from a secure configuration or environment variable.
  // static const String _base64Key = 'YOUR_SECURE_32_BYTE_BASE64_ENCODED_KEY_HERE';

  // Remove the unused _key field
  // final encrypt.Key _key;
  final encrypt.IV _iv;
  final encrypt.Encrypter _encrypter;

  // Private constructor
  CryptoHelper._internal(this._iv, this._encrypter);

  // Singleton instance
  static CryptoHelper? _instance;

  // Factory constructor to initialize and return the singleton instance
  factory CryptoHelper() {
    if (_instance == null) {
      // --- Key Management ---
      // Fetch your key securely here. Example using a hardcoded placeholder:
      const String base64Key = 'YOUR_SECURE_32_BYTE_BASE64_ENCODED_KEY_HERE';
      // WARNING: Do NOT keep the key hardcoded like this in production.
      // Consider environment variables, secure storage, or a configuration service.

      if (base64Key == 'YOUR_SECURE_32_BYTE_BASE64_ENCODED_KEY_HERE') {
        print(
          '\n\n*** WARNING: Using placeholder encryption key in CryptoHelper! Replace this immediately. ***\n\n',
        );
        // You might throw an error here in production builds
        // throw Exception("Encryption key not configured!");
      }

      final key = encrypt.Key.fromBase64(base64Key);
      // For AES, IV length must be 16 bytes (128 bits)
      final iv = encrypt.IV.fromLength(
        16,
      ); // Generate a random IV or use a fixed one (less secure)
      // Consider generating and storing IVs per encryption if needed

      final encrypter = encrypt.Encrypter(encrypt.AES(key));

      _instance = CryptoHelper._internal(iv, encrypter);
    }
    return _instance!;
  }

  String encryptText(String plainText) {
    try {
      final encrypted = _encrypter.encrypt(plainText, iv: _iv);
      return encrypted.base64;
    } catch (e) {
      print("Encryption Error: $e");
      return plainText; // Return original on error? Or handle differently.
    }
  }

  String decryptText(String encryptedText) {
    try {
      final encryptedData = encrypt.Encrypted.fromBase64(encryptedText);
      final decrypted = _encrypter.decrypt(encryptedData, iv: _iv);
      return decrypted;
    } catch (e) {
      print("Decryption Error: $e - Input: $encryptedText");
      // Handle error appropriately - maybe return the encrypted text or a specific error message?
      // Returning the encrypted text might leak it in the UI.
      return '{Decryption Failed}';
    }
  }
}
