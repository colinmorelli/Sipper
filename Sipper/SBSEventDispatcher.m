//
//  SBSEventDispatcher.m
//  Sipper
//
//  Created by Colin Morelli on 6/3/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSEventDispatcher.h"

#import "SBSEventBinding.h"

@implementation SBSEvent

- (instancetype)initWithName:(NSString *)name {
  if (self = [super init]) {
    _name = name;
  }
  
  return self;
}

@end

@interface SBSEventDispatcher ()

@property (strong, nonatomic) NSMutableDictionary *bindings;

@end

@implementation SBSEventDispatcher

- (instancetype)init {
  if (self = [super init]) {
    _bindings = [[NSMutableDictionary alloc] init];
  }
  
  return self;
}

- (SBSEventBinding *)addEventListener:(id<SBSEventListener>)listener forEvent:(NSString *)event {
  NSMutableArray *bindingsForEvent = _bindings[event];
  if (bindingsForEvent == nil) {
    bindingsForEvent = [[NSMutableArray alloc] init];
    _bindings[event] = bindingsForEvent;
  }
  
  SBSEventBinding *binding = [SBSEventBinding bindingWithListener:listener eventName:event];
  [bindingsForEvent addObject:binding];
  
  return binding;
}

- (void)removeBinding:(SBSEventBinding *)binding {
  NSMutableArray *bindingsForEvent = _bindings[binding.eventName];
  
  if ([bindingsForEvent containsObject:binding]) {
    [bindingsForEvent removeObject:binding];
  }
}

#pragma mark - Dispatching Events

- (void)dispatchEvent:(SBSEvent *)event {
  for (SBSEventBinding *binding in _bindings[event.name]) {
    if (![binding.listener dispatchEvent:event]) {
      [self removeBinding:binding];
    }
  }
}

@end
