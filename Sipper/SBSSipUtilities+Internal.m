//
//  SBSSipUtilities.m
//  Sipper
//
//  Created by Colin Morelli on 9/18/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSSipUtilities+Internal.h"

#import "NSString+PJString.h"
#import <pjsip.h>

@implementation SBSSipUtilities

+ (NSDictionary<NSString *, NSString *> *)headersFromMessage:(pjsip_msg *)message {
  NSMutableDictionary *headers = [[NSMutableDictionary alloc] init];
  
  pjsip_hdr *hdr = message->hdr.next,
            *end = &message->hdr;
  
  // Iterate over all of the headers, push to dictionary
  for (; hdr != end; hdr = hdr->next) {
    NSString *headerName = [NSString stringWithPJString:hdr->name];
    char value[512] = {0};
    
    // If we weren't able to read the string in 512 bytes... (we should fix this)
    if (hdr->vptr->print_on(hdr, value, 512) == -1) {
      continue;
    }
    
    // Always append the raw header value, even if we did something else above
    NSString *headerValue = [[NSString alloc] initWithCString:value encoding:NSUTF8StringEncoding];
    NSRange splitRange = [headerValue rangeOfString:@":"];
    
    // Strip out the header name from the value
    if (splitRange.location != NSNotFound) {
      headerValue = [[headerValue substringFromIndex:splitRange.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    
    [headers setObject:headerValue forKey:[headerName lowercaseString]];
  }
  
  return headers;
}

@end
