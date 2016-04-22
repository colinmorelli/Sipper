//
//  SipperEndpoint.h
//  Sipper
//
//  Created by Colin Morelli on 4/20/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#ifndef SBSEndpoint_h
#define SBSEndpoint_h

#import <Foundation/Foundation.h>

@class SBSAccount;
@class SBSAccountConfiguration;
@class SBSAudioManager;
@class SBSEndpointConfiguration;

/**
 *  Possible errors the Endpoint can return.
 */
typedef NS_ENUM(NSInteger, SBSEndpointError) {
  /**
   *  Unable to create the pjsip library.
   */
  SBSEndpointErrorCannotCreate,
  /**
   *  Unable to initialize the pjsip library.
   */
  SBSEndpointErrorCannotInitialize,
  /**
   *  Unable to add transport configuration to endpoint.
   */
  SBSEndpointErrorCannotAddTransportConfiguration,
  /**
   *  Unable to start the pjsip library.
   */
  SBSEndpointErrorCannotStart,
  /**
   *  Unable to create the thread for pjsip.
   */
  SBSEndpointErrorCannotCreateThread,
  /**
   *  Unable to cleanly destroy the endpoint on shutdown.
   */
  SBSEndpointErrorCannotDestroy
};

@interface SBSEndpoint : NSObject

@property (strong, nonatomic, readonly) SBSEndpointConfiguration *configuration;

/**
 * Initializes the SIP endpoint
 *
 * This method sets up underlying data structures and functions to prepare the endpoint for use
 * and account registrations.
 *
 * @param configuration sip endpoint configuration to use
 * @param error         pointer to an error
 * @return if the initialization was successful
 */
- (BOOL)initializeEndpointWithConfiguration:(SBSEndpointConfiguration *)configuration error:(NSError **)error;

/**
 * Destroys the underlying SIP endpoint
 *
 * This method will block while it waits for some final network calls to come back from the
 * SIP server (it attempts to shutdown gracefully). You may call this in a background thread
 * to avoid blocking the UI
 *
 * @param error pointer to an error
 * @return of the destroy was successful
 */
- (BOOL)destroyEndpointWithError:(NSError **)error;

/**
 * Attempts to create and register an account with the endpoint
 *
 * This method does not block to wait for the server to respond. In fact, this does not communicate
 * with the server at all. You may call start and stop on the returned account object to register the
 * account with the server
 *
 * @param configuration the account configuration to use when constructing the account
 * @param error         pointer to an error
 * @return a created account instance, if successful
 */
- (SBSAccount *)createAccountWithConfiguration:(SBSAccountConfiguration *)configuration error:(NSError **)error;

/**
 * Returns the audio manager associated with this endpoint
 *
 * You can use the audio manager to configure input/output devices for handling call audio. Note that the
 * methods on SBAudioManager will affect all calls, as you're changing the input and output devices for the
 * local host.
 *
 * @returns the audio manager that controls local audio devices
 */
- (SBSAudioManager *)audioManager;

/**
 * Returns the static shared endpoint
 *
 * Note that the SBSEndpoint returned from this method *is not* ready to be used until initializeEndpointWithConfiguration
 * is invoked on it.
 */
+ (instancetype)sharedEndpoint;

@end

#endif
