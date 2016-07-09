//
//  SBSAccount+Internal.h
//  Sipper
//
//  Created by Colin Morelli on 4/22/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#ifndef SBSAccount_Internal_h
#define SBSAccount_Internal_h

#import "SBSAccount.h"
#import <pjsua.h>

@class SBSAccountConfiguration;
@class SBSEndpoint;

@interface SBSAccount ()

/**
 * Invoked once we've started a registration attempt with PJSUA
 *
 * Internally, this method updates some internal structures and invokes the delegate of the
 * account to reflect the state change
 */
- (void)handleRegistrationStarted:(pjsua_reg_info * _Nonnull)info;

/**
 * Invoked on receiving a callback from PJSUA
 *
 * Internally, this method updates some internal structures and invokes the delegate of the
 * account to reflect the state change
 */
- (void)handleRegistrationStateChange:(pjsua_reg_info * _Nonnull)info;

/**
 * Invoked by the endpoint when this account is receiving a new call
 *
 * @param callId the PJSIP call identifier for the incoming call
 * @param data   the incoming rxdata that can be parsed for headers
 */
- (void)handleIncomingCall:(pjsua_call_id)callId data:(pjsip_rx_data * _Nonnull)data;

/**
 * Invoked by the endpoint when a call tracked by this account is updated
 *
 * @param callId the PJSIP call identifier for the call that was updated
 */
- (void)handleCallStateChange:(pjsua_call_id)callId;

/**
 * Invoked by the endpoint when a call tracked by this account has its media channels updated
 *
 * @param callId the PJSIP call identifier for the call that was updated
 */
- (void)handleCallMediaStateChange:(pjsua_call_id)callId;

/**
 * Invoked by the endpoint when a call's TSX transaction status changes
 *
 * @param callId      the PJSIP call identifier for the call whose transaction changed
 * @param transaction the transaction that was updated during this call
 * @param event       the event that triggered the state change
 */
- (void)handleCallTsxStateChange:(pjsua_call_id)callId transation:(pjsip_transaction * _Nonnull)transaction event:(pjsip_event * _Nonnull)event;

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
- (void)handleTransportStateChange:(pjsip_transport * _Nonnull)transport state:(pjsip_transport_state)state info:(const pjsip_transport_state_info * _Nonnull)info;

/**
 * Attempts to create a new account and returns the account instance
 *
 * @param configuration the account configuration to use
 * @param endpoint      pointer to the endpoint that is tracking this account
 * @param error         pointer to an error if account creation fails
 * @return an account instance, if creation was successful
 */
+ (instancetype _Nullable)accountWithConfiguration:(SBSAccountConfiguration * _Nonnull)configuration endpoint:(SBSEndpoint * _Nonnull)endpoint error:(NSError * _Nullable * _Nullable)error;

@end

#endif /* SBSAccount_Internal_h */
