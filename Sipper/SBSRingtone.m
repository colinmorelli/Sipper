//
//  SBSRingtone.m
//  Sipper
//
//  Created by Colin Morelli on 5/1/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSRingtone.h"

@implementation SBSRingtone

- (instancetype)initWithURL:(NSURL *)url {
  if (self = [super init]) {
    _url = url;
  }

  return self;
}

@end
