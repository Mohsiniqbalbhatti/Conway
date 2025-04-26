const crypto = require('crypto');

const ALGORITHM = 'aes-256-cbc';
// Ensure the key is 32 bytes (64 hex characters)
const ENCRYPTION_KEY = Buffer.from(process.env.ENCRYPTION_KEY || Buffer.alloc(32).toString('hex'), 'hex'); 
const IV_LENGTH = 16; // For AES, this is always 16

if (ENCRYPTION_KEY.length !== 32) {
  throw new Error('Invalid ENCRYPTION_KEY length. Must be 32 bytes (64 hex characters).');
}

function encrypt(text) {
  // DISABLED: Simply return plain text
  console.log("[Crypto DISABLED] encrypt called, returning plain text:", text);
  return text;
  /* // Original encryption logic commented out
  try {
    const iv = crypto.randomBytes(IV_LENGTH);
    const cipher = crypto.createCipheriv(ALGORITHM, ENCRYPTION_KEY, iv);
    let encrypted = cipher.update(text, 'utf8', 'base64');
    encrypted += cipher.final('base64');
    return iv.toString('hex') + ':' + encrypted;
  } catch (error) {
    console.error('Encryption failed:', error);
    return text; 
  }
  */
}

function decrypt(text) {
  // DISABLED: Simply return input text
  console.log("[Crypto DISABLED] decrypt called, returning input text:", text);
  return text;
  /* // Original decryption logic commented out
  try {
    const textParts = text.split(':');
    if (textParts.length !== 2) {
      console.error('Decryption failed: Invalid format (expected iv:ciphertext)');
      return text; 
    }
    const iv = Buffer.from(textParts[0], 'hex');
    const encryptedText = textParts[1];

    if (iv.length !== IV_LENGTH) {
        console.error(`Decryption failed: Invalid IV length (${iv.length}, expected ${IV_LENGTH})`);
        return text;
    }

    const decipher = crypto.createDecipheriv(ALGORITHM, ENCRYPTION_KEY, iv);
    let decrypted = decipher.update(encryptedText, 'base64', 'utf8');
    decrypted += decipher.final('utf8');
    return decrypted;
  } catch (error) {
     console.error('Decryption failed:', error);
    if (!text.includes(':')) { 
        return text;
    }
    return '[Decryption Error]';
  }
  */
}

module.exports = { encrypt, decrypt }; 