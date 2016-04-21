//
//  SipperAccount.h
//  Sipper
//
//  Created by Colin Morelli on 4/20/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#ifndef SBSAccount_h
#define SBSAccount_h

#import "SBSAccountConfiguration.h"

@class SBSAccount;
@class SBSEndpoint;

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
  SBSAccountRegistrationStateInactive
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

@protocol SBSAccountDelegate

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
@property (readonly, strong, nonatomic, nonnull) NSString *id;

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
 * Creates a new account with the requested account configuration
 *
 * This method creates and configures the account object, but will not perform an explicit
 * registration until the start method is called. Once the start method is called, registration
 * will be retained until stop is invoked
 *
 * @param id            unique identifier for this account
 * @param configuration the account configuration to use when creating the account
 */
- (instancetype _Nonnull)initWithIdentifier:(NSString * _Nonnull)identifier configuration:(SBSAccountConfiguration * _Nonnull)configuration endpoint:(SBSEndpoint * _Nullable)endpoint;

/**
 * Attempts to construct the underlying account
 *
 * This method *must* be called before any other methods on the account class. It's automatically
 * performed by the Sipper instance, which should be used by default
 *
 * @param error pointer to an error
 * @return if the account was successfully created
 */
- (BOOL)createWithError:(NSError * _Nullable * _Nullable)error;

/**
 * Starts the account and registers with the endpoint
 *
 * The SBSAccount instance must be initialized using the createWithError method before it can be started. This
 * is automatically handled for you when using the convenience methods on SBSEndpoint (highly recommended).
 *
 * Note that accounts will not be registered with the SIP provider until the start method is called. This gives you
 * an opportunity to attach delegates to the SBSAccount and avoid race conditions
 */
- (void)start;

@end

#endif /* SBSAccount_h */
