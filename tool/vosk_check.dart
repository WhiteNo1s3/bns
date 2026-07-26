// Proves the Vosk chain end to end without the GUI:
//   dart run tool/vosk_check.dart <voskDir> install     — fetch engine+model
//   dart run tool/vosk_check.dart <voskDir> <file.wav>  — transcribe a WAV
// ignore_for_file: avoid_print
import 'package:bns/services/vosk_service.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    print('usage: vosk_check <voskDir> install|<wavPath>');
    return;
  }
  final dir = args[0];
  if (args[1] == 'install') {
    await VoskService.install(dir, onStatus: print);
    print('installed=${VoskService.isInstalled(dir)}');
    return;
  }
  final sw = Stopwatch()..start();
  final text = await VoskService.transcribeWav(dir, args[1]);
  print('TRANSCRIPT (${sw.elapsedMilliseconds}ms): "$text"');
}
