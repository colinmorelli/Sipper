//
//  SBSSipMessage.h
//  Sipper
//
//  Created by Colin Morelli on 9/18/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SBSSipMessage : NSObject

/**
 * Call ID that the message represents
 */
@property(nonatomic, strong, nonnull, readonly) NSString *callId;

/**
 * All headers present on the message
 */
@property(nonatomic, strong, nonnull, readonly) NSDictionary<NSString *, NSString *> *headers;

/**
 * Creates a new instance of a response message with the given parameters
 *
 * @param callId  the call id of the message chain
 * @param headers the dictionary of headers on the call
 */
- (_Nonnull instancetype)initWithCallId:(NSString * _Nonnull)callId
                                headers:(NSDictionary<NSString *, NSString *> * _Nonnull)headers;

@end
