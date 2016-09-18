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
 * Underlying SIP provider ID for the call
 */
@property(nonatomic) pjsua_call_id callId;

/**
 * Creates a new instance of a call wrapper from the incoming PJSIP call
 *
 * @param account    the account that is receiving the call
 * @param callId     the identifier for the call
 * @param account    the account instance that this call is for
 * @param direction  the direction of the call
 * @return new call instance
 */
+ (instancetype _Nonnull)incomingCallWithAccount:(SBSAccount *_Nonnull)account callId:(pjsua_call_id)callId data:(pjsip_rx_data *_Nonnull)data;

/**
 * Creates a new instance of a call wrapper from the incoming PJSIP call
 *
 * @param account     the account that is making the call
 * @param destination the remote endpoint receiving the call
 * @param headers     headers that were included on the call
 * @return new call instance
 */
+ (instancetype _Nonnull)outgoingCallWithAccount:(SBSAccount *_Nonnull)account destination:(NSString *_Nonnull)destination headers:(NSDictionary<NSString *, NSString *> *_Nullable)headers;

/**
 * Starts ringing the call
 *
 * The call will stop ringing on its own when the answer or hangup methods or called, or when the active state of the call
 * changes
 */
- (void)ring;

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
 * @param event       the event that triggered the state change
 */
- (void)handleTransactionStateChange:(pjsip_transaction *_Nonnull)transaction event:(pjsip_event *_Nonnull)event;

/**
 * Invoked by the endpoint when a transport changes state
 *
 * This fans out to all active calls to release a hold on their transports, if someone is
 * expliclty trying to shut this transport down
 *
 * @param transport   the transport that had a state change
 * @param state       the state of the transport
 * @param info        additional state information
 */
- (void)handleTransportStateChange:(pjsip_transport *_Nonnull)transport state:(pjsip_transport_state)state info:(const pjsip_transport_state_info *_Nonnull)info;

@end

#endif
