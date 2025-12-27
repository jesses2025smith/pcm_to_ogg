import 'dart:async';

import 'dart:typed_data';

abstract class StreamingEncoderHandle {
  int get address;
}

abstract class PcmToOggPlatform {
  static PcmToOggPlatform? _instance;

  static PcmToOggPlatform get instance {
    if (_instance == null) {
      throw Exception(
        'PcmToOggPlatform not registered. Ensure the platform implementation is set.',
      );
    }
    return _instance!;
  }

  static set instance(PcmToOggPlatform impl) {
    _instance = impl;
  }

  Future<void> initialize();

  Future<Uint8List> convert(
    Float32List pcmData, {
    required int channels,
    required int sampleRate,
    double quality = 0.4,
  });

  // Streaming encoder methods for large file conversion

  /// Create a new streaming encoder instance.
  ///
  /// Returns a handle that must be used for subsequent operations.
  Future<StreamingEncoderHandle> createStreamingEncoder({
    required int channels,
    required int sampleRate,
    double quality = 0.4,
  });

  /// Encode a chunk of PCM data using the streaming encoder.
  ///
  /// Returns the encoded OGG data chunk, or null if no data is ready yet.
  /// The first call will return the OGG header data.
  Future<Uint8List?> encodeStreamingChunk(
    StreamingEncoderHandle handle,
    Float32List pcmChunk,
  );

  /// Finish encoding and return any remaining OGG data.
  ///
  /// This should be called after all PCM data has been encoded.
  Future<Uint8List> finishStreamingEncoding(StreamingEncoderHandle handle);

  /// Dispose of the streaming encoder and free resources.
  ///
  /// This should be called when you're done with the encoder.
  Future<void> disposeStreamingEncoder(StreamingEncoderHandle handle);
}
