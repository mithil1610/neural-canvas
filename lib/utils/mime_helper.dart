/// Maps a file name or path to the MIME type sent with Firebase Storage uploads.
///
/// Storage rules only accept known content types, so every upload sets one
/// explicitly instead of relying on the platform to infer it.
class MimeHelper {
  static const Map<String, String> _byExtension = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'md': 'text/markdown',
    'rtf': 'text/rtf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'm4a': 'audio/mp4',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'aac': 'audio/aac',
  };

  /// Returns the MIME type for [pathOrName], or `application/octet-stream`
  /// when the extension is unknown (Storage rules will then reject the upload).
  static String fromPath(String pathOrName) {
    final name = pathOrName.split('?').first.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'application/octet-stream';
    final ext = name.substring(dot + 1).toLowerCase();
    return _byExtension[ext] ?? 'application/octet-stream';
  }
}
