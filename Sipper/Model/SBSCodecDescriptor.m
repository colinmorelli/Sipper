//
//  SBSCodecDescriptor.m
//  Sipper
//
//  Created by Colin Morelli on 4/24/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSCodecDescriptor.h"

@implementation SBSCodecDescriptor

//------------------------------------------------------------------------------

- (instancetype)initWithEncoding:(NSString *)encoding {
  return [self initWithEncoding:encoding samplingRate:0];
}

//------------------------------------------------------------------------------

- (instancetype)initWithEncoding:(NSString *)encoding samplingRate:(NSUInteger)samplingRate {
  return [self initWithEncoding:encoding samplingRate:samplingRate numberOfChannels:0];
}

//------------------------------------------------------------------------------

- (instancetype)initWithEncoding:(NSString *)encoding samplingRate:(NSUInteger)samplingRate numberOfChannels:(NSUInteger)numberOfChannels {
  if (self = [super init]) {
    _encoding = encoding;
    _samplingRate = samplingRate;
    _numberOfChannels = numberOfChannels;
  }
  
  return self;
}

//------------------------------------------------------------------------------

- (NSString *)description {
  NSString *description = _encoding;
  
  if (_samplingRate > 0) {
    description = [description stringByAppendingString:[NSString stringWithFormat:@"/%d", (int) _samplingRate]];
  }
  
  if (_numberOfChannels > 0) {
    description = [description stringByAppendingString:[NSString stringWithFormat:@"/%d", (int) _numberOfChannels]];
  }
  
  return description;
}

@end
