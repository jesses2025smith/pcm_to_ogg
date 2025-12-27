import 'dart:async';
import 'dart:typed_data';

import 'package:pcm_to_ogg/src/pcm_to_ogg_platform_interface.dart';

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

  Future<StreamingEncoderHandle> createStreamingEncoder({
    required int channels,
    required int sampleRate,
    double quality = 0.4,
  });

  Future<Uint8List?> encodeStreamingChunk(
    StreamingEncoderHandle handle,
    Float32List pcmChunk,
  );

  Future<Uint8List> finishStreamingEncoding(StreamingEncoderHandle handle);

  Future<void> disposeStreamingEncoder(StreamingEncoderHandle handle);
}
