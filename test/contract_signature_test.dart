import 'package:dating_app/core/services/secure_storage_service.dart';
import 'package:dating_app/core/services/signature_service.dart';
import 'package:dating_app/data/models/rental_contract.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for the keychain so the signing key persists within a test
/// without touching platform channels.
class _MemStorage extends SecureStorageService {
  final Map<String, String> _m = {};
  @override
  Future<void> writeString(String key, String value) async => _m[key] = value;
  @override
  Future<String?> readString(String key) async => _m[key];
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

RentalContract _contract({int rent = 6000, String terms = 'תשלום עד ה-10'}) {
  return RentalContract(
    id: 'c1',
    matchId: 'm1',
    propertyId: 'p1',
    propertyTitle: 'דירה ברחוב הרצל',
    landlordUserId: 'L1',
    landlordName: 'לימור',
    tenantUserId: 'T1',
    tenantName: 'דנה',
    monthlyRent: rent,
    deposit: 12000,
    durationMonths: 12,
    startDate: DateTime.utc(2026, 7, 1),
    additionalTerms: terms,
    status: ContractStatus.sent,
  );
}

void main() {
  test('content hash is deterministic and term-sensitive', () {
    expect(_contract().contentHash, equals(_contract().contentHash));
    expect(_contract(rent: 6000).contentHash,
        isNot(equals(_contract(rent: 6500).contentHash)));
    expect(_contract(terms: 'a').contentHash,
        isNot(equals(_contract(terms: 'b').contentHash)));
  });

  test('signature verifies for the original contract terms', () async {
    final service = SignatureService(storage: _MemStorage());
    final contract = _contract();
    final publicKey = await service.publicKeyBase64();
    final signature = await service.sign(contract.contentHash);

    final ok = await service.verify(
      contentHashBase64: contract.contentHash,
      signatureBase64: signature,
      publicKeyBase64: publicKey,
    );
    expect(ok, isTrue);
  });

  test('signature is tamper-evident: editing a term invalidates it', () async {
    final service = SignatureService(storage: _MemStorage());
    final original = _contract(rent: 6000);
    final publicKey = await service.publicKeyBase64();
    final signature = await service.sign(original.contentHash);

    // The landlord secretly raises the rent after the tenant signed.
    final tampered = _contract(rent: 9000);
    final ok = await service.verify(
      contentHashBase64: tampered.contentHash, // recomputed from new terms
      signatureBase64: signature, // signature over the OLD terms
      publicKeyBase64: publicKey,
    );
    expect(ok, isFalse);
  });

  test('a different key cannot forge a verifiable signature', () async {
    final signer = SignatureService(storage: _MemStorage());
    final attacker = SignatureService(storage: _MemStorage());
    final contract = _contract();

    final attackerSig = await attacker.sign(contract.contentHash);
    final signerPublicKey = await signer.publicKeyBase64();

    final ok = await signer.verify(
      contentHashBase64: contract.contentHash,
      signatureBase64: attackerSig, // signed by the attacker's key
      publicKeyBase64: signerPublicKey, // but checked against the signer's key
    );
    expect(ok, isFalse);
  });

  test('the device key pair is stable across calls (persisted)', () async {
    final service = SignatureService(storage: _MemStorage());
    final a = await service.publicKeyBase64();
    final b = await service.publicKeyBase64();
    expect(a, equals(b));
  });
}
