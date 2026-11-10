/// Validates a managed file entry from a decrypted backup archive.
/// Returns a safe relative path including its managed root folder.
String safeManagedFileRelativePath(String archiveName) {
  final portable = archiveName.replaceAll(String.fromCharCode(92), '/');
  if (portable.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(portable)) {
    throw const FormatException('Backup में असुरक्षित file path मिला।');
  }
  final segments = portable.split('/');
  const roots = {'case_documents', 'evidence', 'dak_attachments'};
  if (segments.length < 3 || !roots.contains(segments.first) ||
      segments.any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw const FormatException('Backup में असुरक्षित file path मिला।');
  }
  return segments.join('/');
}

/// Backward-compatible validator for document-only callers and old tests.
String safeCaseDocumentRelativePath(String archiveName) {
  final safe = safeManagedFileRelativePath(archiveName);
  if (!safe.startsWith('case_documents/')) {
    throw const FormatException('Backup में असुरक्षित document path मिला।');
  }
  return safe.substring('case_documents/'.length);
}
