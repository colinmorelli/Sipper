//
//  SBSCall+Internal.h
//  Sipper
//
//  Created by Colin Morelli on 4/21/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#ifndef SBSCall_Internal_h
#define SBSCall_Internal_h

#import "SBSCall.h"

#import <pjsua.h>

@interface SBSCall ()

/**
 * Creates a new instance of a call wrapper from the incoming PJSIP call
 *
 * @param callId     the identifier for the call
 * @param account    the account instance that this call is for
 * @param direction  the direction of the call
 * @return new call instance
 */
+ (instancetype _Nonnull)incomingCallWithAccount:(SBSAccount * _Nonnull)account callId:(pjsua_call_id)callId data:(pjsip_rx_data * _Nonnull)data;

/**
 * Creates a new instance of a call wrapper from the incoming PJSIP call
 *
 * @param callId     the identifier for the call
 * @param account    the account instance that this call is for
 * @param direction  the direction of the call
 * @return new call instance
 */
+ (instancetype _Nonnull)outgoingCallWithAccount:(SBSAccount * _Nonnull)account callId:(pjsua_call_id)callId;

/**
 * Attempts to look up a call instance using PJSUA call identifiers
 *
 * @param callId the callId to lookup
 * @return an instance of SBSCall, if one was found for the requested call
 */
+ (instancetype _Nullable)fromCallId:(pjsua_call_id)callId;

/**
 * Invoked when the call state changes
 *
 * This method will update all internal state pointers and invoke the proper delegate methods. Note that once this
 * method is called and the state is SBSCallStateDisconnected, the call *will* be released from the SBSAccount and
 * the underlying PJSIP call instance will be de-alloced.
 */
- (void)handleCallStateChange;

/**
 * Invoked when the call's media state changes
 *
 * This method could be called for a number of reasons. It will be invoked when calls are placed on hold, new media
 * channels are opened (for example, video is added to an audio call), and more
 */
- (void)handleCallMediaStateChange;

/**
 * Invoked when a call's transaction state changes
 *
 * @param transaction the transaction whose state was changed
 */
- (void)handleTransactionStateChange:(pjsip_transaction * _Nonnull)transaction;

@end

#endif