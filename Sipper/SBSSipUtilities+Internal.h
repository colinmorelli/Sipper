//
//  SBSSipUtilities.h
//  Sipper
//
//  Created by Colin Morelli on 9/18/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef struct pjsip_msg pjsip_msg;

@interface SBSSipUtilities : NSObject

/**
 * Creates an NSDictionary from a SIP message
 *
 * Attempts to parse all of the headers information out of a SIP message construct
 * to return a dictionary of headers present in the message
 *
 * @param message the message to parse
 */
+ (NSDictionary<NSString *, NSString *> *)headersFromMessage:(pjsip_msg *)message;

@end
