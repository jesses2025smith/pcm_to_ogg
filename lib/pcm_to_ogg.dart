import 'dart:async';

import 'package:flutter/foundation.dart';

import 'src/pcm_to_ogg_platform_interface.dart';
import 'src/native/pcm_to_ogg_native.dart'
    if (dart.library.html) 'src/stub/pcm_to_ogg_stub.dart'
    as native_impl;

class PcmToOgg {
  StreamingEncoderHandle? _handle;

  // Auto-register platform implementation when class is first accessed
  static bool _registered = false;
  static void _ensureRegistered() {
    if (!_registered) {
      if (!kIsWeb) {
        try {
          // Use conditional import - this will be PcmToOggNative on native platforms
          // and PcmToOggNative stub (which throws) on web
          native_impl.PcmToOggNative.registerWith();
        } catch (e) {
          // On web or if registration fails, the plugin system will handle registration
        }
      }
      _registered = true;
    }
  }

  static Future<void> initialize() async {
    _ensureRegistered();
    await PcmToOggPlatform.instance.initialize();
  }

  static Future<Uint8List> convert(
    Float32List pcmData, {
    required int channels,
    required int sampleRate,
    double quality = 0.4,
  }) async {
    return PcmToOggPlatform.instance.convert(
      pcmData,
      channels: channels,
      sampleRate: sampleRate,
      quality: quality,
    );
  }

  Future<void> initializeStreamingEncoder({
    required int channels,
    required int sampleRate,
    double quality = 0.4,
  }) async {
    await dispose();

    _handle = await PcmToOggPlatform.instance.createStreamingEncoder(
      channels: channels,
      sampleRate: sampleRate,
      quality: quality,
    );
  }

  /// Encode a chunk of PCM data.
  ///
  /// Returns the encoded OGG data chunk, or null if no data is ready yet.
  /// The first call will return the OGG header data.
  Future<Uint8List?> encodeChunk(Float32List pcmChunk) async {
    if (_handle == null) {
      throw Exception(
        'Encoder not initialized. Call initializeStreamingEncoder() first.',
      );
    }

    return await PcmToOggPlatform.instance.encodeStreamingChunk(
      _handle!,
      pcmChunk,
    );
  }

  /// Finish encoding and return any remaining OGG data.
  ///
  /// This should be called after all PCM data has been encoded.
  Future<Uint8List> finish() async {
    if (_handle == null) {
      throw Exception(
        'Encoder not initialized. Call initializeStreamingEncoder() first.',
      );
    }

    return await PcmToOggPlatform.instance.finishStreamingEncoding(_handle!);
  }

  /// Dispose of the encoder and free resources.
  ///
  /// This should be called when you're done with the encoder.
  Future<void> dispose() async {
    if (_handle != null) {
      await PcmToOggPlatform.instance.disposeStreamingEncoder(_handle!);
      _handle = null;
    }
  }
}
