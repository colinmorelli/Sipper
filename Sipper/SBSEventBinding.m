//
//  SBSEventBinding.m
//  Sipper
//
//  Created by Colin Morelli on 6/3/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSEventBinding.h"

@implementation SBSEventBinding

- (instancetype)initWithListener:(id<SBSEventListener>)listener eventName:(NSString *)name {
  if (self = [super init]) {
    _listener = listener;
    _eventName = name;
  }
  
  return self;
}

+ (SBSEventBinding *)bindingWithListener:(id<SBSEventListener>)listener eventName:(NSString *)name {
  return [[self alloc] initWithListener:listener eventName:name];
}

@end
