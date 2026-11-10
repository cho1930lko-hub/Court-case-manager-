import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Keeps Dak attachments in app-private storage. A picked file is staged first;
/// callers commit it only after the Dak record has been saved successfully.
class DakAttachmentService {
  DakAttachmentService._();

  static final DakAttachmentService instance = DakAttachmentService._();

  static const int maxBytes = 20 * 1024 * 1024;
  static const Set<String> allowedExtensions = {
    'pdf', 'jpg', 'jpeg', 'png', 'webp', 'doc', 'docx', 'xls', 'xlsx',
  };

  Future<Directory> _root() async {
    final app = await getApplicationDocumentsDirectory();
    return Directory(p.join(app.path, 'dak_attachments'));
  }

  Future<String?> pickAndStage() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions.toList(),
      withData: false,
    );
    if (picked == null || picked.files.isEmpty) return null;

    final item = picked.files.single;
    final sourcePath = item.path;
    if (sourcePath == null || sourcePath.isEmpty) {
      throw StateError('चुनी गई फाइल का स्थानीय पथ उपलब्ध नहीं है।');
    }
    if (item.size <= 0 || item.size > maxBytes) {
      throw StateError('फाइल खाली है या 20 MB की अधिकतम सीमा से बड़ी है।');
    }

    final extension = p.extension(item.name).replaceFirst('.', '').toLowerCase();
    if (!allowedExtensions.contains(extension)) {
      throw StateError('यह फाइल प्रकार समर्थित नहीं है।');
    }

    final root = await _root();
    final pending = Directory(p.join(root.path, '.pending'));
    await pending.create(recursive: true);
    final stagedPath = p.join(
      pending.path,
      '${const Uuid().v4()}_${_safeName(item.name)}',
    );
    final copied = await File(sourcePath).copy(stagedPath);
    final copiedLength = await copied.length();
    if (copiedLength != item.size || copiedLength > maxBytes) {
      await copied.delete();
      throw StateError('फाइल कॉपी की जाँच विफल रही; अटैचमेंट सेव नहीं हुआ।');
    }
    return stagedPath;
  }

  Future<String> commit(String stagedPath, String recordId) async {
    final staged = File(stagedPath);
    if (!await staged.exists() || !isStagedPath(stagedPath)) {
      throw StateError('अस्थायी अटैचमेंट उपलब्ध नहीं है।');
    }
    final root = await _root();
    final destinationDir = Directory(p.join(root.path, _safeName(recordId)));
    await destinationDir.create(recursive: true);
    final destination = p.join(
      destinationDir.path,
      '${const Uuid().v4()}_${p.basename(stagedPath).split('_').skip(1).join('_')}',
    );
    final committed = await staged.rename(destination);
    if (await committed.length() == 0) {
      await committed.delete();
      throw StateError('अटैचमेंट खाली मिला; सेव नहीं किया गया।');
    }
    return destination;
  }

  bool isStagedPath(String path) =>
      p.split(p.normalize(path)).contains('.pending');

  Future<void> discard(String? path) async {
    if (path == null || path.isEmpty || !isStagedPath(path)) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<bool> exists(String? path) async {
    if (path == null || path.trim().isEmpty) return false;
    return File(path).exists();
  }

  String _safeName(String value) {
    final cleaned = p.basename(value).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'attachment' : cleaned;
  }
}
