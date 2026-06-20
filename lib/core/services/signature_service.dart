import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dating_app/core/services/secure_storage_service.dart';
import 'package:flutter/foundation.dart';

/// End-to-end digital signatures for rental contracts.
///
/// Each user owns an **Ed25519 key pair**. The private key never leaves the
/// device (stored in the OS keychain via [SecureStorageService]); only the
/// public key is shared with the backend alongside a signature. To sign a
/// contract we hash its canonical content (SHA-256) and sign that hash with the
/// private key. Anyone holding the contract + the signer's public key can
/// verify the signature — and because the signature is bound to the content
/// hash, any later edit to the contract terms invalidates it (tamper-evident).
class SignatureService {
  SignatureService({SecureStorageService? storage})
      : _storage = storage ?? SecureStorageService();

  final SecureStorageService _storage;
  final Ed25519 _algorithm = Ed25519();

  static const _privateKeyStorageKey = 'contract_signing_ed25519_seed_v1';

  /// Returns the device's signing key pair, generating + persisting one on first
  /// use. The 32-byte Ed25519 seed is what we store (compact + sufficient to
  /// reconstruct the key pair).
  Future<SimpleKeyPair> _keyPair() async {
    final existing = await _storage.readString(_privateKeyStorageKey);
    if (existing != null && existing.isNotEmpty) {
      try {
        final seed = base64Decode(existing);
        if (seed.length == 32) {
          return _algorithm.newKeyPairFromSeed(seed);
        }
      } catch (_) {/* fall through to regenerate */}
    }
    final keyPair = await _algorithm.newKeyPair();
    final seed = await keyPair.extractPrivateKeyBytes();
    await _storage.writeString(_privateKeyStorageKey, base64Encode(seed));
    return keyPair;
  }

  /// The device's public key (base64), shared with the backend so the other
  /// party can verify this user's signatures.
  Future<String> publicKeyBase64() async {
    final kp = await _keyPair();
    final pub = await kp.extractPublicKey();
    return base64Encode(pub.bytes);
  }

  /// SHA-256 (base64) of a contract's canonical content. Deterministic so both
  /// devices and the backend compute the same hash from the same terms.
  static String contentHash(String canonicalContent) {
    final digest = crypto.sha256.convert(utf8.encode(canonicalContent));
    return base64Encode(digest.bytes);
  }

  /// Signs [contentHashBase64] with the device's private key, returning the
  /// signature as base64.
  Future<String> sign(String contentHashBase64) async {
    final kp = await _keyPair();
    final message = base64Decode(contentHashBase64);
    final signature = await _algorithm.sign(message, keyPair: kp);
    return base64Encode(signature.bytes);
  }

  /// Verifies [signatureBase64] over [contentHashBase64] using [publicKeyBase64].
  /// Returns false (never throws) on any malformed input.
  Future<bool> verify({
    required String contentHashBase64,
    required String signatureBase64,
    required String publicKeyBase64,
  }) async {
    try {
      final message = base64Decode(contentHashBase64);
      final signatureBytes = base64Decode(signatureBase64);
      final publicKey = SimplePublicKey(
        base64Decode(publicKeyBase64),
        type: KeyPairType.ed25519,
      );
      return _algorithm.verify(
        message,
        signature: Signature(signatureBytes, publicKey: publicKey),
      );
    } catch (error) {
      if (kDebugMode) debugPrint('SignatureService.verify failed: $error');
      return false;
    }
  }
}
