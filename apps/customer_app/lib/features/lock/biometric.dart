import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../app/providers.dart';

/// What this phone can use to unlock the app.
enum BioKind { none, fingerprint, face }

/// Fingerprint / Face ID unlock. The check happens entirely on the phone:
/// Mukafaah never receives a fingerprint or a face, only "it was you".
class Biometrics {
  Biometrics(this._ref);
  final Ref _ref;
  final _auth = LocalAuthentication();

  static const _enabledKey = 'bio.enabled';
  static const _askedKey = 'bio.asked';

  bool get enabled => _ref.read(prefsProvider).getBool(_enabledKey) ?? false;

  /// True once the member has seen the "use fingerprint / Face ID" offer.
  bool get asked => _ref.read(prefsProvider).getBool(_askedKey) ?? false;

  Future<void> markAsked() => _ref.read(prefsProvider).setBool(_askedKey, true);

  Future<void> setEnabled(bool on) async {
    await _ref.read(prefsProvider).setBool(_enabledKey, on);
    await markAsked();
    _ref.invalidate(bioEnabledProvider);
  }

  Future<BioKind> kind() async {
    try {
      if (!await _auth.isDeviceSupported() || !await _auth.canCheckBiometrics) return BioKind.none;
      final types = await _auth.getAvailableBiometrics();
      if (types.isEmpty) return BioKind.none;
      if (types.contains(BiometricType.face)) return BioKind.face;
      return BioKind.fingerprint;
    } on PlatformException {
      return BioKind.none;
    }
  }

  /// Shows the phone's own fingerprint / Face ID prompt. True if it was the owner.
  Future<bool> check(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } on PlatformException {
      return false;
    }
  }
}

final biometricsProvider = Provider<Biometrics>(Biometrics.new);
final bioKindProvider = FutureProvider<BioKind>((ref) => ref.watch(biometricsProvider).kind());
final bioEnabledProvider = Provider<bool>((ref) => ref.watch(biometricsProvider).enabled);
