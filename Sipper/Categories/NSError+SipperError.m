//
//  NSError+SipperError.m
//  Sipper
//
//  Created by Colin Morelli on 4/20/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "NSError+SipperError.h"

@implementation NSError (SipperError)

+ (NSError *)ErrorWithUnderlying:(NSError *)underlyingErrorKey localizedDescriptionKey:(NSString *)localizedDescriptionKey localizedFailureReasonError:(NSString *)localizedFailureReasonError errorDomain:(NSString *)errorDomain errorCode:(NSUInteger)errorCode {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  
  if (underlyingErrorKey) {
    [userInfo setObject:underlyingErrorKey forKey:NSUnderlyingErrorKey];
  }
  
  if (localizedDescriptionKey) {
    [userInfo setObject:localizedDescriptionKey forKey:NSLocalizedDescriptionKey];
  }
  
  if (localizedFailureReasonError) {
    [userInfo setObject:localizedFailureReasonError forKey:NSLocalizedFailureReasonErrorKey];
  }
  
  return [NSError errorWithDomain:errorDomain code:errorCode userInfo:[userInfo copy]];
}

@end
