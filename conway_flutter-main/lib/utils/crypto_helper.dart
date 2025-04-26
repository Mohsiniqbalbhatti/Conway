import 'package:encrypt/encrypt.dart' as encrypt;

class CryptoHelper {
  // IMPORTANT: Store this key securely. 
  // Hardcoding is NOT secure for production.
  // This MUST match the key in your server's .env file.
  static const String _keyString = 'fe3ee557c292ace20f4e37d87a0d05475599f496fb3964aaeba81bb8f4282a17';

  static final encrypt.Key _key = encrypt.Key.fromBase16(_keyString);
  // IV is handled per message (extracted from received, generated for sending)
  // static final encrypt.IV _iv = encrypt.IV.fromLength(16); // Not used directly like this

  static final encrypt.Encrypter _encrypter = encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc));

  static String encryptText(String plainText) {
    // DISABLED: Return plain text
    print("[Crypto DISABLED] encryptText called, returning plain text: $plainText");
    return plainText;
    /* // Original logic commented out
    try {
      final iv = encrypt.IV.fromSecureRandom(16);
      final encrypted = _encrypter.encrypt(plainText, iv: iv);
      return iv.base16 + ':' + encrypted.base64;
    } catch (e) {
      print("Encryption Error: $e");
      return plainText;
    }
    */
  }

  static String decryptText(String text) {
    // DISABLED: Return input text
    print("[Crypto DISABLED] decryptText called, returning input text: $text");
    return text;
    /* // Original logic commented out
    print("[DECRYPT HELPER] Attempting to decrypt: $text");
    if (text == '[Decryption Error]' || text == '[Invalid Payload Format]' || !text.contains(':')) {
         print("[DECRYPT HELPER] Input is placeholder or invalid format, returning as is.");
         return text; // Avoid trying to decrypt placeholders or invalid formats
    }
    
    dynamic decryptedResult;
    StackTrace? errorStackTrace;

    try {
      final parts = text.split(':');
      if (parts.length != 2) {
        print("[DECRYPT HELPER] Error: Invalid format. Parts count: ${parts.length}");
        return '[Invalid Format]'; // Return specific error
      }
      final ivHex = parts[0];
      final encryptedPayload = parts[1];
      print("[DECRYPT HELPER] IV (hex): $ivHex");
      print("[DECRYPT HELPER] Payload (base64): $encryptedPayload");
      
      final iv = encrypt.IV.fromBase16(ivHex);
      if (!RegExp(r'^[A-Za-z0-9+/=]*$').hasMatch(encryptedPayload)) { // Allow empty payload, fix regex
          print("[DECRYPT HELPER] Error: Payload is not valid Base64.");
          return '[Invalid Payload Format]';
      }

      final encryptedValue = encrypt.Encrypted.fromBase64(encryptedPayload);
      
      // *** THE DECRYPTION CALL ***
      decryptedResult = _encrypter.decrypt(encryptedValue, iv: iv);
      // *** END DECRYPTION CALL ***

      print("[DECRYPT HELPER] Decryption method returned: $decryptedResult (Type: ${decryptedResult.runtimeType})");

      if (decryptedResult is String && decryptedResult.isNotEmpty) {
          print("[DECRYPT HELPER] Decryption SUCCESSFUL.");
          return decryptedResult; // Return the successful result
      } else {
          // This case should ideally not happen if decrypt worked, but let's log it.
          print("[DECRYPT HELPER] Decryption returned unexpected type or empty string.");
          return '[Decryption Failed: Empty Result]';
      }

    } catch (e, st) { // Catch specific Exception types
      print("[DECRYPT HELPER] Decryption FAILED (Caught Exception): $e");
      errorStackTrace = st;
    } on Error catch (e, st) { // Catch lower-level Error types
       print("[DECRYPT HELPER] Decryption FAILED (Caught Error): $e");
       errorStackTrace = st;
    } catch (e, st) { // Catch anything else
        print("[DECRYPT HELPER] Decryption FAILED (Caught Unknown): $e");
        errorStackTrace = st;
    }
    
    // If we reached here, an error occurred
    print("[DECRYPT HELPER] StackTrace: \n$errorStackTrace"); 
    return '[Decryption Error]'; // Return specific error placeholder
    */
  }
} 