//
//  SipperAccountConfiguration.m
//  Sipper
//
//  Created by Colin Morelli on 4/20/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSAccountConfiguration.h"

@implementation SBSAccountConfiguration

//------------------------------------------------------------------------------

- (instancetype)init {
  if (self = [super init]) {
    _sipAuthRealm = @"*";
    _sipAuthScheme = SBSAuthenticationSchemeDigest;
    _secureMediaPolicy = SBSSecureMediaPolicyOptional;
    _sipRegistrationRetryTimeout = 500;
    _sipRegistrationLifetime = 800;
  }

  return self;
}

//------------------------------------------------------------------------------

- (NSString *)sipAddress {
  if (self.sipAccount && self.sipDomain) {
    return [NSString stringWithFormat:@"sip:%@@%@", self.sipAccount, self.sipDomain];
  }
  return nil;
}

@end
