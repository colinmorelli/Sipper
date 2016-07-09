//
//  SBSBlockEventListener+Internal.m
//  Sipper
//
//  Created by Colin Morelli on 7/6/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSBlockEventListener+Internal.h"

@interface SBSBlockEventListener ()

@property (nonatomic, copy, nonnull) void (^block)(SBSEvent *);

@end

@implementation SBSBlockEventListener

- (instancetype)initWithBlock:(void (^)(SBSEvent *))block {
  if (self = [super init]) {
    _block = block;
  }
  
  return self;
}

- (BOOL)dispatchEvent:(SBSEvent *)event {
  _block(event);
  return YES;
}

+ (SBSBlockEventListener *)listenerWithBlock:(void (^)(SBSEvent *))block {
  return [[SBSBlockEventListener alloc] initWithBlock:block];
}

@end

@implementation SBSEventDispatcher (SBSBlockEventListener)

- (SBSEventBinding *)addListenerWithBlock:(void (^)(SBSEvent *))block eventName:(NSString *)name {
  return [self addEventListener:[SBSBlockEventListener listenerWithBlock:block] forEvent:name];
}

@end
