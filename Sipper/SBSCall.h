//
//  SBSCall.h
//  Sipper
//
//  Created by Colin Morelli on 4/21/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#ifndef SBSCall_h
#define SBSCall_h

#import <Foundation/Foundation.h>
#import "SBSConstants.h"

@class SBSAccount;
@class SBSCall;
@class SBSMediaDescription;
@class SBSNameAddressPair;
@class SBSRingtone;

/**
 *  Different possible hold states
 */
typedef NS_ENUM(NSInteger, SBSHoldState) {
  /**
   * The call is not currently on hold
   */
  SBSHoldStateNone,
  
  /**
   * The call is on hold by the local endpoint
   */
  SBSHoldStateLocal,
  
  /**
   * The call is on hold by the remote endpoint
   */
  SBSHoldStateRemote
};

/**
 *  Different valid call states
 */
typedef NS_ENUM(NSInteger, SBSCallState) {
  /**
   * Call state is currently unknown (before dial or answer)
   */
  SBSCallStateUnknown,
  /**
   *  Call has been disconnected, and is no longer valid
   */
  SBSCallStateDisconnected,
  /**
   *  Call is currently ringing, waiting for remote response
   */
  SBSCallStateCalling,
  /**
   *  Call is currently incoming, pending response
   */
  SBSCallStateIncoming,
  /**
   *  Call is currently engaged in early media
   */
  SBSCallStateEarly,
  /**
   *  Call has been accepted, and is pending confirmation
   */
  SBSCallStateConnecting,
  /**
   *  Call is currently active and connected
   */
  SBSCallStateActive
};

/**
 *  Different possible call dirations
 */
typedef NS_ENUM(NSInteger, SBSCallDirection) {
  /**
   *  Call was made from this device, to the SIP server.
   */
  SBSCallDirectionOutbound,
  /**
   *  Call was received on this device, from somewhere else
   */
  SBSCallDirectionInbound
};

/**
 *  Possible errors the call can return.
 */
typedef NS_ENUM(NSInteger, SBSCallError) {
  /**
   *  Unable to answer the call
   */
  SBSCallErrorCannotAnswer,
  /**
   *  Unable to hangup the call
   */
  SBSCallErrorCannotHangup,
  /**
   *  Unable to place the call on hold
   */
  SBSCallErrorCannotHold,
  /**
   *  Unable to take the call off of hold
   */
  SBSCallErrorCannotUnhold
};

@protocol SBSCallDelegate<NSObject>

@optional

/**
 * Invoked when the call changes its current call state
 *
 * @param call   the call that this is in reference to
 * @param state  the new state of the target call
 */
- (void)call:(SBSCall * _Nonnull)call didChangeState:(SBSCallState)state;

/**
 * Invoked when the underlying call's media state changes
 *
 * This method will be invoked when any of the underlying media streams changes. It is on the application
 * to check the call's media descriptions to determine if there's anything relevant
 *
 * @param call         the call that was changed during this callback
 * @param descriptions the media descriptions associated with this call
 */
- (void)call:(SBSCall * _Nonnull)call didChangeMediaState:(NSArray<SBSMediaDescription *> * _Nonnull)descriptions;

/**
 * Invoked when the hold state of the call changes
 *
 * You can implement this delegate method to receive callbacks when hold and unhold requests
 * have been processed
 *
 * @param call   the call that was changed
 * @param state  the hold state of the call
 */
- (void)call:(SBSCall * _Nonnull)call didChangeHoldState:(SBSHoldState)state;

@end

@interface SBSCall : NSObject

/**
 * Unique identifier for the call
 */
@property (nonatomic) NSUInteger id;

/**
 * The SIP URI for the local end of the call
 */
@property (nonatomic, nullable) SBSNameAddressPair *local;

/**
 * The SIP URI for the remote end of the call
 */
@property (nonatomic, nullable) SBSNameAddressPair *remote;

/**
 * All SIP headers present on the call
 */
@property (strong, nonatomic, nonnull, readonly) NSDictionary *allHeaders;

/**
 * The account that this call belongs to
 */
@property (weak, nonatomic, nullable, readonly) SBSAccount *account;

/**
 * The ringtone to play on this call
 */
@property (strong, nonatomic, nonnull) SBSRingtone *ringtone;

/**
 * The direction of the call, can either be inbound or outbound
 */
@property (nonatomic, readonly) SBSCallDirection direction;

/**
 * The current state that the call is in
 */
@property (nonatomic, readonly) SBSCallState state;

/**
 * The hold state for the call
 */
@property (nonatomic, readonly) SBSHoldState holdState;

/**
 * Array of media attached to the call
 */
@property (strong, nonnull, nonatomic, readonly) NSArray<SBSMediaDescription *> *media;

/**
 * The current mute state of the call, can be set to place the call on mute
 */
@property (nonatomic) BOOL muted;

/**
 * Delegate to receive call events
 */
@property (weak, nonatomic, nullable) id<SBSCallDelegate> delegate;

/**
 * Answers the call with a 200 OK status code
 *
 * This is a convenience method for the alternative ANSWER implementation that takes a status code. 
 * Alternative methods can be used to send pre-media to the caller.
 *
 * Note that the callback provided to this method will be invoked when we receive a result from sending
 * the answer. This *does not* mean that the call has actually been answered or connected. In order to
 * receive those events, you should attach a delegate to the call and observe for the call state change
 * events
 *
 * @param callback callback to invoke on completion
 */
- (void)answerWithCompletion:(void (^ _Nullable)(BOOL success, NSError * _Nullable))callback;

/**
 * Answers the call with the requested status code
 *
 * You probably want to have a delegate set before calling this method. You won't receive delegate
 * methods until you do.
 *
 * Note that the callback provided to this method will be invoked when we receive a result from sending
 * the answer. This *does not* mean that the call has actually been answered or connected. In order to
 * receive those events, you should attach a delegate to the call and observe for the call state change
 * events
 *
 * @param code the status code to answer the call with
 * @param callback callback to invoke on completion
 */
- (void)answerWithStatus:(SBSStatusCode)code completion:(void (^ _Nullable)(BOOL, NSError * _Nullable))callback;

/**
 * Hangs up this call with a 603 Decline status code
 *
 * This method can be invoked on a call that is not currently answered. If it is, the call will be
 * explicitly declined.
 *
 * @param callback callback to invoke on success
 */
- (void)hangupWithCompletion:(void (^ _Nullable)(BOOL success, NSError * _Nullable))callback;

/**
 * Hangs up this call with the requested status code
 *
 * This method can be invoked on a call that is not currently answered. If it is, the call will be
 * explicitly declined.
 *
 * @param code     the status code to respond with
 * @param callback callback to invoke on success
 */
- (void)hangupWithStatus:(SBSStatusCode)code completion:(void (^ _Nullable)(BOOL, NSError * _Nullable))callback;

/**
 * Places the call on hold
 *
 * Note that holds are not guaranteed to work. They require the endpoint to support parking the call,
 * and need to wait for acceptance of the park status. As a result, hold's are required to function
 * asynchronously.
 *
 * @param callback a callback that will be invoked when the hold response is sent
 */
- (void)holdWithCallback:(void (^_Nonnull)(BOOL, NSError * _Nullable))callback;

/**
 * Unholds the call if it's currently on hold
 *
 * If the call is not currently on hold, this is a no-op. Note that you can't unhold a call on which
 * hold hasn't been confirmed. You can verify if you're in a local hold by checking the aggregate
 * mediaState property on a call
 *
 * @param callback a callback that will be invoked when the call is reinvited
 */
- (void)unholdWithCallback:(void (^_Nonnull)(BOOL, NSError * _Nullable))callback;

/**
 * Sends the requested digits as DTMF tones
 *
 * Callers can pass any number of digits as a string to this method. Each digit will be sent individually
 * to the remote.
 *
 * @param digits the digits to send to the remote
 */
- (void)sendDigits:(NSString * _Nullable)digits;

/**
 * Returns a value for the named header
 *
 * @param header the name of the header to get the value for (case insensitive)
 * @return the header's value, if present
 */
- (NSString * _Nullable)valueForHeader:(NSString * _Nonnull)header;

@end

#endif