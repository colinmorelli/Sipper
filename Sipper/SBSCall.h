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
#import "SBSEventDispatcher.h"

extern NSString * _Nonnull const SBSCallEventStateChange;
extern NSString * _Nonnull const SBSCallEventReceivedMessage;

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
   *  Call is currently being setup, and no underlying call exists in the SIP stack
   */
  SBSCallStateSetup,
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
   *  The call is not ready to perform this action
   */
  SBSCallErrorCallNotReady,
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
  SBSCallErrorCannotUnhold,
  /**
   *  Unable to send a re-invite for the call
   */
  SBSCallErrorCannotReinvite
};

@interface SBSCallEvent : SBSEvent

/**
 * The call that this event corresponds to
 *
 * Events contain a strong reference to the call that triggered them so that listeners can easily
 * access call information without needing to create a weak reference to the call outside of their
 * observers.
 */
@property (readonly, strong, nonnull, nonatomic) SBSCall *call;

@end

typedef void (^SBSCallEventListener)(SBSCallEvent * _Nonnull);

@interface SBSCall : NSObject

/**
 * UUID for the call that can be used in the application
 */
@property (strong, nonnull, nonatomic) NSUUID *uuid;

/**
 * Underlying SIP provider ID for the call
 */
@property (nonatomic) NSInteger id;

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
@property (strong, nonatomic, nonnull, readonly) NSDictionary<NSString *, NSObject *> *allHeaders;

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
 * Timestamp that this call initially went into an active state (for determining duration)
 */
@property (strong, nonatomic, nullable, readonly) NSDate *activeAt;

/**
 * Returns the value for a specific header on the call
 *
 * This method is case-insensitive. All headers are stored in a map that is held lowercase internally,
 * and this method applies the same case rules
 *
 * @param header the name of the header to get a value for
 */
- (NSString * _Nullable)valueForHeader:(NSString * _Nonnull)header;

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
- (void)holdWithCallback:(void (^_Nullable)(BOOL, NSError * _Nullable))callback;

/**
 * Unholds the call if it's currently on hold
 *
 * If the call is not currently on hold, this is a no-op. Note that you can't unhold a call on which
 * hold hasn't been confirmed. You can verify if you're in a local hold by checking the aggregate
 * mediaState property on a call
 *
 * @param callback a callback that will be invoked when the call is reinvited
 */
- (void)unholdWithCallback:(void (^_Nullable)(BOOL, NSError * _Nullable))callback;

/**
 * Sends a re-invite to the active call
 *
 * The purpose of this method is to attempt to update the contact destination for a live call, due to
 * (for example) an address change.
 *
 * @param callback a callback that will be invoked when the call is reinvited
 */
- (void)reinviteWithCallback:(void (^_Nullable)(BOOL, NSError * _Nullable))callback;

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
 * Adds a new target/action pair to the listeners for this call
 *
 * Multiple listeners can be added to a call, and they will be invoked in the order that they're registered
 * with the dispatcher
 *
 * @param target   the target to invoke on a new event
 * @param selector selector on the target to invoke
 * @param event    the event to invoke the target for
 * @return a binding that can be used to remove the listener
 */
- (SBSEventBinding * _Nonnull)addListenerWithTarget:(id _Nonnull)target action:(SEL _Nonnull)selector forEvent:(NSString * _Nonnull)event;

/**
 * Adds a new block as a listener for call events on this call
 *
 * Multiple listeners can be added to a call, and they will be invoked in the order that they're registered
 * with the dispatcher
 *
 * @param block the block to invoke for the event
 * @return a binding that can be used to remove the listener
 */
- (SBSEventBinding * _Nonnull)addListenerWithBlock:(SBSCallEventListener _Nonnull)block forEvent:(NSString * _Nonnull)event;

/**
 * Removes a previously registered listener
 *
 * This method attempts to safely remove a previously registered binding from an event type
 * on the call
 *
 * @param binding the binding that was returned from addTarget
 */
- (void)removeBinding:(SBSEventBinding * _Nonnull)binding;

@end

#endif
