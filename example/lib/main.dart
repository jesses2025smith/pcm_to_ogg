import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, Float32List;
import 'package:flutter/material.dart';
import 'package:pcm_to_ogg/pcm_to_ogg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';

import 'wav_reader.dart';

const wavFilename = 'hype-drill-music-438398.wav';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Note: Platform registration is handled automatically by Flutter plugins.
  // On native platforms, the plugin registers itself via the plugin registry.
  // The web implementation is registered automatically.
  // We will initialize it asynchronously in the app itself.

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _status = 'Press the button to start.';
  Uint8List? _oggData;
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isPluginReady = false;
  bool _isInitializing = false;
  String _initError = '';

  // Streaming conversion related state
  bool _isStreamingConverting = false;
  double _streamingProgress = 0.0;
  String? _selectedWavFile; // For native platforms
  String? _selectedWavFileName; // File name for display
  String? _outputOggFile;

  @override
  void initState() {
    super.initState();
    _initializePlugin();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initializePlugin() async {
    // On non-web platforms, initialization is instant.
    // if (!kIsWeb) {
    //   setState(() {
    //     _isPluginReady = true;
    //     _status = 'Plugin ready on native platform.';
    //   });
    //   return;
    // }

    // On web, it needs to download and compile the Wasm module.
    setState(() {
      _isInitializing = true;
      _status = 'Initializing WebAssembly module...';
    });

    try {
      await PcmToOgg.initialize();
      setState(() {
        _isPluginReady = true;
        _status = 'Plugin initialized. Click the button to convert.';
      });
    } catch (e) {
      setState(() {
        _initError = 'Failed to load plugin: $e';
        _status = _initError;
      });
    } finally {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  // Function to generate dummy PCM data (1 second sine wave at 440Hz)
  Float32List _generateDummyPcmData() {
    const sampleRate = 44100;
    const duration = 1; // 1 second
    const frequency = 440.0; // A4 note
    const numSamples = sampleRate * duration;

    final random = Random();
    final list = Float32List(numSamples);
    for (var i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      // Generate sine wave with a bit of noise
      list[i] =
          sin(2 * pi * frequency * t) * 0.5 +
          (random.nextDouble() - 0.5) * 0.01;
    }
    return list;
  }

  Future<void> _runConversion() async {
    if (!_isPluginReady) return;

    setState(() {
      _status = 'Generating PCM data...';
      _oggData = null;
    });

    // Generate 32-bit float PCM data, mono
    final pcmData = _generateDummyPcmData();

    setState(() {
      _status =
          'PCM data generated (${pcmData.lengthInBytes} bytes). Converting to OGG...';
    });

    try {
      await _audioPlayer.stop(); // Stop playback if playing
      final stopwatch = Stopwatch()..start();
      final oggData = await PcmToOgg.convert(
        pcmData,
        channels: 1, // Mono
        sampleRate: 44100,
        quality: 0.6,
      );
      stopwatch.stop();

      setState(() {
        _status =
            'Conversion successful in ${stopwatch.elapsedMilliseconds}ms! OGG data size: ${oggData.lengthInBytes} bytes.';
        _oggData = oggData;
      });
    } catch (e) {
      setState(() {
        _status = 'An error occurred during conversion: $e';
      });
    }
  }

  Future<void> _playOggData() async {
    if (_oggData == null) return;

    try {
      await _audioPlayer.play(BytesSource(_oggData!));
      setState(() {
        _status = 'Playing audio...';
      });

      _audioPlayer.onPlayerComplete.first.then((_) {
        setState(() {
          _status = 'Playback complete.';
        });
      });
    } catch (e) {
      setState(() {
        _status = 'Error playing audio: $e';
      });
    }
  }

  /// Share OGG file
  Future<void> _shareOggFile() async {
    if (_outputOggFile == null || !await File(_outputOggFile!).exists()) {
      setState(() {
        _status = 'No file to share';
      });
      return;
    }

    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(_outputOggFile!)],
          subject: 'WAV -> OGG Conversion Result',
          text: 'Conversion Output: ${_outputOggFile!.split('/').last}',
        ),
      );
      setState(() {
        _status = 'Sharing file...';
      });
    } catch (e) {
      setState(() {
        _status = 'Failed to share file: $e';
      });
    }
  }

  /// Select WAV file (for streaming conversion)
  Future<void> _selectWavFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav'],
        allowMultiple: false,
      );

      if (result != null) {
        final file = result.files.single;
        setState(() {
          if (kIsWeb) {
            // On web, use bytes instead of path
            if (file.bytes != null) {
              _selectedWavFile = null;
              _selectedWavFileName = file.name;
              _status = 'File selected: ${file.name}';
            }
          } else {
            // On native platforms, use path
            if (file.path != null) {
              _selectedWavFile = file.path!;
              _selectedWavFileName = file.name;
              _status = 'File selected: ${file.name}';
            }
          }
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error selecting file: $e';
      });
    }
  }

  /// Convert WAV file to OGG using streaming encoder
  Future<void> _convertWavToOggStreaming() async {
    if (!_isPluginReady) {
      setState(() {
        _status =
            'Plugin not ready, please wait for initialization to complete';
      });
      return;
    }

    // If no file is selected, use the default example file from assets
    String? wavFilePath = _selectedWavFile;

    if (wavFilePath == null || !await File(wavFilePath).exists()) {
      // Use the default asset file
      const defaultAssetPath = 'assets/$wavFilename';

      if (kIsWeb) {
        setState(() {
          _status = 'Please select a WAV file first on Web platform';
        });
        return;
      }

      // For non-web platforms, copy the asset file to a temporary directory
      try {
        setState(() {
          _status = 'Loading default WAV file...';
        });

        // Read asset file
        final byteData = await rootBundle.load(defaultAssetPath);
        final bytes = byteData.buffer.asUint8List();

        // Get temporary directory
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/$wavFilename');

        // Write to temporary file
        await tempFile.writeAsBytes(bytes);
        wavFilePath = tempFile.path;

        setState(() {
          _status = 'Default WAV file loaded: $wavFilename';
        });
      } catch (e) {
        setState(() {
          _status =
              'Failed to load default file: $e\nPlease select a WAV file first';
        });
        return;
      }
    }

    final wavFile = File(wavFilePath);
    if (!await wavFile.exists()) {
      setState(() {
        _status = 'WAV file does not exist: $wavFilePath';
      });
      return;
    }

    setState(() {
      _isStreamingConverting = true;
      _streamingProgress = 0.0;
      _status = 'Reading WAV file...';
      _outputOggFile = null;
    });

    try {
      // Get output directory
      final outputDir = kIsWeb
          ? null
          : (Platform.isAndroid || Platform.isIOS
                ? await getApplicationDocumentsDirectory()
                : await getDownloadsDirectory() ?? Directory.current);
      final outputPath = outputDir != null
          ? '${outputDir.path}/output_${DateTime.now().millisecondsSinceEpoch}.ogg'
          : 'output_${DateTime.now().millisecondsSinceEpoch}.ogg';

      final wavReader = WavReader(wavFile);
      await wavReader.open();

      try {
        // Read WAV header information
        final wavInfo = await wavReader.readHeader();
        final fileSizeMB = (await wavFile.length() / 1024 / 1024);
        final duration =
            wavInfo.dataSize /
            (wavInfo.sampleRate * wavInfo.channels * wavInfo.bitsPerSample / 8);

        setState(() {
          _status =
              'File info: ${fileSizeMB.toStringAsFixed(2)} MB, ${duration.toStringAsFixed(1)}s\n'
              'Sample rate: ${wavInfo.sampleRate}Hz, Channels: ${wavInfo.channels}, Bit depth: ${wavInfo.bitsPerSample}bit\n'
              'Initializing encoder...';
        });

        // Initialize streaming encoder
        final encoder = PcmToOgg();
        await encoder.initializeStreamingEncoder(
          channels: wavInfo.channels,
          sampleRate: wavInfo.sampleRate,
          quality: 0.4,
        );

        // Open output file
        final outputFile = File(outputPath);
        final outputSink = outputFile.openWrite();

        try {
          const chunkSizeBytes = 65536; // 64KB chunk size
          int offset = 0;
          final stopwatch = Stopwatch()..start();

          setState(() {
            _status = 'Starting streaming conversion...';
          });

          while (offset < wavInfo.dataSize) {
            final remaining = wavInfo.dataSize - offset;
            final readSize = remaining > chunkSizeBytes
                ? chunkSizeBytes
                : remaining;

            // Read PCM data chunk
            final pcmChunk = await wavReader.readPcmChunk(offset, readSize);
            offset += readSize;

            // Encode data chunk
            final oggChunk = await encoder.encodeChunk(pcmChunk);

            if (oggChunk != null && oggChunk.isNotEmpty) {
              outputSink.add(oggChunk);
            }

            // Update progress
            final progress = offset / wavInfo.dataSize;
            if (mounted) {
              setState(() {
                _streamingProgress = progress;
                _status =
                    'Converting: ${(progress * 100).toStringAsFixed(1)}% (${(offset / 1024 / 1024).toStringAsFixed(2)}/${(wavInfo.dataSize / 1024 / 1024).toStringAsFixed(2)} MB)';
              });
            }
          }

          // Finish encoding
          final finalChunk = await encoder.finish();
          if (finalChunk.isNotEmpty) {
            outputSink.add(finalChunk);
          }

          stopwatch.stop();
          await outputSink.close();

          final outputFileSize = await outputFile.length();
          final compressionRatio = wavInfo.dataSize / outputFileSize;
          final speedMBps =
              wavInfo.dataSize /
              1024 /
              1024 /
              (stopwatch.elapsedMilliseconds / 1000);

          if (mounted) {
            setState(() {
              _isStreamingConverting = false;
              _streamingProgress = 1.0;
              _outputOggFile = outputFile.path;
              _status =
                  '✅ Conversion completed!\n'
                  'Input: ${fileSizeMB.toStringAsFixed(2)} MB\n'
                  'Output: ${(outputFileSize / 1024 / 1024).toStringAsFixed(2)} MB\n'
                  'Compression ratio: ${compressionRatio.toStringAsFixed(2)}:1\n'
                  'Time elapsed: ${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s\n'
                  'Speed: ${speedMBps.toStringAsFixed(2)} MB/s\n'
                  'Saved to: ${outputFile.path}';
            });
          }
        } catch (e) {
          await outputSink.close();
          if (await outputFile.exists()) {
            await outputFile.delete();
          }
          rethrow;
        } finally {
          await encoder.dispose();
        }
      } finally {
        await wavReader.close();
      }
    } catch (e, stackTrace) {
      if (mounted) {
        setState(() {
          _isStreamingConverting = false;
          _streamingProgress = 0.0;
          _status = '❌ Conversion failed: $e';
        });
      }
      debugPrint('Stack trace: $stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('PCM to OGG Plugin Example')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_initError.isNotEmpty)
                  Text(_initError, style: const TextStyle(color: Colors.red)),
                if (_isInitializing) const CircularProgressIndicator(),
                const SizedBox(height: 8),
                Text(_status, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                // Original conversion buttons (small file test)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _isPluginReady ? _runConversion : null,
                      child: const Text('Convert Test Data'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isPluginReady && _oggData != null
                          ? _playOggData
                          : null,
                      child: const Text('Play Audio'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 20),
                // Large file streaming conversion section
                const Text(
                  'Large File Streaming Conversion (WAV → OGG)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    _selectedWavFileName != null || _selectedWavFile != null
                        ? 'Selected: ${_selectedWavFileName ?? _selectedWavFile!.split('/').last}'
                        : 'Default file: $wavFilename (assets)',
                    style: TextStyle(
                      fontSize: 12,
                      color: _selectedWavFile != null
                          ? Colors.blue
                          : Colors.grey,
                    ),
                  ),
                ),
                if (_isStreamingConverting) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _streamingProgress),
                  const SizedBox(height: 8),
                  Text(
                    '${(_streamingProgress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isPluginReady && !_isStreamingConverting
                          ? _selectWavFile
                          : null,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Select WAV'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _isPluginReady && !_isStreamingConverting
                          ? _convertWavToOggStreaming
                          : null,
                      icon: const Icon(Icons.transform),
                      label: Text(
                        _selectedWavFile != null
                            ? 'Convert to OGG'
                            : 'Convert Asset',
                      ),
                    ),
                  ],
                ),
                if (_outputOggFile != null) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Output file: ${_outputOggFile!.split('/').last}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _shareOggFile,
                    icon: const Icon(Icons.share),
                    label: const Text('Share OGG File'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
