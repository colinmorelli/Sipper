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
@class SBSCall;
@class SBSCodecDescriptor;
@class SBSEndpoint;
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
        SBSEndpointErrorCannotRegisterThread,
    /**
     *  Unable to cleanly destroy the endpoint on shutdown.
     */
        SBSEndpointErrorCannotDestroy
};

/**
 *  Possible states that the endpoint can be in
 */
typedef NS_ENUM(NSInteger, SBSEndpointState) {
    /**
     *  The endpoint is currently idle
     */
        SBSEndpointStateIdle,
    /**
     *  The endpoint has incoming calls that are ringing
     */
        SBSEndpointStateRingingCalls,
    /**
     *  The endpoint has active calls
     */
        SBSEndpointStateActiveCalls
};

@protocol SBSEndpointDelegate <NSObject>

@optional

/**
 * Invoked when the endpoint changes its current state
 *
 * This method is useful for updating audio session categories at appropriate points throughout your application,
 * without needing to send all SBSCallDelegates through a single class
 *
 * @param endpoint the endpoint that was updated
 * @param state    the new state of the endpoint
 */
- (void)endpoint:(SBSEndpoint *_Nonnull)account didChangeState:(SBSEndpointState)state;

@end

@interface SBSEndpoint : NSObject

/**
 * The configuration that this endpoint was initialized with
 */
@property(strong, nonatomic, readonly, nonnull) SBSEndpointConfiguration *configuration;

/**
 * All accounts that are currently registered with the endpoint
 */
@property(strong, nonatomic, readonly, nonnull) NSArray<SBSAccount *> *accounts;

/**
 * All calls that the endpoint is aware of
 */
@property(strong, nonatomic, readonly, nonnull) NSArray<SBSCall *> *calls;

/**
 * The current state of the endpoint
 */
@property(nonatomic, readonly) SBSEndpointState state;

/**
 * Delegate to receive events for the endpoint
 */
@property(weak, nonatomic, nullable) id <SBSEndpointDelegate> delegate;

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
- (BOOL)initializeEndpointWithConfiguration:(SBSEndpointConfiguration *_Nonnull)configuration error:(NSError *_Nullable *_Nullable)error;

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
- (BOOL)destroyEndpointWithError:(NSError *_Nullable *_Nullable)error;

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
- (SBSAccount *_Nullable)createAccountWithConfiguration:(SBSAccountConfiguration *_Nonnull)configuration error:(NSError *_Nullable *_Nullable)error;

/**
 * Deregisters an account from the endpoint
 *
 * You should only call this method if you want to ensure the account is de-registered and removed from
 * the endpoint so that it can't be used again until it's re-created. If you just temporarily want to pause
 * an account, you can call stopRegistration on the account instance.
 *
 * @param id the identifier of the account
 */
- (void)removeAccount:(NSUUID * _Nonnull)id;

/**
 * Returns the account associated with the requested account ID
 *
 * @param id the account ID to find
 * @return the account associated with that ID, if it exists
 */
- (SBSAccount *_Nullable)findAccount:(NSUUID * _Nonnull)id;

/**
 * Updates the codec priorities for the endpoint
 *
 * Note that calling this method will not affect any calls that are currently active. Those calls must be explicitly re-negotiated
 * by calling reinvite in the SBSCall instance.
 *
 * @param descriptors new codec descriptors to assign
 * @param error       error pointer to assign if the operation fails
 * @return if the operation was successful
 */
- (BOOL)updatePreferredCodecs:(NSArray<SBSCodecDescriptor *> *_Nonnull)descriptors error:(NSError *_Nullable *_Nullable)error;

/**
 * Executes the requested block in a background thread that is safe for the endpoint
 *
 * This method will execute the requested task in a thread that is safely registered with the underlying SIP provider. This
 * allows background operations to be safely executed. Instances of SBSEndpoint must be invoked either on the main thread,
 * or using this method.
 */
- (void)performAsync:(void (^ _Nonnull)())block;

/**
 * Handles a reachability change in the application
 *
 * The responsibility of this method is to recreate any transports that are necessary after the local IP address changes due
 * to a reachability event. It should make a best effort to restore any active calls that might be lost due to the IP change. 
 * Primarily, this consists of simply sending a re-invite with the updated IP address.
 */
- (void)handleReachabilityChange;

/**
 * Disables the audio devices on the active call
 *
 * The primary purpose of this method is to be used when iOS notifies the application that the audio session has been
 * interrupted. Once called, this will set all sound devices to null and stop sending/receiving audio
 */
- (void)disableAudio;

/**
 * Re-renables the audio devices on the active call
 *
 * The primary purpose of this method is to be used when iOS notifies the application that the audio session interruption has
 * ended. This will reset active audio devices.
 */
- (void)enableAudio;

/**
 * Returns the static shared endpoint
 *
 * Note that the SBSEndpoint returned from this method *is not* ready to be used until initializeEndpointWithConfiguration
 * is invoked on it.
 */
+ (instancetype _Nonnull)sharedEndpoint;

@end

#endif
