import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'src/pcm_to_ogg_platform_interface.dart';

/// An implementation of [PcmToOggPlatform] that uses method channels.
class MethodChannelPcmToOgg extends PcmToOggPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('pcm_to_ogg');

  /// Registers this class as the default instance of [PcmToOggPlatform].
  static void registerWith() {
    PcmToOggPlatform.instance = MethodChannelPcmToOgg();
  }

  @override
  Future<void> initialize() async {
    await methodChannel.invokeMethod('initialize');
  }

  @override
  Future<Uint8List> convert(
    Float32List pcmData, {
    required int channels,
    required int sampleRate,
    double quality = 0.4,
  }) async {
    final Uint8List? result = await methodChannel
        .invokeMethod<Uint8List>('convert', {
          'pcmData': pcmData,
          'channels': channels,
          'sampleRate': sampleRate,
          'quality': quality,
        });
    return result!;
  }

  // Streaming encoder methods - Method channel doesn't support streaming yet
  @override
  Future<StreamingEncoderHandle> createStreamingEncoder({
    required int channels,
    required int sampleRate,
    double quality = 0.4,
  }) async {
    final StreamingEncoderHandle? handle = await methodChannel
        .invokeMethod<StreamingEncoderHandle>('createStreamingEncoder', {
          'channels': channels,
          'sampleRate': sampleRate,
          'quality': quality,
        });
    return handle!;
  }

  @override
  Future<Uint8List?> encodeStreamingChunk(
    StreamingEncoderHandle handle,
    Float32List pcmChunk,
  ) async {
    final Uint8List? result = await methodChannel.invokeMethod<Uint8List>(
      'encodeStreamingChunk',
      {'handle': handle, 'pcmChunk': pcmChunk},
    );
    return result!;
  }

  @override
  Future<Uint8List> finishStreamingEncoding(
    StreamingEncoderHandle handle,
  ) async {
    final Uint8List? result = await methodChannel.invokeMethod<Uint8List>(
      'finishStreamingEncoding',
      {'handle': handle},
    );
    return result!;
  }

  @override
  Future<void> disposeStreamingEncoder(StreamingEncoderHandle handle) async {
    await methodChannel.invokeMethod<void>('disposeStreamingEncoder', {
      'handle': handle,
    });
  }
}
