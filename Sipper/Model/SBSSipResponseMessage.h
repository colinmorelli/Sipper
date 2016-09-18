//
//  SBSSipResponseMessage.h
//  Sipper
//
//  Created by Colin Morelli on 9/18/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SBSSipMessage.h"

@interface SBSSipResponseMessage : SBSSipMessage

/**
 * Status code on the response message
 */
@property(nonatomic, readonly) NSUInteger status;

/**
 * Status code on the response message
 */
@property(nonatomic, strong, nonnull, readonly) NSString *statusReason;

/**
 * Creates a new instance of a response message with the given parameters
 *
 * @param status  the status code on the response message
 * @param reason  the reason code of the status line
 * @param callId  the call id of the message chain
 * @param headers the dictionary of headers on the call
 */
- (_Nonnull instancetype)initWithStatusCode:(NSUInteger)status
                               statusReason:(NSString *_Nonnull)reason
                                     callId:(NSString *_Nonnull)callId
                                    headers:(NSDictionary<NSString *, NSString *> *_Nonnull)headers;

@end
