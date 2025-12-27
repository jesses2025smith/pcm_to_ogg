import 'dart:io';
import 'dart:typed_data';

/// WAV file header information
class WavInfo {
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int dataStartOffset;
  final int dataSize;

  WavInfo({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.dataStartOffset,
    required this.dataSize,
  });
}

/// A utility class for reading WAV files and extracting PCM data.
///
/// This class supports both reading the entire PCM data at once
/// and streaming/chunked reading for large files.
class WavReader {
  final File _file;
  late RandomAccessFile _raf;
  WavInfo? _info;

  WavReader(this._file);

  /// Open the file for reading.
  Future<void> open() async {
    _raf = await _file.open();
  }

  /// Close the file.
  Future<void> close() async {
    await _raf.close();
  }

  /// Read and parse the WAV file header.
  ///
  /// Returns [WavInfo] containing audio format information.
  Future<WavInfo> readHeader() async {
    await _raf.setPosition(0);

    // Read RIFF header (12 bytes)
    final riffHeader = await _raf.read(12);
    if (riffHeader.length < 12 ||
        String.fromCharCodes(riffHeader.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(riffHeader.sublist(8, 12)) != 'WAVE') {
      throw Exception('Invalid WAV file: missing RIFF/WAVE header');
    }

    // Find fmt chunk
    int position = 12;
    bool foundFmt = false;
    int sampleRate = 0;
    int channels = 0;
    int bitsPerSample = 0;

    while (position < 100) {
      // Search within first 100 bytes
      await _raf.setPosition(position);
      final chunkHeader = await _raf.read(8);
      if (chunkHeader.length < 8) break;

      final chunkId = String.fromCharCodes(chunkHeader.sublist(0, 4));
      final chunkSize = _readInt32LE(chunkHeader, 4);

      if (chunkId == 'fmt ') {
        foundFmt = true;
        final fmtData = await _raf.read(chunkSize);
        if (fmtData.length >= 16) {
          // audioFormat = _readInt16LE(fmtData, 0); // Not used, but could validate PCM format
          channels = _readInt16LE(fmtData, 2);
          sampleRate = _readInt32LE(fmtData, 4);
          // Skip byte rate and block align
          bitsPerSample = _readInt16LE(fmtData, 14);
        }
        position += 8 + chunkSize;
      } else if (chunkId == 'data') {
        final dataStart = position + 8;
        final dataSize = chunkSize;
        _info = WavInfo(
          sampleRate: sampleRate,
          channels: channels,
          bitsPerSample: bitsPerSample,
          dataStartOffset: dataStart,
          dataSize: dataSize,
        );
        return _info!;
      } else {
        position += 8 + chunkSize;
      }
    }

    if (!foundFmt) {
      throw Exception('Invalid WAV file: fmt chunk not found');
    }

    // If we didn't find data chunk yet, search for it
    await _raf.setPosition(position);
    while (true) {
      final chunkHeader = await _raf.read(8);
      if (chunkHeader.length < 8) {
        throw Exception('Invalid WAV file: data chunk not found');
      }

      final chunkId = String.fromCharCodes(chunkHeader.sublist(0, 4));
      final chunkSize = _readInt32LE(chunkHeader, 4);

      if (chunkId == 'data') {
        final dataStart = position + 8;
        final dataSize = chunkSize;
        _info = WavInfo(
          sampleRate: sampleRate,
          channels: channels,
          bitsPerSample: bitsPerSample,
          dataStartOffset: dataStart,
          dataSize: dataSize,
        );
        return _info!;
      }

      position += 8 + chunkSize;
      await _raf.setPosition(position);
    }
  }

  /// Get WAV file info (reads header if not already read).
  Future<WavInfo> getInfo() async {
    if (_info == null) {
      await readHeader();
    }
    return _info!;
  }

  /// Read PCM data chunk as Float32List.
  ///
  /// [offset] - Byte offset from the start of PCM data
  /// [size] - Number of bytes to read
  ///
  /// Returns Float32List containing the PCM samples.
  Future<Float32List> readPcmChunk(int offset, int size) async {
    if (_info == null) {
      await readHeader();
    }

    final info = _info!;
    final absoluteOffset = info.dataStartOffset + offset;

    // Ensure we don't read beyond the data chunk
    final maxSize = info.dataSize - offset;
    final readSize = size > maxSize ? maxSize : size;

    await _raf.setPosition(absoluteOffset);
    final bytes = await _raf.read(readSize);

    // Convert bytes to Float32List based on bits per sample
    if (info.bitsPerSample == 16) {
      return _convertInt16ToFloat32(bytes, info.channels);
    } else if (info.bitsPerSample == 32) {
      // Assume 32-bit integer PCM (not float)
      return _convertInt32ToFloat32(bytes, info.channels);
    } else {
      throw Exception('Unsupported bits per sample: ${info.bitsPerSample}');
    }
  }

  /// Read all PCM data as Float32List.
  Future<Float32List> readAllPcmData() async {
    if (_info == null) {
      await readHeader();
    }
    return readPcmChunk(0, _info!.dataSize);
  }

  /// Convert 16-bit PCM to Float32List (normalized to -1.0 to 1.0)
  Float32List _convertInt16ToFloat32(Uint8List bytes, int channels) {
    final samples = bytes.length ~/ 2;
    final result = Float32List(samples);
    final view = bytes.buffer.asInt16List(bytes.offsetInBytes, samples);

    for (int i = 0; i < samples; i++) {
      result[i] = view[i] / 32768.0;
    }

    return result;
  }

  /// Convert 32-bit integer PCM to Float32List (normalized to -1.0 to 1.0)
  Float32List _convertInt32ToFloat32(Uint8List bytes, int channels) {
    final samples = bytes.length ~/ 4;
    final result = Float32List(samples);
    final view = bytes.buffer.asInt32List(bytes.offsetInBytes, samples);

    for (int i = 0; i < samples; i++) {
      result[i] = view[i] / 2147483648.0;
    }

    return result;
  }

  int _readInt16LE(Uint8List bytes, int offset) {
    final low = bytes[offset];
    final high = bytes[offset + 1];
    final value = low | (high << 8);
    // Sign extend if negative
    return (value & 0x8000) != 0 ? (value | 0xFFFF0000) : value;
  }

  int _readInt32LE(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }
}
