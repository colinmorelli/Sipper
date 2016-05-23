//
//  SipperAccount.h
//  Sipper
//
//  Created by Colin Morelli on 4/20/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#ifndef SBSAccount_h
#define SBSAccount_h

#import <Foundation/Foundation.h>

@class SBSAccount;
@class SBSAccountConfiguration;
@class SBSCall;
@class SBSEndpoint;
@class SBSRingtone;

/**
 *  Different registration states for the account
 */
typedef NS_ENUM(NSInteger, SBSAccountRegistrationState) {
  /**
   *  Account has an active registration with the server
   */
  SBSAccountRegistrationStateActive,
  /**
   *  Account is currently attempting to register with the server
   */
  SBSAccountRegistrationStateTrying,
  /**
   *  Account does not have an active registration with the server
   */
  SBSAccountRegistrationStateInactive,
  /**
   *  Account registrations have not been started
   */
  SBSAccountRegistrationStateDisabled
};

/**
 *  Possible errors the account can return.
 */
typedef NS_ENUM(NSInteger, SBSAccountError) {
  /**
   *  Unable to create the underlying account
   */
  SBSAccountErrorCannotCreate,
  /**
   *  Unable to start the account registration
   */
  SBSAccountErrorCannotRegister
};

@protocol SBSAccountDelegate <NSObject>

@optional

/**
 * Invoked when a new call is received
 *
 * The call provided in this method can be answered using the [call answer] method. By default, if this delegate is left
 * unimplemented the call will ring until it times out
 *
 * @param account  the account that the incomign call came in for
 * @param call     information about the incoming call
 */
- (void)account:(SBSAccount * _Nonnull)account didReceiveIncomingCall:(SBSCall * _Nonnull)call;

/**
 * Invoked just before an outgoing call is made
 *
 * This method gives you the opportunity to perform changes that are necessary in order to
 */

/**
 * Invoked when a new outbound call is made
 *
 * @param account  the account that the call was made from
 * @param call     the call that was made
 */
- (void)account:(SBSAccount * _Nonnull)account didMakeOutgoingCall:(SBSCall * _Nonnull)call;

/**
 * Invoked when the registration status of the sip account changes
 *
 * This method will be called any time the status code of the SIP registration changes, even if ultimately the
 * underlying state does not. This gives you the ability to react to all kinds of SIP events.
 *
 * @param account the account that the change is in relation to
 * @param state   the new state of the account
 * @param code    the status code of the registration
 */
- (void)account:(SBSAccount * _Nonnull)account registrationDidChangeState:(SBSAccountRegistrationState)state withStatusCode:(int)code;

/**
 * Invoked when registration fails with an error
 *
 * Note that this method may not always be reliably called. Registration could fail in the background and not trigger
 * an "error" due to underlying retry intervals. However, the registration state should always be updated correctly in
 * the registrationDidChangeState method
 *
 * @param account the account that the failure is in relation to
 * @param error   the error that occurred
 */
- (void)account:(SBSAccount * _Nonnull)account registrationDidFailWithError:(NSError * _Nonnull)error;

@end

@interface SBSAccount : NSObject

/**
 * Unique identifier for this account
 *
 * This identifier will be registered in the primary Sipper class, and can be used to fetch
 * a particular account object
 */
@property (readonly, nonatomic) NSUInteger id;

/**
 * Current registration state for this account
 *
 * This value is a snapshot of the registration state for this account at any given point in
 * time
 */
@property (readonly, nonatomic) SBSAccountRegistrationState registrationState;

/**
 * Pointer back to the endpoint that owns this account
 *
 * This pointer is weak to avoid a retain cycle. Endpoints have a strong reference to all of
 * their registered accounts.
 */
@property (readonly, weak, nonatomic, nullable) SBSEndpoint *endpoint;

/**
 * Pointer to the configuration that was used when constructing this object
 *
 * Note that this property is readonly. While the configuration object itself has mutable properties,
 * they *will not* be respected until the account is restarted
 */
@property (readonly, strong, nonatomic, nonnull) SBSAccountConfiguration *configuration;

/**
 * Delegate to receive events for the account
 *
 * The delegate will be invoked to match state changes to the underlying account, including information
 * about new incoming calls. You probably want to set this.
 */
@property (weak, nonatomic, nullable) id<SBSAccountDelegate> delegate;

/**
 * The ringtone to use for incoming calls associated with this account
 *
 * Ringtones for individual calls can be overridden on a per-call basis in the SBSAccountDelegate by implementing
 * didReceiveIncomingCall and setting call.ringtone on the call isntance
 */
@property (strong, nonatomic, nullable) SBSRingtone *ringtone;

/**
 * All active calls on this account
 */
@property (strong, nonatomic, nonnull, readonly) NSArray<SBSCall *> *calls;

/**
 * Starts the account and registers with the endpoint
 *
 * The SBSAccount instance must be initialized using the createWithError method before it can be started. This
 * is automatically handled for you when using the convenience methods on SBSEndpoint (highly recommended).
 *
 * Note that accounts will not be registered with the SIP provider until the start method is called. This gives you
 * an opportunity to attach delegates to the SBSAccount and avoid race conditions
 */
- (void)startRegistration;

/**
 * Stops the account and removes its registration from the endpoint
 *
 * This method is a no-op if the account hasn't already started registering. Note that the effects of this method are
 * not immedate, and are made on a best-attempt basis.
 */
- (void)stopRegistration;

/**
 * Updates the configuration for this account
 *
 * If this account has started registration, this method will unregister the current account, perform the configuration
 * update, and register the new account. You will *not* receive any events relating to a failure in unregistration with
 * the old credentials. If this is important to you, you should manually call stopRegistration and remove the account,
 * then perform this update and re-start registration
 *
 * @param configuration the new configuration to use
 */
- (void)updateConfiguration:(SBSAccountConfiguration * _Nonnull)configuration;

/**
 * Handles a reachability change in the application
 *
 * The responsibility of this method is to recreate any transports that are necessary after the local IP address changes due
 * to a reachability event. It should make a best effort to restore any active calls.
 */
- (void)handleReachabilityChange;

/**
 * Creates a new call to the requested target destination
 *
 * New calls created from this method will immediately send their invite to the remote. It's possible that you
 * miss some delegate methods, as you're not able to attach the delegate fast enough. As a result, it's recommended
 * to always read call state from the SBSCall's ivars to reconcile anything that was missed
 *
 * @param destination the destination in the form of a SIP URI to make this call to
 * @param error       pointer to an error in case the call can't be made
 * @return a new call instance
 */
- (SBSCall * _Nonnull)callWithDestination:(NSString * _Nonnull)destination;

@end

#endif /* SBSAccount_h */
