//
//  SBSSipURI.m
//  Sipper
//
//  Created by Colin Morelli on 4/21/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSSipURI.h"

@implementation SBSSipURI

//------------------------------------------------------------------------------

- (instancetype)initWithAccount:(NSString *)account password:(NSString *)password host:(NSString *)host port:(NSNumber *)port params:(NSString *)params {
  if (self = [super init]) {
    _account = account;
    _password = password;
    _host = host;
    _port = port;
    _params = params;
  }
  
  return self;
}

//------------------------------------------------------------------------------

+ (instancetype)sipUriWithString:(NSString *)uri {
  if (uri == nil) {
    return nil;
  }
  
  // Validate the input against a regular expression
  NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@"^sip:([^:@]*?)(?::([^@]*?))?@([^:]*?)(?::([0-9]{1,5}))?(?:\\?(.*?))?$"
                                                                              options:NSRegularExpressionCaseInsensitive
                                                                                error:nil];
  NSTextCheckingResult *result = [expression firstMatchInString:uri options:0 range:NSMakeRange(0, uri.length)];
  
  // Check if the string matches
  if (result == nil) {
    return nil;
  }
  
  // Rip out the relevant sections of the string
  NSRange accountRange = [result rangeAtIndex:1];
  NSString *account = accountRange.location == NSNotFound ? nil : [uri substringWithRange:accountRange];
  
  NSRange passwordRange = [result rangeAtIndex:2];
  NSString *password = passwordRange.location == NSNotFound ? nil : [uri substringWithRange:passwordRange];
  
  NSRange hostRange = [result rangeAtIndex:3];
  NSString *host = hostRange.location == NSNotFound ? nil : [uri substringWithRange:hostRange];
  
  NSRange portRange = [result rangeAtIndex:4];
  NSNumber *port = portRange.location == NSNotFound ? nil : [NSNumber numberWithInteger:[[uri substringWithRange:portRange] integerValue]];
  
  NSRange queryRange = [result rangeAtIndex:5];
  NSString *params = queryRange.location == NSNotFound ? nil : [uri substringWithRange:queryRange];
  
  // Otherwise parse it out
  return [[self alloc] initWithAccount:account password:password host:host port:port params:params];
}

@end
