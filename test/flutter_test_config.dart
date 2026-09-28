import 'dart:async';

import 'package:chess_pgn_reader/services/sound_service.dart';

/// Bütün testlerden önce çalışır (Flutter'ın test yapılandırması).
///
/// Linux'ta sesleri sistemin komutu çalıyor ([SoundService.useSystemPlayer]);
/// testlerde bu gerçek süreç başlatır ve sahte saatli testlerde bekleyen
/// zamanlayıcı bırakırdı. Ses denemeleri bunu kendileri açıyor
/// (bkz. v1050_linux_test.dart).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SoundService.useSystemPlayer = false;
  await testMain();
}
