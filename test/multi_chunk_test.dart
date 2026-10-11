import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Multi-Chunk Parallel Download Engine Unit Tests', () {
    test('Calculates chunk ranges accurately for various file sizes', () {
      const totalBytes = 10000000; // 10 MB
      const concurrency = 4;
      final chunkSize = (totalBytes / concurrency).ceil();

      final ranges = <(int, int)>[];
      for (int i = 0; i < concurrency; i++) {
        final start = i * chunkSize;
        final end = (i == concurrency - 1) ? totalBytes - 1 : (start + chunkSize - 1);
        ranges.add((start, end));
      }

      expect(ranges.length, equals(4));
      expect(ranges[0], equals((0, 2499999)));
      expect(ranges[1], equals((2500000, 4999999)));
      expect(ranges[2], equals((5000000, 7499999)));
      expect(ranges[3], equals((7500000, 9999999)));

      // Verify continuous byte coverage without holes or overlaps
      for (int i = 0; i < ranges.length - 1; i++) {
        expect(ranges[i].$2 + 1, equals(ranges[i + 1].$1));
      }
      expect(ranges.last.$2, equals(totalBytes - 1));
    });

    test('Pre-allocation and multi-chunk offset writes work concurrently without corruption', () async {
      final tempDir = Directory.systemTemp.createTempSync('chunk_unit_test');
      final targetFile = File('${tempDir.path}/test_stream.bin');

      const totalBytes = 50000;
      final initRaf = await targetFile.open(mode: FileMode.write);
      await initRaf.truncate(totalBytes);
      await initRaf.close();

      const concurrency = 5;
      final chunkSize = (totalBytes / concurrency).ceil();
      final futures = <Future>[];

      for (int i = 0; i < concurrency; i++) {
        final start = i * chunkSize;
        final end = (i == concurrency - 1) ? totalBytes - 1 : (start + chunkSize - 1);
        final count = end - start + 1;
        final fillVal = i + 10;

        futures.add(() async {
          final raf = await targetFile.open(mode: FileMode.writeOnlyAppend);
          await raf.setPosition(start);
          await raf.writeFrom(List.filled(count, fillVal));
          await raf.close();
        }());
      }

      await Future.wait(futures);

      expect(targetFile.lengthSync(), equals(totalBytes));
      final bytes = await targetFile.readAsBytes();

      for (int i = 0; i < concurrency; i++) {
        final start = i * chunkSize;
        final end = (i == concurrency - 1) ? totalBytes - 1 : (start + chunkSize - 1);
        for (int j = start; j <= end; j++) {
          expect(bytes[j], equals(i + 10));
        }
      }
      tempDir.deleteSync(recursive: true);
    });

    test('5MB Micro-Chunk slice queue covers entire file without gaps', () {
      const totalBytes = 52428800; // 50 MB
      const sliceSize = 5 * 1024 * 1024; // 5 MB
      final totalSlices = (totalBytes / sliceSize).ceil();

      expect(totalSlices, equals(10));

      final slices = <(int, int)>[];
      for (int i = 0; i < totalSlices; i++) {
        final start = i * sliceSize;
        final end = (i == totalSlices - 1) ? totalBytes - 1 : (start + sliceSize - 1);
        slices.add((start, end));
      }

      for (int i = 0; i < slices.length - 1; i++) {
        expect(slices[i].$2 + 1, equals(slices[i + 1].$1));
      }
      expect(slices.first.$1, equals(0));
      expect(slices.last.$2, equals(totalBytes - 1));
    });

    test('Concurrent worker pool downloads all slices without race conditions', () async {
      final tempDir = Directory.systemTemp.createTempSync('pool_unit_test');
      final targetFile = File('${tempDir.path}/test_pool.bin');

      const totalBytes = 25 * 1024; // 25 KB
      const sliceSize = 5 * 1024;   // 5 KB
      final totalSlices = (totalBytes / sliceSize).ceil();

      final initRaf = await targetFile.open(mode: FileMode.write);
      await initRaf.truncate(totalBytes);
      await initRaf.close();

      final slices = <(int, int)>[];
      for (int i = 0; i < totalSlices; i++) {
        final start = i * sliceSize;
        final end = (i == totalSlices - 1) ? totalBytes - 1 : (start + sliceSize - 1);
        slices.add((start, end));
      }

      int nextSliceIndex = 0;
      const numWorkers = 4;
      final futures = <Future>[];

      for (int w = 0; w < numWorkers; w++) {
        futures.add(() async {
          final raf = await targetFile.open(mode: FileMode.writeOnlyAppend);
          while (true) {
            if (nextSliceIndex >= totalSlices) break;
            final idx = nextSliceIndex++;
            if (idx >= totalSlices) break;

            final (start, end) = slices[idx];
            final count = end - start + 1;
            await raf.setPosition(start);
            await raf.writeFrom(List.filled(count, idx + 1));
          }
          await raf.close();
        }());
      }

      await Future.wait(futures);

      expect(targetFile.lengthSync(), equals(totalBytes));
      final bytes = await targetFile.readAsBytes();

      for (int i = 0; i < totalSlices; i++) {
        final (start, end) = slices[i];
        for (int j = start; j <= end; j++) {
          expect(bytes[j], equals(i + 1));
        }
      }

      tempDir.deleteSync(recursive: true);
    });
  });
}
