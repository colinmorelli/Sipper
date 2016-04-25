//
//  SBSCodecDescriptor.h
//  Sipper
//
//  Created by Colin Morelli on 4/24/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SBSCodecDescriptor : NSObject

/**
 * The codec's encoding type (for example, G722, PCMU, etc)
 */
@property (strong, nonatomic, nonnull, readonly) NSString *encoding;

/**
 * The sampling rate of the codec
 */
@property (nonatomic, readonly) NSUInteger samplingRate;

/**
 * The number of channels that this codec has
 */
@property (nonatomic, readonly) NSUInteger numberOfChannels;

/**
 * Creates a new fully qualified codec descriptor
 *
 * @param encoding         the name of the encoding type
 * @param samplingRate     the sampling rate for the codec
 * @param numberOfChannels the number of channels this codec must match
 */
- (instancetype _Nonnull)initWithEncoding:(NSString * _Nonnull)encoding samplingRate:(NSUInteger)samplingRate numberOfChannels:(NSUInteger)numberOfChannels;

/**
 * Creates a partially qualified codec descriptor
 *
 * This codec descriptor will match any codecs with the requested encoding and sampling rate, regardless
 * of the number of audio channels they have
 *
 * @param encoding         the name of the encoding type
 * @param samplingRate     the sampling rate for the codec
 */
- (instancetype _Nonnull)initWithEncoding:(NSString * _Nonnull)encoding samplingRate:(NSUInteger)samplingRate;

/**
 * Creates a partially qualified codec descriptor
 *
 * This codec descriptor will match any codecs with the requested encoding, regardless of the sampling rate or
 * the number of audio channels they have
 *
 * @param encoding         the name of the encoding type
 */
- (instancetype _Nonnull)initWithEncoding:(NSString * _Nonnull)encoding;

@end
