//
//  SBSSipRequestMessage.m
//  Sipper
//
//  Created by Colin Morelli on 9/18/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSSipRequestMessage.h"

@implementation SBSSipRequestMessage

- (instancetype)initWithMethod:(NSString *)method callId:(NSString *)callId headers:(NSDictionary<NSString *, NSString *> *)headers {
  if (self = [super initWithCallId:callId headers:headers]) {
    _method = method;
  }

  return self;
}

@end
