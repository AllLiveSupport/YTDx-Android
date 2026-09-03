import 'dart:io';
import 'package:open_filex/open_filex.dart';

class FileLauncher {
  /// Opens a media file in the system's default media player (VLC, MX Player, Gallery, etc.)
  static Future<bool> openFile(String filePath) async {
    if (!File(filePath).existsSync()) return false;
    try {
      final result = await OpenFilex.open(filePath);
      return result.type == ResultType.done;
    } catch (_) {}
    return false;
  }

  /// Opens the folder containing the file in Android file manager
  static Future<bool> openFolder(String folderOrFilePath) async {
    String folderPath = folderOrFilePath;
    if (File(folderOrFilePath).existsSync()) {
      folderPath = File(folderOrFilePath).parent.path;
    }
    if (!Directory(folderPath).existsSync()) return false;
    try {
      final result = await OpenFilex.open(folderPath);
      return result.type == ResultType.done;
    } catch (_) {}
    return false;
  }
}
