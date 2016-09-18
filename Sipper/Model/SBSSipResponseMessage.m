//
//  SBSSipResponseMessage.m
//  Sipper
//
//  Created by Colin Morelli on 9/18/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSSipResponseMessage.h"

@implementation SBSSipResponseMessage

- (instancetype)initWithStatusCode:(NSUInteger)status statusReason:(NSString *_Nonnull)reason callId:(NSString *_Nonnull)callId headers:(NSDictionary<NSString *, NSString *> *_Nonnull)headers {
  if (self = [super initWithCallId:callId headers:headers]) {
    _status = status;
    _statusReason = reason;
  }

  return self;
}

@end
