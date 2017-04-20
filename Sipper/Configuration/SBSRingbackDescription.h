//
//  SBSRingbackDescription.h
//  Sipper
//
//  Created by Colin Morelli on 4/19/17.
//  Copyright © 2017 Sipper. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SBSRingbackTone : NSObject

@property (nonatomic) NSUInteger firstFrequency;
@property (nonatomic) NSUInteger secondFrequency;
@property (nonatomic) NSUInteger onMs;
@property (nonatomic) NSUInteger offMs;

- (instancetype)initWithFirstFrequency:(NSUInteger)firstFrequency secondFrequency:(NSUInteger)secondFrequency
                                  onMs:(NSUInteger)onMs offMs:(NSUInteger)offMs;

@end

@interface SBSRingbackDescription : NSObject

/**
 * Array of tones that should be played for this ringback description
 */
@property (strong, nonatomic) NSArray<SBSRingbackTone *> *tones;

/**
 * Interval between ringback tones
 *
 * The value specified here will override the offMs of the last tone in
 * the tones array
 */
@property (nonatomic) NSUInteger intervalMs;

/**
 * Creates a predefined ringback description for a US handset
 */
+ (SBSRingbackDescription *)usRingback;

@end
