import 'package:file_picker/file_picker.dart';

class NativeFolderPicker {
  /// Opens a native directory picker dialog on Android and returns the selected path
  static Future<String?> pickDirectory({String? initialPath, String? title}) async {
    try {
      final selected = await FilePicker.getDirectoryPath(
        dialogTitle: title ?? 'İndirme Klasörünü Seçin',
        initialDirectory: initialPath,
      );
      if (selected != null && selected.isNotEmpty) {
        return selected;
      }
    } catch (_) {}
    return null;
  }
}
