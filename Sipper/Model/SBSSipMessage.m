//
//  SBSSipMessage.m
//  Sipper
//
//  Created by Colin Morelli on 9/18/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSSipMessage.h"

@implementation SBSSipMessage

- (instancetype)initWithCallId:(NSString *)callId headers:(NSDictionary<NSString *, NSString *> *)headers {
  if (self = [super init]) {
    _callId = callId;
    _headers = headers;
  }

  return self;
}

@end
