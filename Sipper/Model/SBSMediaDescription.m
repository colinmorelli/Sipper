//
//  SBSMediaDescription.m
//  Sipper
//
//  Created by Colin Morelli on 5/3/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSMediaDescription.h"

@implementation SBSMediaDescription

- (instancetype)initWithMediaType:(SBSMediaType)type direction:(SBSMediaDirection)direction state:(SBSMediaState)state {
  if (self = [super init]) {
    _type = type;
    _direction = direction;
    _state = state;
  }

  return self;
}

@end
