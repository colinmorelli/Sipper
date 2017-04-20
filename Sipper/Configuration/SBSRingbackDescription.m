//
//  SBSRingbackDescription.m
//  Sipper
//
//  Created by Colin Morelli on 4/19/17.
//  Copyright © 2017 Sipper. All rights reserved.
//

#import "SBSRingbackDescription.h"

@implementation SBSRingbackTone

- (instancetype)initWithFirstFrequency:(NSUInteger)firstFrequency secondFrequency:(NSUInteger)secondFrequency
                                  onMs:(NSUInteger)onMs offMs:(NSUInteger)offMs {
  if (self = [super init]) {
    _firstFrequency = firstFrequency;
    _secondFrequency = secondFrequency;
    _onMs = onMs;
    _offMs = offMs;
  }
  
  return self;
}

@end

@implementation SBSRingbackDescription

+ (SBSRingbackDescription *)usRingback {
  SBSRingbackDescription *ringbackDescription = [[SBSRingbackDescription alloc] init];
  ringbackDescription.intervalMs = 4000;
  ringbackDescription.tones = @[[[SBSRingbackTone alloc] initWithFirstFrequency:440 secondFrequency:480 onMs:2000 offMs:4000]];
  return ringbackDescription;
}

@end
