//
//  SBSTargetActionEventListener.m
//  Sipper
//
//  Created by Colin Morelli on 6/3/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSTargetActionEventListener+Internal.h"

@interface SBSTargetActionEventListener ()

@property (weak, nonatomic) id target;
@property (nonatomic, nonnull) SEL action;

@end

@implementation SBSTargetActionEventListener

- (instancetype)initWithTarget:(id)target action:(SEL)action {
  if (self = [super init]) {
    _target = target;
    _action = action;
  }
  
  return self;
}

- (BOOL)dispatchEvent:(SBSEvent *)event {
  if (!_target) {
    return NO;
  }
  
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
  [_target performSelector:_action withObject:event];
#pragma clang diagnostic pop
  
  return YES;
}

+ (SBSTargetActionEventListener *)listenerWithTarget:(id)target action:(SEL)action {
  return [[SBSTargetActionEventListener alloc] initWithTarget:target action:action];
}

@end

@implementation SBSEventDispatcher (SBSTargetActionEventListener)

- (SBSEventBinding *)addListenerWithTarget:(id)target action:(SEL)action eventName:(NSString *)name {
  return [self addEventListener:[SBSTargetActionEventListener listenerWithTarget:target action:action] forEvent:name];
}

@end