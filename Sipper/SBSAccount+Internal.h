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
 * Attempts to construct the underlying account
 *
 * This method *must* be called before any other methods on the account class. It's automatically
 * performed by the endpoint, which should be how it's always used
 *
 * @param error pointer to an error
 * @return if the account was successfully created
 */
- (BOOL)createWithError:(NSError * _Nullable * _Nullable)error;

/**
 * Invoked on receiving a callback from PJSUA
 *
 * Internally, this method updates some internal structures and invokes the delegate of the
 * account to reflect the state change
 */
- (void)handleRegistrationStateChange;

/**
 *
 */
- (void)handleIncomingCall:(pjsua_call_id)callId data:(pjsip_rx_data * _Nonnull)data;

- (void)handleCallStateChange:(pjsua_call_id)callId;
- (void)handleCallMediaStateChange:(pjsua_call_id)callId;

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
