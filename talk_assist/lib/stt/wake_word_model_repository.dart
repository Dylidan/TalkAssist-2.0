import "dart:io";

import "package:archive/archive_io.dart";
import "package:path_provider/path_provider.dart";

import "wake_word_config.dart";

class WakeWordModelRecord {
  const WakeWordModelRecord({
    required this.encoderPath,
    required this.decoderPath,
    required this.joinerPath,
    required this.tokensPath,
    required this.lexiconPath,
    required this.keywordsPath,
    required this.modelDirPath,
  });

  final String encoderPath;
  final String decoderPath;
  final String joinerPath;
  final String tokensPath;
  final String lexiconPath;
  final String keywordsPath;
  final String modelDirPath;
}

class WakeWordModelRepository {
  Future<WakeWordModelRecord> ensureModelAvailable() async {
    final modelDir = await _modelDirectory();
    final record = await _buildRecord(modelDir);
    if (await _hasValidModelFiles(record)) {
      final keywordsFile = File(record.keywordsPath);
      if (!await keywordsFile.exists() || await keywordsFile.length() == 0) {
        await _writeKeywordsFile(record);
      }
      return record;
    }

    final archiveFile = File("${modelDir.parent.path}/${WakeWordConfig.archiveFileName}");
    final client = HttpClient();

    try {
      await modelDir.parent.create(recursive: true);
      if (await archiveFile.exists()) {
        await archiveFile.delete();
      }
      if (await modelDir.exists()) {
        await modelDir.delete(recursive: true);
      }
      await modelDir.create(recursive: true);

      final request = await client.getUrl(Uri.parse(WakeWordConfig.archiveUrl));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          "Wake word model download failed with HTTP ${response.statusCode}.",
          uri: Uri.parse(WakeWordConfig.archiveUrl),
        );
      }

      final sink = archiveFile.openWrite();
      await response.pipe(sink);
      await sink.flush();
      await sink.close();

      await _extractTarBz2(archiveFile, modelDir);
      final extractedRecord = await _buildRecord(modelDir);
      await _validateRecord(extractedRecord);
      await _writeKeywordsFile(extractedRecord);
      return extractedRecord;
    } finally {
      client.close(force: true);
      if (await archiveFile.exists()) {
        await archiveFile.delete();
      }
    }
  }

  Future<Directory> _modelDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory(
      "${appDir.path}/${WakeWordConfig.modelDirName}/${WakeWordConfig.modelSubDirName}",
    );
  }

  Future<WakeWordModelRecord> _buildRecord(Directory modelDir) async {
    return WakeWordModelRecord(
      encoderPath: "${modelDir.path}/${WakeWordConfig.encoderFileName}",
      decoderPath: "${modelDir.path}/${WakeWordConfig.decoderFileName}",
      joinerPath: "${modelDir.path}/${WakeWordConfig.joinerFileName}",
      tokensPath: "${modelDir.path}/${WakeWordConfig.tokensFileName}",
      lexiconPath: "${modelDir.path}/${WakeWordConfig.englishLexiconFileName}",
      keywordsPath: "${modelDir.path}/${WakeWordConfig.keywordsFileName}",
      modelDirPath: modelDir.path,
    );
  }

  Future<bool> _hasValidModelFiles(WakeWordModelRecord record) async {
    try {
      await _validateRecord(record);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _validateRecord(WakeWordModelRecord record) async {
    await _validateFile(record.encoderPath, WakeWordConfig.minimumEncoderSizeBytes);
    await _validateFile(record.decoderPath, WakeWordConfig.minimumDecoderSizeBytes);
    await _validateFile(record.joinerPath, WakeWordConfig.minimumJoinerSizeBytes);
    await _validateFile(record.tokensPath, WakeWordConfig.minimumTokensSizeBytes);
    await _validateFile(record.lexiconPath, WakeWordConfig.minimumLexiconSizeBytes);
  }

  Future<void> _validateFile(String path, int minimumBytes) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException("Missing wake word model file", path);
    }
    final length = await file.length();
    if (length < minimumBytes) {
      throw FileSystemException("Wake word model file is too small", path);
    }
  }

  Future<void> _writeKeywordsFile(WakeWordModelRecord record) async {
    final lexicon = await _loadLexicon(record.lexiconPath);
    final words = WakeWordConfig.wakePhrase.split(' ');
    final phones = <String>[];

    for (final word in words) {
      final normalized = word.trim().toUpperCase();
      final tokens = lexicon[normalized];
      if (tokens == null || tokens.isEmpty) {
        throw Exception("Wake word lexicon is missing pronunciation for $normalized");
      }
      phones.addAll(tokens);
    }

    final output = "${phones.join(' ')} @${WakeWordConfig.wakeKeywordLabel}\n";
    await File(record.keywordsPath).writeAsString(output, flush: true);
  }

  Future<Map<String, List<String>>> _loadLexicon(String path) async {
    final lines = await File(path).readAsLines();
    final lexicon = <String, List<String>>{};

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }

      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 2) {
        continue;
      }

      final word = parts.first.toUpperCase();
      final phones = parts.sublist(1);
      lexicon.putIfAbsent(word, () => phones);
    }

    return lexicon;
  }

  Future<void> _extractTarBz2(File archive, Directory destination) async {
    final bz2Bytes = await archive.readAsBytes();
    final tarBytes = BZip2Decoder().decodeBytes(bz2Bytes);
    final archiveObj = TarDecoder().decodeBytes(tarBytes);

    for (final file in archiveObj.files) {
      if (!file.isFile) {
        continue;
      }

      var relativePath = file.name;
      final parts = relativePath.split('/');
      if (parts.length > 1) {
        relativePath = parts.sublist(1).join('/');
      }

      final outputFile = File("${destination.path}/$relativePath");
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(file.content as List<int>);
    }
  }
}
