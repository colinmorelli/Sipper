//
//  SBSSipRequestMessage.h
//  Sipper
//
//  Created by Colin Morelli on 9/18/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SBSSipMessage.h"

@interface SBSSipRequestMessage : SBSSipMessage

/**
 * Request method on the message
 */
@property(nonatomic, strong, nonnull, readonly) NSString *method;

/**
 * Creates a new instance of a response message with the given parameters
 *
 * @param status  the status code on the response message
 * @param callId  the call id of the message chain
 * @param headers the dictionary of headers on the call
 */
- (_Nonnull instancetype)initWithMethod:(NSString *_Nonnull)method
                                 callId:(NSString *_Nonnull)callId
                                headers:(NSDictionary<NSString *, NSString *> *_Nonnull)headers;

@end
