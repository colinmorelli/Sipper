//
//  SipperAccountConfiguration.m
//  Sipper
//
//  Created by Colin Morelli on 4/20/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SipperAccountConfiguration.h"

@implementation SipperAccountConfiguration

- (instancetype) init {
  if (self = [super init]) {
    self.sipAuthRealm = @"*";
    self.sipAuthScheme = SipperAuthenticationSchemeDigest;
    self.sipRegistrationRetryTimeout = 500;
  }
  
  return self;
}

- (NSString *)sipAddress {
  if (self.sipAccount && self.sipDomain) {
    return [NSString stringWithFormat:@"sip:%@@%@", self.sipAccount, self.sipDomain];
  }
  return nil;
}

@end
