import 'dart:ffi';
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart';
import 'dart:typed_data';

import '../pcm_to_ogg_platform_interface.dart';

/// Native platform implementation of StreamingEncoderHandle using Pointer<Void>
class _NativeStreamingEncoderHandle implements StreamingEncoderHandle {
  final Pointer<Void> _pointer;

  const _NativeStreamingEncoderHandle(this._pointer);

  @override
  int get address => _pointer.address;

  Pointer<Void> get pointer => _pointer;
}

// --- C-side Struct Definition ---
final class _OggOutput extends Struct {
  external Pointer<Uint8> data;
  @Int32()
  external int size;
}

// --- Streaming Encoder FFI Function Signatures ---
typedef _CreateEncoderNative = Pointer<Void> Function(
    Int32 channels, Int64 sampleRate, Float quality);
typedef _CreateEncoderDart = Pointer<Void> Function(
    int channels, int sampleRate, double quality);

typedef _EncodeChunkNative = Pointer<_OggOutput> Function(
  Pointer<Void> encoderCtx,
  Pointer<Float> pcmData,
  Int64 numSamples,
);
typedef _EncodeChunkDart = Pointer<_OggOutput> Function(
  Pointer<Void> encoderCtx,
  Pointer<Float> pcmData,
  int numSamples,
);

typedef _FinishEncodingNative = Pointer<_OggOutput> Function(
    Pointer<Void> encoderCtx);
typedef _FinishEncodingDart = Pointer<_OggOutput> Function(
    Pointer<Void> encoderCtx);

typedef _DestroyEncoderNative = Void Function(Pointer<Void> encoderCtx);
typedef _DestroyEncoderDart = void Function(Pointer<Void> encoderCtx);

// --- FFI Function Signatures ---
typedef _EncodePcmToOggNative = Pointer<_OggOutput> Function(
  Pointer<Float> pcmData,
  Int64 numSamples,
  Int32 channels,
  Int64 sampleRate,
  Float quality,
);
typedef _EncodePcmToOggDart = Pointer<_OggOutput> Function(
  Pointer<Float> pcmData,
  int numSamples,
  int channels,
  int sampleRate,
  double quality,
);

typedef _FreeOggOutputNative = Void Function(Pointer<_OggOutput>);
typedef _FreeOggOutputDart = void Function(Pointer<_OggOutput>);

/// The native implementation of the PcmToOggPlatform.
class PcmToOggNative extends PcmToOggPlatform {
  static late final _EncodePcmToOggDart _encodePcmToOgg;
  static late final _FreeOggOutputDart _freeOggOutput;

  // Streaming encoder FFI functions
  static _CreateEncoderDart? _createEncoder;
  static _EncodeChunkDart? _encodeChunk;
  static _FinishEncodingDart? _finishEncoding;
  static _DestroyEncoderDart? _destroyEncoder;

  bool _isInitialized = false;

  /// Registers the native implementation with the platform interface.
  static void registerWith() {
    PcmToOggPlatform.instance = PcmToOggNative();
  }

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    final dylib = _loadNativeLibrary();

    _encodePcmToOgg = dylib
        .lookup<NativeFunction<_EncodePcmToOggNative>>('encode_pcm_to_ogg')
        .asFunction();

    _freeOggOutput = dylib
        .lookup<NativeFunction<_FreeOggOutputNative>>('free_ogg_output')
        .asFunction();

    _createEncoder = dylib
        .lookup<NativeFunction<_CreateEncoderNative>>('create_ogg_encoder')
        .asFunction();

    _encodeChunk = dylib
        .lookup<NativeFunction<_EncodeChunkNative>>('encode_pcm_chunk')
        .asFunction();

    _finishEncoding = dylib
        .lookup<NativeFunction<_FinishEncodingNative>>('finish_encoding')
        .asFunction();

    _destroyEncoder = dylib
        .lookup<NativeFunction<_DestroyEncoderNative>>('destroy_ogg_encoder')
        .asFunction();

    _isInitialized = true;
  }

  static DynamicLibrary _loadNativeLibrary() {
    if (Platform.isMacOS || Platform.isIOS) {
      return DynamicLibrary.open('pcm_to_ogg.framework/pcm_to_ogg');
    }
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libpcm_to_ogg.so');
    }
    if (Platform.isLinux) {
      // On Linux, try libpcm_to_ogg_plugin.so first (for plugin build),
      // fallback to libpcm_to_ogg.so
      try {
        return DynamicLibrary.open('libpcm_to_ogg_plugin.so');
      } catch (e) {
        return DynamicLibrary.open('libpcm_to_ogg.so');
      }
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('pcm_to_ogg_plugin.dll');
    }
    throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
  }

  @override
  Future<Uint8List> convert(
    Float32List pcmData, {
    required int channels,
    required int sampleRate,
    double quality = 0.4,
  }) async {
    if (!_isInitialized) {
      throw Exception(
        'PcmToOgg.initialize() must be called before using convert().',
      );
    }

    final pcmPointer = calloc<Float>(pcmData.length);
    pcmPointer.asTypedList(pcmData.length).setAll(0, pcmData);

    try {
      final resultPointer = _encodePcmToOgg(
        pcmPointer,
        pcmData.length,
        channels,
        sampleRate,
        quality,
      );

      if (resultPointer == nullptr) {
        throw Exception(
          'Failed to encode PCM data. The native function returned a null pointer.',
        );
      }

      try {
        final int size = resultPointer.ref.size;
        final Pointer<Uint8> dataPointer = resultPointer.ref.data;

        if (dataPointer == nullptr) {
          throw Exception(
            'Native function returned a null data pointer inside the result struct.',
          );
        }

        final oggData = Uint8List.fromList(dataPointer.asTypedList(size));
        return oggData;
      } finally {
        _freeOggOutput(resultPointer);
      }
    } finally {
      calloc.free(pcmPointer);
    }
  }

  // Streaming encoder methods

  @override
  Future<StreamingEncoderHandle> createStreamingEncoder({
    required int channels,
    required int sampleRate,
    double quality = 0.4,
  }) async {
    if (!_isInitialized) {
      throw Exception(
        'PcmToOgg.initialize() must be called before using createStreamingEncoder().',
      );
    }

    final encoderCtx = _createEncoder!(channels, sampleRate, quality);
    if (encoderCtx == nullptr) {
      throw Exception('Failed to create OGG streaming encoder');
    }

    return _NativeStreamingEncoderHandle(encoderCtx);
  }

  @override
  Future<Uint8List?> encodeStreamingChunk(
    StreamingEncoderHandle handle,
    Float32List pcmChunk,
  ) async {
    if (!_isInitialized) {
      throw Exception(
        'PcmToOgg.initialize() must be called before using encodeStreamingChunk().',
      );
    }

    if (handle is! _NativeStreamingEncoderHandle) {
      throw ArgumentError('Invalid encoder handle type');
    }
    final encoderCtx = handle.pointer;
    final pcmPointer = calloc<Float>(pcmChunk.length);
    pcmPointer.asTypedList(pcmChunk.length).setAll(0, pcmChunk);

    try {
      final resultPointer = _encodeChunk!(
        encoderCtx,
        pcmPointer,
        pcmChunk.length,
      );

      if (resultPointer == nullptr) {
        throw Exception('Failed to encode PCM chunk');
      }

      try {
        final int size = resultPointer.ref.size;
        if (size == 0) {
          return null; // No data to return
        }

        final Pointer<Uint8> dataPointer = resultPointer.ref.data;
        if (dataPointer == nullptr) {
          return null;
        }

        final oggData = Uint8List.fromList(dataPointer.asTypedList(size));
        return oggData;
      } finally {
        _freeOggOutput(resultPointer);
      }
    } finally {
      calloc.free(pcmPointer);
    }
  }

  @override
  Future<Uint8List> finishStreamingEncoding(
    StreamingEncoderHandle handle,
  ) async {
    if (!_isInitialized) {
      throw Exception(
        'PcmToOgg.initialize() must be called before using finishStreamingEncoding().',
      );
    }

    if (handle is! _NativeStreamingEncoderHandle) {
      throw ArgumentError('Invalid encoder handle type');
    }
    final encoderCtx = handle.pointer;
    final resultPointer = _finishEncoding!(encoderCtx);

    if (resultPointer == nullptr) {
      throw Exception('Failed to finish encoding');
    }

    try {
      final int size = resultPointer.ref.size;
      final Pointer<Uint8> dataPointer = resultPointer.ref.data;

      if (dataPointer == nullptr || size == 0) {
        return Uint8List(0);
      }

      final oggData = Uint8List.fromList(dataPointer.asTypedList(size));
      return oggData;
    } finally {
      _freeOggOutput(resultPointer);
    }
  }

  @override
  Future<void> disposeStreamingEncoder(StreamingEncoderHandle handle) async {
    if (!_isInitialized) {
      throw Exception(
        'PcmToOgg.initialize() must be called before using disposeStreamingEncoder().',
      );
    }

    if (handle is! _NativeStreamingEncoderHandle) {
      throw ArgumentError('Invalid encoder handle type');
    }
    _destroyEncoder!(handle.pointer);
  }
}
