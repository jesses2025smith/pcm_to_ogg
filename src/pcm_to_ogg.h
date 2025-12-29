#ifndef PCM_TO_OGG_H
#define PCM_TO_OGG_H

#include "ogg/ogg.h"
#include "vorbis/vorbisenc.h"

#ifdef __cplusplus
extern "C" {
#endif

// Define a structure to hold our output data, which will be returned to Dart.
typedef struct {
    unsigned char* data;
    int size;
} OggOutput;

// Encoding context structure for streaming encoding
typedef struct {
    ogg_stream_state os;
    vorbis_info vi;
    vorbis_comment vc;
    vorbis_dsp_state vd;
    vorbis_block vb;
    int header_written;
    int eos;
} OggEncoderContext;

// Main encoding function
void* encode_pcm_to_ogg(
    float* pcm_data,
    long num_samples,
    int channels,
    long sample_rate,
    float quality
);

// Helper functions to access OggOutput
unsigned char* get_ogg_output_data(OggOutput* output);
int get_ogg_output_size(OggOutput* output);
void free_ogg_output(OggOutput* output);

// Streaming encoding functions
OggEncoderContext* create_ogg_encoder(int channels, long sample_rate, float quality);
OggOutput* encode_pcm_chunk(OggEncoderContext* ctx, float* pcm_data, long num_samples);
OggOutput* finish_encoding(OggEncoderContext* ctx);
void destroy_ogg_encoder(OggEncoderContext* ctx);

#ifdef __cplusplus
}
#endif

#endif // PCM_TO_OGG_H
