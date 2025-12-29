package com.github.pcm_to_ogg

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** PcmToOggPlugin */
class PcmToOggPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel

    companion object {
        init {
            System.loadLibrary("pcm_to_ogg")
        }

        @JvmStatic
        private external fun encodePcmToOgg(
            pcmData: ByteBuffer,
            numSamples: Long,
            channels: Int,
            sampleRate: Long,
            quality: Float
        ): Long // Returns a pointer to OggOutput struct

        @JvmStatic
        private external fun getOggOutputData(oggOutputPointer: Long): ByteBuffer

        @JvmStatic
        private external fun getOggOutputSize(oggOutputPointer: Long): Int

        @JvmStatic
        private external fun freeOggOutput(oggOutputPointer: Long)

        // Streaming encoding functions
        @JvmStatic
        private external fun createOggEncoder(
            channels: Int,
            sampleRate: Long,
            quality: Float
        ): Long // Returns a pointer to OggEncoderContext

        @JvmStatic
        private external fun encodePcmChunk(
            encoderContext: Long,
            pcmData: ByteBuffer,
            numSamples: Long
        ): Long // Returns a pointer to OggOutput struct

        @JvmStatic
        private external fun finishEncoding(
            encoderContext: Long
        ): Long // Returns a pointer to OggOutput struct

        @JvmStatic
        private external fun destroyOggEncoder(encoderContext: Long)
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "pcm_to_ogg")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "initialize" -> {
                result.success(null)
            }
            "convert" -> {
                val pcmFloatArray = call.argument<FloatArray>("pcmData")
                val channels = call.argument<Int>("channels")
                val sampleRate = call.argument<Int>("sampleRate")
                val quality = call.argument<Double>("quality")?.toFloat()

                if (pcmFloatArray == null || channels == null || sampleRate == null || quality == null) {
                    result.error("INVALID_ARGUMENTS", "Missing arguments for convert method", null)
                    return
                }

                // Allocate a direct ByteBuffer and copy the float array data into it.
                val pcmByteBuffer = ByteBuffer.allocateDirect(pcmFloatArray.size * 4) // 4 bytes per float
                pcmByteBuffer.order(ByteOrder.nativeOrder())
                pcmByteBuffer.asFloatBuffer().put(pcmFloatArray)

                val numSamples = pcmFloatArray.size.toLong()

                val oggOutputPointer = encodePcmToOgg(
                    pcmByteBuffer,
                    numSamples,
                    channels,
                    sampleRate.toLong(),
                    quality
                )

                if (oggOutputPointer != 0L) {
                    val oggDataBuffer = getOggOutputData(oggOutputPointer)
                    val oggDataSize = getOggOutputSize(oggOutputPointer)

                    val oggBytes = ByteArray(oggDataSize)
                    oggDataBuffer.get(oggBytes)

                    freeOggOutput(oggOutputPointer) // Free native memory
                    result.success(oggBytes)
                } else {
                    result.error("CONVERSION_FAILED", "Failed to convert PCM to OGG", null)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
