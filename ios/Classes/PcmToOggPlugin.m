//
//  PcmToOggPlugin.m
//  pcm_to_ogg
//
//  Objective-C wrapper to expose C functions to Swift and provide plugin registration
//

#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>
#import "PcmToOggPlugin.h"
#import "pcm_to_ogg.h"

@implementation PcmToOggPlugin {
    FlutterMethodChannel *_channel;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel *channel = [FlutterMethodChannel
                                     methodChannelWithName:@"pcm_to_ogg"
                                     binaryMessenger:[registrar messenger]];
    PcmToOggPlugin *instance = [[PcmToOggPlugin alloc] initWithChannel:channel];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithChannel:(FlutterMethodChannel *)channel {
    self = [super init];
    if (self) {
        _channel = channel;
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"initialize" isEqualToString:call.method]) {
        // No-op on native, just for platform interface consistency
        result(nil);
    } else if ([@"convert" isEqualToString:call.method]) {
        NSDictionary *args = call.arguments;
        if (!args[@"pcmData"] || !args[@"channels"] || !args[@"sampleRate"] || !args[@"quality"]) {
            result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                                       message:@"Missing or invalid arguments for convert"
                                       details:nil]);
            return;
        }
        
        FlutterStandardTypedData *pcmDataTyped = args[@"pcmData"];
        NSNumber *channelsNum = args[@"channels"];
        NSNumber *sampleRateNum = args[@"sampleRate"];
        NSNumber *qualityNum = args[@"quality"];
        
        NSData *pcmData = pcmDataTyped.data;
        // A Float32 sample is 4 bytes
        int numSamples = (int)(pcmData.length / 4);
        
        // Create encoder context
        void *encoderCtx = [PcmToOggWrapper createEncoderWithChannels:[channelsNum intValue]
                                                            sampleRate:[sampleRateNum intValue]
                                                               quality:[qualityNum floatValue]];
        if (!encoderCtx) {
            result([FlutterError errorWithCode:@"CONVERSION_FAILED"
                                       message:@"Failed to create encoder"
                                       details:nil]);
            return;
        }
        
        // Collect all output chunks
        __block NSMutableData *allOggData = [NSMutableData data];
        __block BOOL encodingFailed = NO;
        
        // Process PCM data - get bytes pointer
        const void *pcmBytes = [pcmData bytes];
        float *pcmFloatPtr = (float *)pcmBytes;
        
        // Encode PCM chunk
        void *oggOutputPtr = [PcmToOggWrapper encodeChunk:encoderCtx
                                                  pcmData:pcmFloatPtr
                                               numSamples:numSamples];
        if (!oggOutputPtr) {
            encodingFailed = YES;
        } else {
            // Get output data
            unsigned char *outputDataPtr = [PcmToOggWrapper getOutputData:oggOutputPtr];
            int outputSize = [PcmToOggWrapper getOutputSize:oggOutputPtr];
            if (outputSize > 0 && outputDataPtr) {
                [allOggData appendBytes:outputDataPtr length:outputSize];
            }
            
            // Free the OggOutput structure
            [PcmToOggWrapper freeOutput:oggOutputPtr];
            
            // Finish encoding to flush remaining data
            void *finalOutputPtr = [PcmToOggWrapper finishEncoding:encoderCtx];
            if (!finalOutputPtr) {
                encodingFailed = YES;
            } else {
                // Append final output data
                unsigned char *finalDataPtr = [PcmToOggWrapper getOutputData:finalOutputPtr];
                int finalSize = [PcmToOggWrapper getOutputSize:finalOutputPtr];
                if (finalSize > 0 && finalDataPtr) {
                    [allOggData appendBytes:finalDataPtr length:finalSize];
                }
                
                // Free the final OggOutput structure
                [PcmToOggWrapper freeOutput:finalOutputPtr];
            }
        }
        
        // Destroy the encoder context
        [PcmToOggWrapper destroyEncoder:encoderCtx];
        
        if (!encodingFailed && allOggData.length > 0) {
            result([FlutterStandardTypedData typedDataWithBytes:allOggData]);
        } else {
            result([FlutterError errorWithCode:@"CONVERSION_FAILED"
                                       message:@"Failed to encode PCM to OGG"
                                       details:nil]);
        }
    } else {
        result(FlutterMethodNotImplemented);
    }
}

@end

@implementation PcmToOggWrapper

+ (void *)createEncoderWithChannels:(int32_t)channels 
                         sampleRate:(int32_t)sampleRate 
                            quality:(float)quality {
    return (void *)create_ogg_encoder((int)channels, (long)sampleRate, quality);
}

+ (void *)encodeChunk:(void *)encoder 
              pcmData:(float *)pcmData 
           numSamples:(int32_t)numSamples {
    OggEncoderContext *ctx = (OggEncoderContext *)encoder;
    OggOutput *output = encode_pcm_chunk(ctx, pcmData, (long)numSamples);
    return (void *)output;
}

+ (void *)finishEncoding:(void *)encoder {
    OggEncoderContext *ctx = (OggEncoderContext *)encoder;
    OggOutput *output = finish_encoding(ctx);
    return (void *)output;
}

+ (void)destroyEncoder:(void *)encoder {
    OggEncoderContext *ctx = (OggEncoderContext *)encoder;
    destroy_ogg_encoder(ctx);
}

+ (unsigned char *)getOutputData:(void *)output {
    OggOutput *out = (OggOutput *)output;
    return get_ogg_output_data(out);
}

+ (int)getOutputSize:(void *)output {
    OggOutput *out = (OggOutput *)output;
    return get_ogg_output_size(out);
}

+ (void)freeOutput:(void *)output {
    OggOutput *out = (OggOutput *)output;
    free_ogg_output(out);
}

@end

