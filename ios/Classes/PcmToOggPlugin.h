//
//  PcmToOggPlugin.h
//  pcm_to_ogg
//
//  Objective-C header to expose C functions to Swift and provide plugin registration
//

#import <Flutter/Flutter.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Objective-C plugin registration class
@interface PcmToOggPlugin : NSObject<FlutterPlugin>

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar;

- (instancetype)initWithChannel:(FlutterMethodChannel *)channel;

@end

// Use void* for opaque C types to avoid exposing C structures to Swift
@interface PcmToOggWrapper : NSObject

+ (nullable void *)createEncoderWithChannels:(int32_t)channels 
                                  sampleRate:(int32_t)sampleRate 
                                      quality:(float)quality NS_SWIFT_NAME(createEncoder(withChannels:sampleRate:quality:));

+ (nullable void *)encodeChunk:(void *)encoder 
                       pcmData:(float *)pcmData 
                    numSamples:(int32_t)numSamples NS_SWIFT_NAME(encodeChunk(_:pcmData:numSamples:));

+ (nullable void *)finishEncoding:(void *)encoder NS_SWIFT_NAME(finishEncoding(_:));

+ (void)destroyEncoder:(void *)encoder NS_SWIFT_NAME(destroyEncoder(_:));

+ (nullable unsigned char *)getOutputData:(void *)output NS_SWIFT_NAME(getOutputData(_:));
+ (int)getOutputSize:(void *)output NS_SWIFT_NAME(getOutputSize(_:));
+ (void)freeOutput:(void *)output NS_SWIFT_NAME(freeOutput(_:));

@end

NS_ASSUME_NONNULL_END


