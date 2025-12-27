// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;
import '../pcm_to_ogg_platform_interface.dart';

/// Web platform implementation of StreamingEncoderHandle using int address
class _WebStreamingEncoderHandle implements StreamingEncoderHandle {
  final int _address;

  const _WebStreamingEncoderHandle(this._address);

  @override
  int get address => _address;
}

// Extension for the result of WebAssembly.instantiate
extension type WasmInstantiateResult._(JSObject _) implements JSObject {
  external JSObject get instance;
}

// Extension for WebAssembly.Instance
extension type WasmInstance._(JSObject _) implements JSObject {
  external _WasmExports get exports;
}

// Extension for the Wasm module's exports
extension type _WasmExports._(JSObject _) implements JSObject {
  @JS('_malloc')
  external JSNumber malloc(JSNumber size);
  @JS('_free')
  external void free(JSNumber ptr);
  @JS('_encode_pcm_to_ogg')
  external JSNumber encode_pcm_to_ogg(
    JSNumber pcmPtr,
    JSNumber numSamples,
    JSNumber channels,
    JSNumber sampleRate,
    JSNumber quality,
  );
  @JS('_get_ogg_output_data')
  external JSNumber get_ogg_output_data(JSNumber ptr);
  @JS('_get_ogg_output_size')
  external JSNumber get_ogg_output_size(JSNumber ptr);
  @JS('_free_ogg_output')
  external void free_ogg_output(JSNumber ptr);

  // Streaming encoding functions
  @JS('_create_ogg_encoder')
  external JSNumber create_ogg_encoder(
    JSNumber channels,
    JSNumber sampleRate,
    JSNumber quality,
  );
  @JS('_encode_pcm_chunk')
  external JSNumber encode_pcm_chunk(
    JSNumber encoderCtx,
    JSNumber pcmData,
    JSNumber numSamples,
  );
  @JS('_finish_encoding')
  external JSNumber finish_encoding(JSNumber encoderCtx);
  @JS('_destroy_ogg_encoder')
  external void destroy_ogg_encoder(JSNumber encoderCtx);

  // Thuộc tính heap views được cung cấp bởi Emscripten
  @JS('HEAPU8')
  external JSUint8Array get HEAPU8;
  @JS('HEAPF32')
  external JSFloat32Array get HEAPF32;
}

// Extension để thêm phương thức .slice()
extension JSUint8ArrayExt on JSUint8Array {
  external JSUint8Array slice(int begin, [int? end]);
}

// Extension để thêm phương thức .set()
extension JSFloat32ArrayExt on JSFloat32Array {
  external void set(JSAny array, [int offset]);
}

/// The web implementation of the PcmToOggPlatform.
class PcmToOggWeb extends PcmToOggPlatform {
  JSObject? _wasmModule;
  _WasmExports? _wasmExports;
  bool _isInitialized = false;

  static void registerWith(Registrar registrar) {
    PcmToOggPlatform.instance = PcmToOggWeb();
  }

  PcmToOggWeb();

  @override
  Future<void> initialize() async {
    if (_isInitialized && _wasmModule != null && _wasmExports != null) {
      return;
    }
    _isInitialized = false; // Đặt lại cờ nếu có gì đó không ổn

    // 1. If the factory doesn't exist, inject the script and wait for it.
    if (!globalContext.hasProperty('PcmToOggModuleFactory'.toJS).toDart) {
      final script = web.HTMLScriptElement()
        ..type = 'module'
        ..innerHTML = '''
          import createPcmToOggModule from '/pcm_to_ogg.js';
          window.PcmToOggModuleFactory = createPcmToOggModule;
        '''
            .toJS;
      web.document.head!.appendChild(script);

      // 2. Poll to check when the factory is available.
      const maxRetries = 200; // Wait up to 10 seconds
      var retries = 0;
      while (!globalContext.hasProperty('PcmToOggModuleFactory'.toJS).toDart) {
        if (retries++ > maxRetries) {
          throw Exception(
            'PcmToOggWeb: Timed out waiting for PcmToOggModuleFactory.',
          );
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
    } else {}

    final createModule = globalContext['PcmToOggModuleFactory'] as JSFunction;
    final modulePromise =
        createModule.callAsFunction(globalContext) as JSPromise;

    final module = (await modulePromise.toDart) as JSObject;

    // Chờ cho runtime C++ sẵn sàng ***
    final completer = Completer<void>();
    bool runtimeReady = false;

    // Kiểm tra xem nó đã chạy xong chưa (trong trường hợp hot reload)
    // *** ĐÃ SỬA LỖI PHƯƠNG THỨC (toDartBoolean -> toDart) TẠI ĐÂY ***
    final JSAny? calledRunProp = module.getProperty('calledRun'.toJS);
    if (module.hasProperty('calledRun'.toJS).toDart &&
        calledRunProp is JSBoolean &&
        calledRunProp.toDart) {
      runtimeReady = true;
    } else {
      // Gán callback
      module.setProperty(
        'onRuntimeInitialized'.toJS,
        () {
          runtimeReady = true;
          if (!completer.isCompleted) {
            completer.complete();
          }
        }.toJS,
      );
    }

    // Nếu chưa sẵn sàng, hãy đợi completer
    if (!runtimeReady) {
      await completer.future;
    }
    // *** KẾT THÚC SỬA LỖI ***

    _wasmModule = module;
    _wasmExports = _WasmExports._(module);

    // Kiểm tra nhanh xem HEAPF32 có thực sự tồn tại không
    if (!_wasmExports!.hasProperty('HEAPF32'.toJS).toDart) {
      throw Exception('PcmToOggWeb: HEAPF32 not found on Wasm module.');
    }
    _isInitialized = true;
  }

  @override
  Future<Uint8List> convert(
    Float32List pcmData, {
    required int channels,
    required int sampleRate,
    double quality = 0.4,
  }) async {
    await initialize();

    if (_wasmExports == null || _wasmModule == null) {
      // Thêm kiểm tra này để đảm bảo initialize() đã chạy đúng
      if (!_isInitialized) {
        throw Exception('Wasm module initialization failed or never ran.');
      }
      throw Exception(
        'Wasm module references are null despite initialization.',
      );
    }

    final pcmDataSize = pcmData.length * pcmData.elementSizeInBytes;
    final pcmPtr = _wasmExports!.malloc(pcmDataSize.toJS).toDartInt;

    if (pcmPtr == 0) {
      throw Exception('Wasm _malloc failed to allocate memory for PCM data.');
    }

    try {
      // --- BƯỚC 1: GHI DỮ LIỆU VÀO WASM ---
      try {
        // Lấy view HEAPF32 trực tiếp từ module
        final JSFloat32Array wasmHeapF32View = _wasmExports!.HEAPF32;

        // Ghi dữ liệu vào heap bằng phương thức .set() từ extension
        // pcmPtr là một byte offset. HEAPF32 là một Float32Array
        // nên chỉ số (offset) của nó là (byteOffset / 4) hoặc (byteOffset >> 2)
        wasmHeapF32View.set(
          pcmData.toJS,
          pcmPtr >> 2,
        ); // set(source, targetOffset)
      } catch (e) {
        throw Exception('Failed to write PCM data to Wasm heap.');
      }

      // --- BƯỚC 2: GỌI HÀM WASM ---
      final resultPtr = _wasmExports!
          .encode_pcm_to_ogg(
            pcmPtr.toJS,
            pcmData.length.toJS,
            channels.toJS,
            sampleRate.toJS,
            quality.toJS,
          )
          .toDartInt;

      if (resultPtr == 0) {
        throw Exception(
          'Wasm function \'encode_pcm_to_ogg\' returned a null pointer.',
        );
      }

      try {
        // --- BƯỚC 3: ĐỌC KẾT QUẢ TỪ WASM ---
        final dataPtr =
            _wasmExports!.get_ogg_output_data(resultPtr.toJS).toDartInt;
        final size =
            _wasmExports!.get_ogg_output_size(resultPtr.toJS).toDartInt;

        if (dataPtr == 0) {
          throw Exception(
            'Wasm function returned a null data pointer inside the result struct.',
          );
        }
        if (size == 0) {
          return Uint8List(0);
        }

        // Lấy view HEAPU8 trực tiếp.
        final JSUint8Array heapU8View = _wasmExports!.HEAPU8;

        // Gọi phương thức .slice() từ extension
        final oggData = heapU8View.slice(dataPtr, dataPtr + size).toDart;
        return oggData;
      } finally {
        // Giải phóng con trỏ kết quả (struct)
        _wasmExports!.free_ogg_output(resultPtr.toJS);
      }
    } catch (e) {
      throw Exception('Caught a general exception in convert: $e');
      // return Uint8List(0);
    } finally {
      // Luôn giải phóng bộ đệm PCM đã cấp phát
      _wasmExports!.free(pcmPtr.toJS);
    }
  }

  @override
  Future<StreamingEncoderHandle> createStreamingEncoder({
    required int channels,
    required int sampleRate,
    double quality = 0.4,
  }) async {
    await initialize();

    if (_wasmExports == null || _wasmModule == null) {
      if (!_isInitialized) {
        throw Exception('Wasm module initialization failed or never ran.');
      }
      throw Exception(
        'Wasm module references are null despite initialization.',
      );
    }

    final encoderCtxPtr = _wasmExports!
        .create_ogg_encoder(channels.toJS, sampleRate.toJS, quality.toJS)
        .toDartInt;

    if (encoderCtxPtr == 0) {
      throw Exception('Failed to create OGG streaming encoder');
    }

    return _WebStreamingEncoderHandle(encoderCtxPtr);
  }

  @override
  Future<Uint8List?> encodeStreamingChunk(
    StreamingEncoderHandle handle,
    Float32List pcmChunk,
  ) async {
    await initialize();

    if (_wasmExports == null || _wasmModule == null) {
      throw Exception('Wasm module not initialized');
    }

    final encoderCtxPtr = handle.address;

    // Allocate memory for PCM data
    final pcmDataSize = pcmChunk.length * pcmChunk.elementSizeInBytes;
    final pcmPtr = _wasmExports!.malloc(pcmDataSize.toJS).toDartInt;

    if (pcmPtr == 0) {
      throw Exception('Wasm _malloc failed to allocate memory for PCM data.');
    }

    try {
      // Write PCM data to WASM heap
      final JSFloat32Array wasmHeapF32View = _wasmExports!.HEAPF32;
      wasmHeapF32View.set(pcmChunk.toJS, pcmPtr >> 2);

      // Call encoding function
      final resultPtr = _wasmExports!
          .encode_pcm_chunk(
            encoderCtxPtr.toJS,
            pcmPtr.toJS,
            pcmChunk.length.toJS,
          )
          .toDartInt;

      if (resultPtr == 0) {
        return null; // No data ready yet
      }

      try {
        // Read result
        final dataPtr =
            _wasmExports!.get_ogg_output_data(resultPtr.toJS).toDartInt;
        final size =
            _wasmExports!.get_ogg_output_size(resultPtr.toJS).toDartInt;

        if (dataPtr == 0 || size == 0) {
          return null;
        }

        // Read data from heap
        final JSUint8Array heapU8View = _wasmExports!.HEAPU8;
        final oggData = heapU8View.slice(dataPtr, dataPtr + size).toDart;
        return oggData;
      } finally {
        _wasmExports!.free_ogg_output(resultPtr.toJS);
      }
    } finally {
      _wasmExports!.free(pcmPtr.toJS);
    }
  }

  @override
  Future<Uint8List> finishStreamingEncoding(
    StreamingEncoderHandle handle,
  ) async {
    await initialize();

    if (_wasmExports == null || _wasmModule == null) {
      throw Exception('Wasm module not initialized');
    }

    final encoderCtxPtr = handle.address;

    final resultPtr =
        _wasmExports!.finish_encoding(encoderCtxPtr.toJS).toDartInt;

    if (resultPtr == 0) {
      throw Exception('Failed to finish encoding');
    }

    try {
      final dataPtr =
          _wasmExports!.get_ogg_output_data(resultPtr.toJS).toDartInt;
      final size = _wasmExports!.get_ogg_output_size(resultPtr.toJS).toDartInt;

      if (dataPtr == 0 || size == 0) {
        return Uint8List(0);
      }

      final JSUint8Array heapU8View = _wasmExports!.HEAPU8;
      final oggData = heapU8View.slice(dataPtr, dataPtr + size).toDart;
      return oggData;
    } finally {
      _wasmExports!.free_ogg_output(resultPtr.toJS);
    }
  }

  @override
  Future<void> disposeStreamingEncoder(StreamingEncoderHandle handle) async {
    await initialize();

    if (_wasmExports == null || _wasmModule == null) {
      throw Exception('Wasm module not initialized');
    }

    final encoderCtxPtr = handle.address;
    _wasmExports!.destroy_ogg_encoder(encoderCtxPtr.toJS);
  }
}
