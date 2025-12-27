import 'dart:async';
import 'dart:typed_data';

import '../pcm_to_ogg_platform_interface.dart';

class PcmToOggWeb extends PcmToOggPlatform {
  static Future<PcmToOggWeb> create() async {
    throw UnimplementedError('Web platform not supported on this build.');
  }

  @override
  Future<void> initialize() {
    throw UnimplementedError('Web platform not supported on this build.');
  }

  @override
  Future<Uint8List> convert(
    Float32List pcmData, {
    required int channels,
    required int sampleRate,
    double quality = 0.4,
  }) {
    throw UnimplementedError('Web platform not supported on this build.');
  }

  @override
  Future<StreamingEncoderHandle> createStreamingEncoder({
    required int channels,
    required int sampleRate,
    double quality = 0.4,
  }) {
    throw UnimplementedError('Streaming encoding not supported on web stub.');
  }

  @override
  Future<Uint8List?> encodeStreamingChunk(
    StreamingEncoderHandle handle,
    Float32List pcmChunk,
  ) {
    throw UnimplementedError('Streaming encoding not supported on web stub.');
  }

  @override
  Future<Uint8List> finishStreamingEncoding(StreamingEncoderHandle handle) {
    throw UnimplementedError('Streaming encoding not supported on web stub.');
  }

  @override
  Future<void> disposeStreamingEncoder(StreamingEncoderHandle handle) {
    throw UnimplementedError('Streaming encoding not supported on web stub.');
  }
}

class PcmToOggNative extends PcmToOggPlatform {
  PcmToOggNative() {
    throw UnimplementedError('Native platform not supported on this build.');
  }

  static void registerWith() {
    // No-op for stub implementation
  }

  @override
  Future<void> initialize() {
    throw UnimplementedError('Native platform not supported on this build.');
  }

  @override
  Future<Uint8List> convert(
    Float32List pcmData, {
    required int channels,
    required int sampleRate,
    double quality = 0.4,
  }) {
    throw UnimplementedError('Native platform not supported on this build.');
  }

  @override
  Future<StreamingEncoderHandle> createStreamingEncoder({
    required int channels,
    required int sampleRate,
    double quality = 0.4,
  }) {
    throw UnimplementedError(
      'Streaming encoding not supported on native stub.',
    );
  }

  @override
  Future<Uint8List?> encodeStreamingChunk(
    StreamingEncoderHandle handle,
    Float32List pcmChunk,
  ) {
    throw UnimplementedError(
      'Streaming encoding not supported on native stub.',
    );
  }

  @override
  Future<Uint8List> finishStreamingEncoding(StreamingEncoderHandle handle) {
    throw UnimplementedError(
      'Streaming encoding not supported on native stub.',
    );
  }

  @override
  Future<void> disposeStreamingEncoder(StreamingEncoderHandle handle) {
    throw UnimplementedError(
      'Streaming encoding not supported on native stub.',
    );
  }
}
