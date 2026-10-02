import 'package:file_picker/file_picker.dart';

import 'study_document_upload_source.dart';

typedef StudyDocumentFilePicker = Future<FilePickerResult?> Function();

class PickedStudyDocument {
  const PickedStudyDocument({
    required this.displayName,
    required this.source,
  });

  final String displayName;
  final StudyDocumentUploadSource source;

  Future<void> dispose() => source.dispose();
}

Future<FilePickerResult?> _pickPdfFile() => FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: false,
      withData: false,
      withReadStream: true,
    );

Future<PickedStudyDocument?> pickStudyDocumentPdf({
  StudyDocumentFilePicker? picker,
}) async {
  final result = await (picker ?? _pickPdfFile)();
  if (result == null || result.files.isEmpty) return null;

  final file = result.files.single;
  final source = await prepareStudyDocumentUpload(
    fileName: file.name,
    declaredSize: file.size,
    path: file.path,
    bytes: file.bytes,
    readStream: file.readStream,
  );

  return PickedStudyDocument(
    displayName: file.name,
    source: source,
  );
}
