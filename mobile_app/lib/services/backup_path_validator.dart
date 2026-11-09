/// Validates a document entry from a decrypted backup archive.
/// Returns a safe path relative to the case_documents directory.
String safeCaseDocumentRelativePath(String archiveName) {
  final portable = archiveName.replaceAll(String.fromCharCode(92), '/');
  if (portable.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(portable) ||
      !portable.startsWith('case_documents/')) {
    throw const FormatException('Backup में असुरक्षित file path मिला।');
  }
  final segments = portable.split('/');
  if (segments.length < 2 || segments.first != 'case_documents') {
    throw const FormatException('Backup में असुरक्षित file path मिला।');
  }
  final relativeSegments = segments.skip(1).toList();
  if (relativeSegments.any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw const FormatException('Backup में असुरक्षित file path मिला।');
  }
  return relativeSegments.join('/');
}
