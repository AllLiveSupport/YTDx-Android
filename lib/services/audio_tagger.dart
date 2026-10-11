import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:audiotags/audiotags.dart';
import 'app_logger.dart';

class AudioTagger {
  static const String _tag = 'AudioTagger';

  /// Downloads thumbnail and embeds metadata + cover art into the audio file (MP3 / M4A / MP4)
  /// Uses the `audiotags` package (Rust lofty crate) for reliable cross-platform tagging.
  /// If [localArtPath] is provided, uses that file directly without re-downloading.
  static Future<bool> tagAudioFile({
    required String filePath,
    required String title,
    required String artist,
    required String thumbnailUrl,
    String? localArtPath, // Optional: pre-downloaded thumbnail local path
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) return false;

    try {
      // Use pre-downloaded local art if available, otherwise download
      Uint8List? imageBytes;
      if (localArtPath != null && File(localArtPath).existsSync()) {
        imageBytes = await File(localArtPath).readAsBytes();
      } else if (thumbnailUrl.isNotEmpty) {
        try {
          final res = await http
              .get(Uri.parse(thumbnailUrl))
              .timeout(const Duration(seconds: 15));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            imageBytes = res.bodyBytes;
          }
        } catch (_) {}
      }

      // Build list of pictures
      final pictures = <Picture>[];
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final isPng = imageBytes.length > 8 &&
            imageBytes[0] == 0x89 &&
            imageBytes[1] == 0x50;
        pictures.add(Picture(
          bytes: imageBytes,
          mimeType: isPng ? MimeType.png : MimeType.jpeg,
          pictureType: PictureType.coverFront,
        ));
      }

      // Build tag
      final tag = Tag(
        title: title.isNotEmpty ? title : null,
        trackArtist: artist.isNotEmpty ? artist : null,
        album: 'YTDx Studio',
        pictures: pictures,
      );

      // Write tag via audiotags (Rust lofty)
      await AudioTags.write(filePath, tag);

      AppLogger.success(
          _tag, '🖼️ Albüm kapağı ve etiketler başarıyla gömüldü: $filePath');
      return true;
    } catch (e) {
      AppLogger.warn(_tag, 'audiotags etiketleme hatası: $e');
      // Fallback to manual M4A embedding if audiotags fails
      if (filePath.endsWith('.m4a') || filePath.endsWith('.mp4')) {
        return _fallbackEmbedM4a(
          filePath: filePath,
          title: title,
          artist: artist,
          thumbnailUrl: thumbnailUrl,
        );
      }
      return false;
    }
  }

  /// Fallback: Manual MP4/M4A embedding using pure Dart if audiotags fails.
  /// Uses proper QuickTime hdlr atom and stco/co64 chunk offset adjustment.
  static Future<bool> _fallbackEmbedM4a({
    required String filePath,
    required String title,
    required String artist,
    required String thumbnailUrl,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) return false;

    try {
      Uint8List? imageBytes;
      if (thumbnailUrl.isNotEmpty) {
        try {
          final res = await http
              .get(Uri.parse(thumbnailUrl))
              .timeout(const Duration(seconds: 15));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            imageBytes = res.bodyBytes;
          }
        } catch (_) {}
      }

      final lower = filePath.toLowerCase();
      final bytes = file.readAsBytesSync();
      bool isMp4Container = false;
      if (bytes.length >= 8) {
        final boxType = String.fromCharCodes(bytes.sublist(4, 8));
        if (boxType == 'ftyp' || boxType == 'moov' || boxType == 'mdat' || boxType == 'free') {
          isMp4Container = true;
        }
      }

      if (isMp4Container || lower.endsWith('.m4a') || lower.endsWith('.mp4')) {
        return _embedM4aManual(file, title: title, artist: artist, imageBytes: imageBytes);
      } else {
        return _embedMp3Id3v2(file, title: title, artist: artist, imageBytes: imageBytes);
      }
    } catch (e) {
      AppLogger.warn(_tag, 'Fallback etiket gömme hatası: $e');
    }
    return false;
  }

  /// ID3v2.3 tag embedding for MP3 files
  static bool _embedMp3Id3v2(
    File file, {
    required String title,
    required String artist,
    Uint8List? imageBytes,
  }) {
    try {
      final originalBytes = file.readAsBytesSync();
      int audioStartIndex = 0;

      if (originalBytes.length > 10 &&
          originalBytes[0] == 0x49 &&
          originalBytes[1] == 0x44 &&
          originalBytes[2] == 0x33) {
        final sizeBytes = originalBytes.sublist(6, 10);
        final existingSize = (sizeBytes[0] << 21) |
            (sizeBytes[1] << 14) |
            (sizeBytes[2] << 7) |
            sizeBytes[3];
        audioStartIndex = 10 + existingSize;
        if (audioStartIndex > originalBytes.length) audioStartIndex = 0;
      }

      final frames = <int>[];

      if (title.isNotEmpty) {
        final titleUtf8 = utf8.encode(title);
        final frameData = [0x03, ...titleUtf8];
        frames.addAll(utf8.encode('TIT2'));
        frames.addAll(_int32ToBytes(frameData.length));
        frames.addAll([0x00, 0x00]);
        frames.addAll(frameData);
      }

      if (artist.isNotEmpty) {
        final artistUtf8 = utf8.encode(artist);
        final frameData = [0x03, ...artistUtf8];
        frames.addAll(utf8.encode('TPE1'));
        frames.addAll(_int32ToBytes(frameData.length));
        frames.addAll([0x00, 0x00]);
        frames.addAll(frameData);
      }

      if (imageBytes != null && imageBytes.isNotEmpty) {
        final isPng = imageBytes.length > 8 &&
            imageBytes[0] == 0x89 &&
            imageBytes[1] == 0x50;
        final mimeBytes = utf8.encode(isPng ? 'image/png' : 'image/jpeg');
        final frameData = <int>[
          0x00,
          ...mimeBytes,
          0x00,
          0x03,
          0x00,
          ...imageBytes,
        ];

        frames.addAll(utf8.encode('APIC'));
        frames.addAll(_int32ToBytes(frameData.length));
        frames.addAll([0x00, 0x00]);
        frames.addAll(frameData);
      }

      final tagSize = frames.length;
      final header = <int>[
        0x49, 0x44, 0x33,
        0x03, 0x00,
        0x00,
        (tagSize >> 21) & 0x7F,
        (tagSize >> 14) & 0x7F,
        (tagSize >> 7) & 0x7F,
        tagSize & 0x7F,
      ];

      final outputBytes = Uint8List(
          header.length + frames.length + (originalBytes.length - audioStartIndex));
      int offset = 0;
      outputBytes.setRange(offset, offset + header.length, header);
      offset += header.length;
      outputBytes.setRange(offset, offset + frames.length, frames);
      offset += frames.length;
      outputBytes.setRange(
          offset, outputBytes.length, originalBytes.sublist(audioStartIndex));

      file.writeAsBytesSync(outputBytes);
      AppLogger.success(_tag, '🖼️ MP3 ID3v2 albüm kapağı gömüldü.');
      return true;
    } catch (e) {
      AppLogger.error(_tag, 'MP3 etiketleme hatası: $e');
      return false;
    }
  }

  /// Manual QuickTime/iTunes M4A metadata embedding with proper hdlr + stco offset fix
  static bool _embedM4aManual(
    File file, {
    required String title,
    required String artist,
    Uint8List? imageBytes,
  }) {
    try {
      final bytes = file.readAsBytesSync();
      int moovOffset = -1;
      int moovSize = 0;
      int mdatOffset = -1;

      int pos = 0;
      while (pos + 8 <= bytes.length) {
        if (pos < 0 || pos + 4 > bytes.length) break;
        final size = (bytes[pos] << 24) |
            (bytes[pos + 1] << 16) |
            (bytes[pos + 2] << 8) |
            bytes[pos + 3];
        if (size < 8 || pos + size > bytes.length) break;
        final type = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));

        if (type == 'moov') {
          moovOffset = pos;
          moovSize = size;
        } else if (type == 'mdat') {
          mdatOffset = pos;
        }
        pos += size;
      }

      if (moovOffset == -1) return false;

      final ilstItems = <int>[];

      if (title.isNotEmpty) {
        final valBytes = utf8.encode(title);
        final dataAtom = _buildMp4DataAtom(typeCode: 1, payload: valBytes);
        ilstItems.addAll(_buildMp4Atom('©nam', dataAtom));
      }

      if (artist.isNotEmpty) {
        final valBytes = utf8.encode(artist);
        final dataAtom = _buildMp4DataAtom(typeCode: 1, payload: valBytes);
        ilstItems.addAll(_buildMp4Atom('©ART', dataAtom));
      }

      if (imageBytes != null && imageBytes.isNotEmpty) {
        final isPng = imageBytes.length > 8 &&
            imageBytes[0] == 0x89 &&
            imageBytes[1] == 0x50;
        final dataAtom =
            _buildMp4DataAtom(typeCode: isPng ? 14 : 13, payload: imageBytes);
        ilstItems.addAll(_buildMp4Atom('covr', dataAtom));
      }

      final ilstAtom = _buildMp4Atom('ilst', ilstItems);

      // hdlr atom required by QuickTime/iTunes for Android to parse meta
      final hdlrPayload = [
        0, 0, 0, 0, // version/flags
        0, 0, 0, 0, // pre-defined
        ...'mdir'.codeUnits, // handler subtype
        ...'appl'.codeUnits, // manufacturer
        0, 0, 0, 0, // component flags
        0, 0, 0, 0, // component flags mask
        0, // name (empty string null terminator)
      ];
      final hdlrAtom = _buildMp4Atom('hdlr', hdlrPayload);

      // meta atom: FullBox header (4 bytes version+flags = 0)
      final metaAtom =
          _buildMp4Atom('meta', [0, 0, 0, 0, ...hdlrAtom, ...ilstAtom]);
      final udtaAtom = _buildMp4Atom('udta', metaAtom);

      // Strip any existing udta from moov
      final rawMoovData = bytes.sublist(moovOffset + 8, moovOffset + moovSize);
      final cleanMoovData = <int>[];
      int mPos = 0;
      while (mPos + 8 <= rawMoovData.length) {
        final atomSize = (rawMoovData[mPos] << 24) |
            (rawMoovData[mPos + 1] << 16) |
            (rawMoovData[mPos + 2] << 8) |
            rawMoovData[mPos + 3];
        if (atomSize < 8 || mPos + atomSize > rawMoovData.length) break;
        final atomType =
            String.fromCharCodes(rawMoovData.sublist(mPos + 4, mPos + 8));
        if (atomType != 'udta') {
          cleanMoovData.addAll(rawMoovData.sublist(mPos, mPos + atomSize));
        }
        mPos += atomSize;
      }

      // Build new moov payload and calculate delta
      final newMoovPayloadList = [...cleanMoovData, ...udtaAtom];
      final newMoovSize = newMoovPayloadList.length + 8;
      final deltaBytes = newMoovSize - moovSize;

      // Convert to mutable Uint8List before shifting offsets
      final moovPayload = Uint8List.fromList(newMoovPayloadList);

      // Shift stco/co64 offsets if moov is before mdat
      if (mdatOffset != -1 && moovOffset < mdatOffset && deltaBytes != 0) {
        _shiftChunkOffsets(moovPayload, deltaBytes);
      }

      final newMoovAtom = _buildMp4Atom('moov', moovPayload);

      final result = Uint8List.fromList([
        ...bytes.sublist(0, moovOffset),
        ...newMoovAtom,
        ...bytes.sublist(moovOffset + moovSize),
      ]);

      file.writeAsBytesSync(result);
      AppLogger.success(_tag, '🖼️ M4A/MP4 covr albüm kapağı gömüldü (manuel).');
      return true;
    } catch (e) {
      AppLogger.error(_tag, 'M4A manuel etiketleme hatası: $e');
      return false;
    }
  }

  /// Scans moovPayload for stco (32-bit) and co64 (64-bit) atoms and adjusts offsets by delta.
  /// Properly scans atom boundaries, not byte-by-byte.
  static void _shiftChunkOffsets(Uint8List moovPayload, int delta) {
    if (delta == 0) return;
    _scanAndShiftAtoms(moovPayload, 0, moovPayload.length, delta);
  }

  static void _scanAndShiftAtoms(
      Uint8List data, int start, int end, int delta) {
    int pos = start;
    while (pos + 8 <= end) {
      final atomSize = (data[pos] << 24) |
          (data[pos + 1] << 16) |
          (data[pos + 2] << 8) |
          data[pos + 3];
      if (atomSize < 8 || pos + atomSize > end) break;

      final type = String.fromCharCodes(data.sublist(pos + 4, pos + 8));

      if (type == 'stco') {
        // 4 bytes version/flags, 4 bytes entry count, then 4-byte offsets
        final entryCount = (data[pos + 8] << 24) |
            (data[pos + 9] << 16) |
            (data[pos + 10] << 8) |
            data[pos + 11];
        int entryPos = pos + 12;
        for (int i = 0;
            i < entryCount && entryPos + 4 <= pos + atomSize;
            i++) {
          final oldOffset = (data[entryPos] << 24) |
              (data[entryPos + 1] << 16) |
              (data[entryPos + 2] << 8) |
              data[entryPos + 3];
          final newOffset = oldOffset + delta;
          data[entryPos] = (newOffset >> 24) & 0xFF;
          data[entryPos + 1] = (newOffset >> 16) & 0xFF;
          data[entryPos + 2] = (newOffset >> 8) & 0xFF;
          data[entryPos + 3] = newOffset & 0xFF;
          entryPos += 4;
        }
      } else if (type == 'co64') {
        final entryCount = (data[pos + 8] << 24) |
            (data[pos + 9] << 16) |
            (data[pos + 10] << 8) |
            data[pos + 11];
        int entryPos = pos + 12;
        for (int i = 0;
            i < entryCount && entryPos + 8 <= pos + atomSize;
            i++) {
          final oldOffsetHigh = (data[entryPos] << 24) |
              (data[entryPos + 1] << 16) |
              (data[entryPos + 2] << 8) |
              data[entryPos + 3];
          final oldOffsetLow = (data[entryPos + 4] << 24) |
              (data[entryPos + 5] << 16) |
              (data[entryPos + 6] << 8) |
              data[entryPos + 7];
          final oldOffset = (oldOffsetHigh * 4294967296) + oldOffsetLow;
          final newOffset = oldOffset + delta;
          final newHigh = (newOffset ~/ 4294967296);
          final newLow = (newOffset % 4294967296).toInt();
          data[entryPos] = (newHigh >> 24) & 0xFF;
          data[entryPos + 1] = (newHigh >> 16) & 0xFF;
          data[entryPos + 2] = (newHigh >> 8) & 0xFF;
          data[entryPos + 3] = newHigh & 0xFF;
          data[entryPos + 4] = (newLow >> 24) & 0xFF;
          data[entryPos + 5] = (newLow >> 16) & 0xFF;
          data[entryPos + 6] = (newLow >> 8) & 0xFF;
          data[entryPos + 7] = newLow & 0xFF;
          entryPos += 8;
        }
      } else if (type == 'moov' ||
          type == 'trak' ||
          type == 'mdia' ||
          type == 'minf' ||
          type == 'stbl') {
        // Recurse into container atoms
        _scanAndShiftAtoms(data, pos + 8, pos + atomSize, delta);
      }

      pos += atomSize;
    }
  }

  static List<int> _buildMp4DataAtom(
      {required int typeCode, required List<int> payload}) {
    final dataHeader = [0, 0, 0, typeCode, 0, 0, 0, 0];
    return _buildMp4Atom('data', [...dataHeader, ...payload]);
  }

  static List<int> _buildMp4Atom(String fourCC, List<int> payload) {
    final size = payload.length + 8;
    return [
      (size >> 24) & 0xFF,
      (size >> 16) & 0xFF,
      (size >> 8) & 0xFF,
      size & 0xFF,
      ...fourCC.codeUnits.take(4),
      ...payload,
    ];
  }

  static List<int> _int32ToBytes(int val) {
    return [
      (val >> 24) & 0xFF,
      (val >> 16) & 0xFF,
      (val >> 8) & 0xFF,
      val & 0xFF,
    ];
  }
}
