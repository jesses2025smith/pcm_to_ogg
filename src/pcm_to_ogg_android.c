#ifdef ANDROID

#include <jni.h>
#include "pcm_to_ogg.h"

// JNI wrapper for encode_pcm_to_ogg
JNIEXPORT jlong JNICALL
Java_com_github_pcm_1to_1ogg_PcmToOggPlugin_encodePcmToOgg(
    JNIEnv* env,
    jclass clazz,
    jobject pcmData,
    jlong numSamples,
    jint channels,
    jlong sampleRate,
    jfloat quality) {

    float* pcm_data_ptr = (float*)(*env)->GetDirectBufferAddress(env, pcmData);
    if (pcm_data_ptr == NULL) {
        return 0; // Failed to get direct buffer address
    }

    void* output_ptr = encode_pcm_to_ogg(
        pcm_data_ptr,
        (long)numSamples,
        (int)channels,
        (long)sampleRate,
        (float)quality
    );

    return (jlong)output_ptr;
}

// JNI wrapper for get_ogg_output_data
JNIEXPORT jobject JNICALL
Java_com_github_pcm_1to_1ogg_PcmToOggPlugin_getOggOutputData(
    JNIEnv* env,
    jclass clazz,
    jlong oggOutputPointer) {

    OggOutput* output = (OggOutput*)oggOutputPointer;
    if (output == NULL || output->data == NULL) {
        return NULL;
    }
    return (*env)->NewDirectByteBuffer(env, output->data, output->size);
}

// JNI wrapper for get_ogg_output_size
JNIEXPORT jint JNICALL
Java_com_github_pcm_1to_1ogg_PcmToOggPlugin_getOggOutputSize(
    JNIEnv* env,
    jclass clazz,
    jlong oggOutputPointer) {

    OggOutput* output = (OggOutput*)oggOutputPointer;
    if (output == NULL) {
        return 0;
    }
    return (jint)get_ogg_output_size(output);
}

// JNI wrapper for free_ogg_output
JNIEXPORT void JNICALL
Java_com_github_pcm_1to_1ogg_PcmToOggPlugin_freeOggOutput(
    JNIEnv* env,
    jclass clazz,
    jlong oggOutputPointer) {

    OggOutput* output = (OggOutput*)oggOutputPointer;
    free_ogg_output(output);
}

// JNI wrapper for create_ogg_encoder
JNIEXPORT jlong JNICALL
Java_com_github_pcm_1to_1ogg_PcmToOggPlugin_createOggEncoder(
    JNIEnv* env,
    jclass clazz,
    jint channels,
    jlong sampleRate,
    jfloat quality) {

    OggEncoderContext* ctx = create_ogg_encoder(
        (int)channels,
        (long)sampleRate,
        (float)quality
    );

    return (jlong)ctx;
}

// JNI wrapper for encode_pcm_chunk
JNIEXPORT jlong JNICALL
Java_com_github_pcm_1to_1ogg_PcmToOggPlugin_encodePcmChunk(
    JNIEnv* env,
    jclass clazz,
    jlong encoderContext,
    jobject pcmData,
    jlong numSamples) {

    OggEncoderContext* ctx = (OggEncoderContext*)encoderContext;
    if (ctx == NULL) {
        return 0;
    }

    float* pcm_data_ptr = (float*)(*env)->GetDirectBufferAddress(env, pcmData);
    if (pcm_data_ptr == NULL) {
        return 0; // Failed to get direct buffer address
    }

    OggOutput* output = encode_pcm_chunk(
        ctx,
        pcm_data_ptr,
        (long)numSamples
    );

    return (jlong)output;
}

// JNI wrapper for finish_encoding
JNIEXPORT jlong JNICALL
Java_com_github_pcm_1to_1ogg_PcmToOggPlugin_finishEncoding(
    JNIEnv* env,
    jclass clazz,
    jlong encoderContext) {

    OggEncoderContext* ctx = (OggEncoderContext*)encoderContext;
    if (ctx == NULL) {
        return 0;
    }

    OggOutput* output = finish_encoding(ctx);
    return (jlong)output;
}

// JNI wrapper for destroy_ogg_encoder
JNIEXPORT void JNICALL
Java_com_github_pcm_1to_1ogg_PcmToOggPlugin_destroyOggEncoder(
    JNIEnv* env,
    jclass clazz,
    jlong encoderContext) {

    OggEncoderContext* ctx = (OggEncoderContext*)encoderContext;
    destroy_ogg_encoder(ctx);
}

#endif // ANDROID

