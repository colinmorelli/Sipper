//
//  NSString+PJString.h
//  Sipper
//
//  Created by Colin Morelli on 4/20/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <pjsua.h>

@interface NSString (PJString)

/**
 *  This returns a string for the pjsip library.
 */
@property(readonly) pj_str_t pjString;

/**
 *  This will return a string which can be read by human eyes.
 *
 *  @param pjString pjString struct
 *
 *  @return NSString
 */
+ (NSString *)stringWithPJString:(pj_str_t)pjString;

/**
 *  This will prepend "sip:" in front of the string.
 *
 *  @return NSString
 */
- (NSString *)prependSipUri;

/**
 *  This will create a sip uri with added domain info if necessary.
 *
 *  @param domain a NSString with domain info.
 *
 */
- (pj_str_t)sipUriWithDomain:(NSString *)domain;

@end
