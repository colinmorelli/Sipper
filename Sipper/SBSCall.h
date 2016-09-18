//
// Created by Colin Morelli on 9/18/16.
// Copyright (c) 2016 Sipper. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SBSConstants.h"
#import "SBSEventDispatcher.h"
#import "SBSSipMessage.h"

@class SBSAccount;
@class SBSCall;
@class SBSEndpoint;
@class SBSEventBinding;
@class SBSMediaDescription;
@class SBSNameAddressPair;
@class SBSRingtone;
@class SBSSipMessage;

extern NSString *_Nonnull const SBSCallEventStateChange;
extern NSString *_Nonnull const SBSCallEventReceivedMessage;
extern NSString *_Nonnull const SBSCallEventMuteStateChange;
extern NSString *_Nonnull const SBSCallEventHoldStateChange;
extern NSString *_Nonnull const SBSCallEventMediaDescriptionChange;
extern NSString *_Nonnull const SBSCallEventEnd;

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
   *  Call is currently being setup, and no underlying call exists in the SIP stack
   */
  SBSCallStatePending,
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
   *  The call is not ready to perform this action
   */
  SBSCallErrorCallNotReady,
  /**
   *  The call is not an outgoing call and can't be conneted this way
   */
  SBSCallErrorInvalidOperation,
  /**
   *  There was a transport error while attempting to handle a SIP message
   */
  SBSCallErrorTransportFailure,
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
   *  Unable to send the DTMF tones
   */
  SBSCallErrorCannotSendDTMF,
  /**
   *  Unable to send a re-invite for the call
   */
  SBSCallErrorCannotReinvite
};

#pragma mark - Events

@interface SBSCallEvent : SBSEvent

/**
 * The call that this event corresponds to
 *
 * Events contain a strong reference to the call that triggered them so that listeners can easily
 * access call information without needing to create a weak reference to the call outside of their
 * observers.
 */
@property(readonly, strong, nonnull, nonatomic) SBSCall *call;

@end

@interface SBSCallReceivedMessageEvent : SBSCallEvent

/**
 * The message that the event contains
 *
 * This is the only opportunity to get access to the message that the call has received. The message
 * contains headers, methods, and more
 */
@property(readonly, strong, nonnull, nonatomic) SBSSipMessage *message;

@end

@interface SBSCallMediaUpdatedEvent : SBSCallEvent

/**
 * The descriptions of available media on the call
 *
 * This property reflects the most up-to-date information about hte media channels available on the call
 * and can be used to determine if, for example, video/audio/text are supported
 */
@property(readonly, strong, nonnull, nonatomic) NSArray<SBSMediaDescription *> *media;

@end

@interface SBSCallEndedEvent : SBSCallEvent

/**
 * The error that caused the call to end, if any
 */
@property(readonly, strong, nonnull, nonatomic) NSError *error;

@end

#pragma mark - Closures

typedef void (^SBSCallEventListener)(SBSCallEvent * _Nonnull);

typedef void (^SBSActionCallbackBlock)(BOOL successful, NSError * _Nullable);

#pragma mark - Call

@interface SBSCall : NSObject

/**
 * Unique identifier for the call
 */
@property (strong, nonatomic, nonnull, readonly) NSUUID *uuid;

/**
 * Description for the remote identity, taken from Remote-Party-ID
 */
@property (strong, nonatomic, nonnull, readonly) SBSNameAddressPair *remote;

/**
 * If an outgoing call, contains the destination that was dialed
 */
@property (strong, nonatomic, nonnull, readonly) NSString *destination;

/**
 * If an outgoing call, contains all of the initial headers to add to the outgoing call
 */
@property (strong, nonatomic, nonnull, readonly) NSDictionary<NSString *, NSString *> *headers;

/**
 * Controls if media for the current call should be muted or not
 */
@property (nonatomic) BOOL muted;

/**
 * The last message received for this call
 */
@property (strong, nonatomic, nullable, readonly) SBSSipMessage *lastMessage;

/**
 * The direction of the call, can either be inbound or outbound
 */
@property(nonatomic, readonly) SBSCallDirection direction;

/**
 * The current state that the call is in
 */
@property(nonatomic, readonly) SBSCallState state;

/**
 * The hold state for the call
 */
@property(nonatomic, readonly) SBSHoldState holdState;

/**
 * Array of media attached to the call
 */
@property(strong, nonnull, nonatomic, readonly) NSArray<SBSMediaDescription *> *media;

/**
 * The ringtone to play on this call
 */
@property(strong, nonatomic, nonnull) SBSRingtone *ringtone;

/**
 * The endpoint that this acount is connected to
 */
@property(weak, nonatomic, nullable, readonly) SBSEndpoint *endpoint;

/**
 * The account that this call belongs to
 */
@property(weak, nonatomic, nullable, readonly) SBSAccount *account;

/**
 * Timestamp that this call initially went into an non-pending state
 */
@property(strong, nonatomic, nullable, readonly) NSDate *startedAt;

/**
 * Timestamp that this call initially went into an active state (for determining duration)
 */
@property(strong, nonatomic, nullable, readonly) NSDate *activeAt;

/**
 * Timestamp that this call initially went into an disconnected state
 */
@property(strong, nonatomic, nullable, readonly) NSDate *completedAt;

/**
 * Places the call associate with this instance
 *
 * SIP calls are not placed when they're created from the account. This method needs to be called in order
 * to send the INVITE request
 *
 * @param callback callback to invoke on completion
 */
- (void)connectWithCompletion:(SBSActionCallbackBlock _Nullable)callback;

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
- (void)answerWithCompletion:(SBSActionCallbackBlock _Nullable)callback;

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
- (void)answerWithStatus:(SBSStatusCode)code completion:(SBSActionCallbackBlock _Nullable)callback;

/**
 * Hangs up this call with a 603 Decline status code
 *
 * This method can be invoked on a call that is not currently answered. If it is, the call will be
 * explicitly declined.
 *
 * @param callback callback to invoke on success
 */
- (void)hangupWithCompletion:(SBSActionCallbackBlock _Nullable)callback;

/**
 * Hangs up this call with the requested status code
 *
 * This method can be invoked on a call that is not currently answered. If it is, the call will be
 * explicitly declined.
 *
 * @param code     the status code to respond with
 * @param callback callback to invoke on success
 */
- (void)hangupWithStatus:(SBSStatusCode)code completion:(SBSActionCallbackBlock _Nullable)callback;

/**
 * Places the call on hold
 *
 * Note that holds are not guaranteed to work. They require the endpoint to support parking the call,
 * and need to wait for acceptance of the park status. As a result, hold's are required to function
 * asynchronously.
 *
 * @param callback a callback that will be invoked when the hold response is sent
 */
- (void)holdWithCallback:(SBSActionCallbackBlock _Nullable)callback;

/**
 * Unholds the call if it's currently on hold
 *
 * If the call is not currently on hold, this is a no-op. Note that you can't unhold a call on which
 * hold hasn't been confirmed. You can verify if you're in a local hold by checking the aggregate
 * mediaState property on a call
 *
 * @param callback a callback that will be invoked when the call is reinvited
 */
- (void)unholdWithCallback:(SBSActionCallbackBlock _Nullable)callback;

/**
 * Sends a re-invite to the active call
 *
 * The purpose of this method is to attempt to update the contact destination for a live call, due to
 * (for example) an address change.
 *
 * @param callback a callback that will be invoked when the call is reinvited
 */
- (void)reinviteWithCallback:(SBSActionCallbackBlock _Nullable)callback;

/**
 * Sends the requested digits as DTMF tones
 *
 * Callers can pass any number of digits as a string to this method. Each digit will be sent individually
 * to the remote.
 *
 * @param digits the digits to send to the remote
 * @param callback a callback that will be invoked when the DTMF is sent
 */
- (void)sendDigits:(NSString *_Nullable)digits completion:(SBSActionCallbackBlock _Nullable)callback;

/**
 * Sends a SIP REFER message to direct the call to the given destination
 *
 * @param destination the new destination to send the call to
 * @param callback    a callback to invoke when the REFER is sent
 */
- (void)referTo:(NSString *_Nullable)destination completion:(SBSActionCallbackBlock _Nullable)callback;

/**
 * Adds a new target/action pair to the listeners for this call
 *
 * Multiple listeners can be added to a call, and they will be invoked in the order that they're registered
 * with the dispatcher
 *
 * @param event    the event to invoke the target for
 * @param target   the target to invoke on a new event
 * @param selector selector on the target to invoke
 * @return a binding that can be used to remove the listener
 */
- (SBSEventBinding *_Nonnull)addListenerForEvent:(NSString *_Nonnull)event target:(id _Nonnull)target action:(SEL _Nonnull)selector;

/**
 * Adds a new block as a listener for call events on this call
 *
 * Multiple listeners can be added to a call, and they will be invoked in the order that they're registered
 * with the dispatcher
 *
 * @param event the event to listen to
 * @param block the block to invoke for the event
 * @return a binding that can be used to remove the listener
 */
- (SBSEventBinding *_Nonnull)addListenerForEvent:(NSString *_Nonnull)event block:(SBSCallEventListener _Nonnull)block;

/**
 * Removes a previously registered listener
 *
 * This method attempts to safely remove a previously registered binding from an event type
 * on the call
 *
 * @param binding the binding that was returned from addTarget
 */
- (void)removeBinding:(SBSEventBinding *_Nonnull)binding;

@end
