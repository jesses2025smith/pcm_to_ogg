#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "pcm_to_ogg.h"

// If compiling for the web with Emscripten, include its header
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

// Define the export macro.
// For native platforms, it ensures the symbol is visible.
// For Emscripten, it ensures the function isn't optimized away and is exported.
#ifdef __EMSCRIPTEN__
    #define EXPORT EMSCRIPTEN_KEEPALIVE
#else
    #define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif


// The main encoding function that will be exposed to Dart.
// It takes raw PCM data (as 32-bit floats), number of samples,
// channels, sample rate, and a quality setting.
EXPORT
void* encode_pcm_to_ogg(
    float* pcm_data,
    long num_samples, // Total number of samples (e.g., for stereo, 2 samples = 1 frame)
    int channels,
    long sample_rate,
    float quality // from 0.0 (worst) to 1.0 (best)
) {
    ogg_stream_state os; // state of the ogg stream
    ogg_page         og; // a page of ogg data
    ogg_packet       op; // a packet of ogg data
    vorbis_info      vi; // struct that stores all the static vorbis bitstream settings
    vorbis_comment   vc; // struct that stores all the user comments
    vorbis_dsp_state vd; // central working state for the packet->PCM decoder
    vorbis_block     vb; // local working space for packet->PCM decode

    int eos = 0;
    int ret;

    vorbis_info_init(&vi);
    
    ret = vorbis_encode_init_vbr(&vi, channels, sample_rate, quality);
    if (ret) {
        return NULL; // Failed to initialize encoder
    }

    vorbis_analysis_init(&vd, &vi);
    vorbis_block_init(&vd, &vb);

    srand(time(NULL));
    ogg_stream_init(&os, rand());

    vorbis_comment_init(&vc);
    vorbis_comment_add_tag(&vc, "ENCODER", "pcm_to_ogg_plugin");

    ogg_packet header, header_comm, header_code;
    vorbis_analysis_headerout(&vd, &vc, &header, &header_comm, &header_code);
    ogg_stream_packetin(&os, &header);
    ogg_stream_packetin(&os, &header_comm);
    ogg_stream_packetin(&os, &header_code);

    unsigned char* output_buffer = NULL;
    size_t output_size = 0;

    while(ogg_stream_flush(&os, &og)){
        size_t new_size = output_size + og.header_len + og.body_len;
        output_buffer = realloc(output_buffer, new_size);
        memcpy(output_buffer + output_size, og.header, og.header_len);
        memcpy(output_buffer + output_size + og.header_len, og.body, og.body_len);
        output_size = new_size;
    }

    long i = 0;
    long read_size = 1024;

    while (i < num_samples) {
        long current_num_samples_remaining = num_samples - i;
        long samples_to_process = current_num_samples_remaining / channels;

        if (samples_to_process == 0 && current_num_samples_remaining > 0) {
            // If remaining samples are less than channels, process them all
            samples_to_process = 1;
        }

        if (samples_to_process > read_size) {
            samples_to_process = read_size;
        }

        if (samples_to_process <= 0) {
            break;
        }

        float** buffer = vorbis_analysis_buffer(&vd, samples_to_process);

        for (int c = 0; c < channels; c++) {
            // Assuming interleaved PCM data
            for (int j = 0; j < samples_to_process; j++) {
                buffer[c][j] = pcm_data[i + j * channels + c];
            }
        }
        long samples_processed_in_p_buf = samples_to_process * channels;
        i += samples_processed_in_p_buf;

        vorbis_analysis_wrote(&vd, samples_to_process);

        while (vorbis_analysis_blockout(&vd, &vb) == 1) {
            vorbis_analysis(&vb, NULL);
            vorbis_bitrate_addblock(&vb);
            while (vorbis_bitrate_flushpacket(&vd, &op)) {
                ogg_stream_packetin(&os, &op);
                while (!eos) {
                    int result = ogg_stream_pageout(&os, &og);
                    if (result == 0) break;
                    size_t new_size = output_size + og.header_len + og.body_len;
                    output_buffer = realloc(output_buffer, new_size);
                    memcpy(output_buffer + output_size, og.header, og.header_len);
                    memcpy(output_buffer + output_size + og.header_len, og.body, og.body_len);
                    output_size = new_size;
                    if (ogg_page_eos(&og)) eos = 1;
                }
            }
        }
    }

    vorbis_analysis_wrote(&vd, 0);

    while (vorbis_analysis_blockout(&vd, &vb) == 1) {
        vorbis_analysis(&vb, NULL);
        vorbis_bitrate_addblock(&vb);
        while (vorbis_bitrate_flushpacket(&vd, &op)) {
            ogg_stream_packetin(&os, &op);
            while (!eos) {
                int result = ogg_stream_pageout(&os, &og);
                if (result == 0) break;
                size_t new_size = output_size + og.header_len + og.body_len;
                output_buffer = realloc(output_buffer, new_size);
                memcpy(output_buffer + output_size, og.header, og.header_len);
                memcpy(output_buffer + output_size + og.header_len, og.body, og.body_len);
                output_size = new_size;
                if (ogg_page_eos(&og)) eos = 1;
            }
        }
    }

    ogg_stream_clear(&os);
    vorbis_block_clear(&vb);
    vorbis_dsp_clear(&vd);
    vorbis_comment_clear(&vc);
    vorbis_info_clear(&vi);

    OggOutput* output = malloc(sizeof(OggOutput));
    output->data = output_buffer;
    output->size = (int)output_size;

    return output;
}

EXPORT
unsigned char* get_ogg_output_data(OggOutput* output) {
    return output->data;
}

EXPORT
int get_ogg_output_size(OggOutput* output) {
    return output->size;
}

// We need a function to free the memory we allocated for the output.
// This will be called from Dart.
EXPORT
void free_ogg_output(OggOutput* output) {
    if (output != NULL) {
        if (output->data != NULL) {
            free(output->data);
        }
        free(output);
    }
}

// ============================================================================
// Streaming encoding functions
// ============================================================================

// Create an encoder context for streaming encoding
EXPORT
OggEncoderContext* create_ogg_encoder(int channels, long sample_rate, float quality) {
    OggEncoderContext* ctx = malloc(sizeof(OggEncoderContext));
    if (!ctx) return NULL;

    vorbis_info_init(&ctx->vi);
    if (vorbis_encode_init_vbr(&ctx->vi, channels, sample_rate, quality)) {
        free(ctx);
        return NULL;
    }

    vorbis_analysis_init(&ctx->vd, &ctx->vi);
    vorbis_block_init(&ctx->vd, &ctx->vb);
    
    srand(time(NULL));
    ogg_stream_init(&ctx->os, rand());

    vorbis_comment_init(&ctx->vc);
    vorbis_comment_add_tag(&ctx->vc, "ENCODER", "pcm_to_ogg_plugin");

    ctx->header_written = 0;
    ctx->eos = 0;

    return ctx;
}

// Get header data (called once at the beginning)
static OggOutput* get_header(OggEncoderContext* ctx) {
    if (!ctx || ctx->header_written) {
        OggOutput* output = malloc(sizeof(OggOutput));
        if (output) {
            output->data = NULL;
            output->size = 0;
        }
        return output;
    }

    ogg_page og;
    ogg_packet header, header_comm, header_code;
    vorbis_analysis_headerout(&ctx->vd, &ctx->vc, &header, &header_comm, &header_code);
    ogg_stream_packetin(&ctx->os, &header);
    ogg_stream_packetin(&ctx->os, &header_comm);
    ogg_stream_packetin(&ctx->os, &header_code);

    unsigned char* output_buffer = NULL;
    size_t output_size = 0;

    while(ogg_stream_flush(&ctx->os, &og)){
        size_t new_size = output_size + og.header_len + og.body_len;
        unsigned char* temp = realloc(output_buffer, new_size);
        if (!temp) {
            if (output_buffer) free(output_buffer);
            return NULL;
        }
        output_buffer = temp;
        memcpy(output_buffer + output_size, og.header, og.header_len);
        memcpy(output_buffer + output_size + og.header_len, og.body, og.body_len);
        output_size = new_size;
    }

    ctx->header_written = 1;

    OggOutput* output = malloc(sizeof(OggOutput));
    if (!output) {
        if (output_buffer) free(output_buffer);
        return NULL;
    }
    output->data = output_buffer;
    output->size = (int)output_size;
    return output;
}

// Encode a chunk of PCM data
EXPORT
OggOutput* encode_pcm_chunk(OggEncoderContext* ctx, float* pcm_data, long num_samples) {
    if (!ctx) return NULL;

    // If header hasn't been written, return it first
    if (!ctx->header_written) {
        return get_header(ctx);
    }

    int channels = ctx->vi.channels;
    unsigned char* output_buffer = NULL;
    size_t output_size = 0;
    ogg_page og;
    ogg_packet op;

    long i = 0;
    long read_size = 1024;

    while (i < num_samples) {
        long remaining = num_samples - i;
        long samples_to_process = remaining / channels;
        
        if (samples_to_process == 0 && remaining > 0) {
            samples_to_process = 1;
        }
        if (samples_to_process > read_size) {
            samples_to_process = read_size;
        }
        if (samples_to_process <= 0) break;

        float** buffer = vorbis_analysis_buffer(&ctx->vd, samples_to_process);

        for (int c = 0; c < channels; c++) {
            for (int j = 0; j < samples_to_process; j++) {
                buffer[c][j] = pcm_data[i + j * channels + c];
            }
        }

        i += samples_to_process * channels;
        vorbis_analysis_wrote(&ctx->vd, samples_to_process);

        while (vorbis_analysis_blockout(&ctx->vd, &ctx->vb) == 1) {
            vorbis_analysis(&ctx->vb, NULL);
            vorbis_bitrate_addblock(&ctx->vb);
            while (vorbis_bitrate_flushpacket(&ctx->vd, &op)) {
                ogg_stream_packetin(&ctx->os, &op);
                while (!ctx->eos) {
                    int result = ogg_stream_pageout(&ctx->os, &og);
                    if (result == 0) break;
                    size_t new_size = output_size + og.header_len + og.body_len;
                    unsigned char* temp = realloc(output_buffer, new_size);
                    if (!temp) {
                        if (output_buffer) free(output_buffer);
                        return NULL;
                    }
                    output_buffer = temp;
                    memcpy(output_buffer + output_size, og.header, og.header_len);
                    memcpy(output_buffer + output_size + og.header_len, og.body, og.body_len);
                    output_size = new_size;
                    if (ogg_page_eos(&og)) ctx->eos = 1;
                }
            }
        }
    }

    OggOutput* output = malloc(sizeof(OggOutput));
    if (!output) {
        if (output_buffer) free(output_buffer);
        return NULL;
    }
    output->data = output_buffer;
    output->size = (int)output_size;
    return output;
}

// Finish encoding (flush remaining data)
EXPORT
OggOutput* finish_encoding(OggEncoderContext* ctx) {
    if (!ctx) return NULL;

    // If header hasn't been written, return it
    if (!ctx->header_written) {
        return get_header(ctx);
    }

    unsigned char* output_buffer = NULL;
    size_t output_size = 0;
    ogg_page og;
    ogg_packet op;

    vorbis_analysis_wrote(&ctx->vd, 0);

    while (vorbis_analysis_blockout(&ctx->vd, &ctx->vb) == 1) {
        vorbis_analysis(&ctx->vb, NULL);
        vorbis_bitrate_addblock(&ctx->vb);
        while (vorbis_bitrate_flushpacket(&ctx->vd, &op)) {
            ogg_stream_packetin(&ctx->os, &op);
            while (!ctx->eos) {
                int result = ogg_stream_pageout(&ctx->os, &og);
                if (result == 0) break;
                size_t new_size = output_size + og.header_len + og.body_len;
                unsigned char* temp = realloc(output_buffer, new_size);
                if (!temp) {
                    if (output_buffer) free(output_buffer);
                    return NULL;
                }
                output_buffer = temp;
                memcpy(output_buffer + output_size, og.header, og.header_len);
                memcpy(output_buffer + output_size + og.header_len, og.body, og.body_len);
                output_size = new_size;
                if (ogg_page_eos(&og)) ctx->eos = 1;
            }
        }
    }

    // Flush the stream
    while (!ctx->eos && ogg_stream_flush(&ctx->os, &og)) {
        size_t new_size = output_size + og.header_len + og.body_len;
        unsigned char* temp = realloc(output_buffer, new_size);
        if (!temp) {
            if (output_buffer) free(output_buffer);
            return NULL;
        }
        output_buffer = temp;
        memcpy(output_buffer + output_size, og.header, og.header_len);
        memcpy(output_buffer + output_size + og.header_len, og.body, og.body_len);
        output_size = new_size;
        if (ogg_page_eos(&og)) ctx->eos = 1;
    }

    OggOutput* output = malloc(sizeof(OggOutput));
    if (!output) {
        if (output_buffer) free(output_buffer);
        return NULL;
    }
    output->data = output_buffer;
    output->size = (int)output_size;
    return output;
}

// Destroy encoder context
EXPORT
void destroy_ogg_encoder(OggEncoderContext* ctx) {
    if (!ctx) return;

    ogg_stream_clear(&ctx->os);
    vorbis_block_clear(&ctx->vb);
    vorbis_dsp_clear(&ctx->vd);
    vorbis_comment_clear(&ctx->vc);
    vorbis_info_clear(&ctx->vi);
    free(ctx);
}

// Android JNI implementations are in pcm_to_ogg_android.c