//
//  SBSNameAddressPair.m
//  Sipper
//
//  Created by Colin Morelli on 4/21/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSNameAddressPair.h"

#import "SBSSipURI.h"

@implementation SBSNameAddressPair

//------------------------------------------------------------------------------

- (instancetype)initWithAddress:(SBSSipURI *)uri {
  return [self initWithDisplayName:nil uri:uri];
}

//------------------------------------------------------------------------------

- (instancetype)initWithDisplayName:(NSString *)name uri:(SBSSipURI *)uri {
  if (self = [super init]) {
    _name = name;
    _uri = uri;
  }
  
  return self;
}

//------------------------------------------------------------------------------

+ (instancetype)nameAddressPairFromString:(NSString *)string {
  if (string == nil) {
    return nil;
  }
  
  // Validate the input against a regular expression
  NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@"(.*?)[\\s\\t]*<([^>]+)>"
                                                                              options:NSRegularExpressionCaseInsensitive
                                                                                error:nil];
  NSTextCheckingResult *result = [expression firstMatchInString:string options:0 range:NSMakeRange(0, string.length)];
  
  // If we have no result, there's no valid pair here, fallback to just parsing a SIP URI
  if (result == nil) {
    SBSSipURI *uri = [SBSSipURI sipUriWithString:string];
    if (uri == nil) {
      return nil;
    }
    
    return [[self alloc] initWithDisplayName:nil uri:uri];
  }
  
  // Otherwise, grab the name and address
  NSString *name = [string substringWithRange:[result rangeAtIndex:1]];
  NSString *address = [string substringWithRange:[result rangeAtIndex:2]];
  
  // Trim off any quotes around the name
  name = [name stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"'\" "]];
  SBSSipURI *uri = [SBSSipURI sipUriWithString:address];
  
  // If the SIP URI is not valid, then fail here
  if (uri == nil) {
    return nil;
  }
  
  // Return the new instance from the matched regex
  return [[self alloc] initWithDisplayName:name uri:uri];
}

@end
