import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// One JSON document kept on this device. Health data goes here only after
/// the account holder agreed to it (see `health_consent.dart`).
abstract class LocalVault {
  /// Null when nothing is stored, or when what is stored can no longer be
  /// opened (for example a backup restored without its key); the unreadable
  /// copy is deleted.
  Future<Map<String, Object?>?> read();
  Future<void> write(Map<String, Object?> data);
  Future<void> wipe();
}

/// Keeps the document in memory only. Used in tests, and as the default so
/// nothing reaches the disk unless `main` installs [EncryptedFileVault].
class MemoryVault implements LocalVault {
  MemoryVault([this._data]);
  Map<String, Object?>? _data;

  @override
  Future<Map<String, Object?>?> read() async => _data;

  @override
  Future<void> write(Map<String, Object?> data) async =>
      _data = jsonDecode(jsonEncode(data)) as Map<String, Object?>;

  @override
  Future<void> wipe() async => _data = null;
}

/// AES-256-GCM encrypted file in the app's private support folder. The key is
/// generated on first use and kept in Android Keystore-backed secure storage,
/// so a copy of the file alone cannot be read.
class EncryptedFileVault implements LocalVault {
  EncryptedFileVault({
    FlutterSecureStorage? keyStore,
    Future<File> Function()? file,
  }) : _keyStore = keyStore ?? const FlutterSecureStorage(),
       _file = file ?? _defaultFile;

  static const _keyName = 'medicapp.vault.key.v1';
  static final _cipher = AesGcm.with256bits();

  final FlutterSecureStorage _keyStore;
  final Future<File> Function() _file;

  static Future<File> _defaultFile() async =>
      File('${(await getApplicationSupportDirectory()).path}/vault.bin');

  Future<SecretKey?> _key({required bool create}) async {
    final stored = await _keyStore.read(key: _keyName);
    if (stored != null) return SecretKey(base64Decode(stored));
    if (!create) return null;
    final key = await _cipher.newSecretKey();
    await _keyStore.write(
      key: _keyName,
      value: base64Encode(await key.extractBytes()),
    );
    return key;
  }

  @override
  Future<Map<String, Object?>?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      final key = await _key(create: false);
      if (key == null) throw const FormatException('Missing vault key');
      final box = SecretBox.fromConcatenation(
        await file.readAsBytes(),
        nonceLength: _cipher.nonceLength,
        macLength: _cipher.macAlgorithm.macLength,
      );
      final clear = await _cipher.decrypt(box, secretKey: key);
      return jsonDecode(utf8.decode(clear)) as Map<String, Object?>;
    } on Object {
      await wipe();
      return null;
    }
  }

  @override
  Future<void> write(Map<String, Object?> data) async {
    final key = await _key(create: true);
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: key!,
    );
    final file = await _file();
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(box.concatenation(), flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<void> wipe() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
    await _keyStore.delete(key: _keyName);
  }
}

final localVaultProvider = Provider<LocalVault>((ref) => MemoryVault());

/// What [localVaultProvider] held when the app started; `main` overrides it.
final vaultSnapshotProvider = Provider<Map<String, Object?>?>((ref) => null);
