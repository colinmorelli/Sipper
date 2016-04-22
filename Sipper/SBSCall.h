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
#import "SBSAccount.h"
#import "SBSConstants.h"
#import "SBSNameAddressPair.h"

@class SBSCall;

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

@protocol SBSCallDelegate

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
 * @param call   the call that was changed during this callback
 */
- (void)callDidChangeMediaState:(SBSCall * _Nonnull)call;

@end

@interface SBSCall : NSObject

/**
 * The SIP URI that the call originated from
 */
@property (nonatomic, nullable) SBSNameAddressPair *from;

/**
 * The SIP URI that the call is going to
 */
@property (nonatomic, nullable) SBSNameAddressPair *to;

/**
 * All SIP headers present on the call
 */
@property (strong, nonatomic, nonnull, readonly) NSDictionary *allHeaders;

/**
 * The account that this call belongs to
 */
@property (strong, nonatomic, nonnull, readonly) SBSAccount *account;

/**
 * The direction of the call, can either be inbound or outbound
 */
@property (nonatomic, readonly) SBSCallDirection direction;

/**
 * The current state that the call is in
 */
@property (nonatomic, readonly) SBSCallState state;

/**
 * Delegate to receive call events
 */
@property (nonatomic, nullable) id<SBSCallDelegate> delegate;

/**
 * Answers the call with a 200 OK status code
 *
 * This is a convenience method for the alternative ANSWER implementation that takes a status code. 
 * Alternative methods can be used to send pre-media to the caller. 
 *
 * You probably want to have a delegate set before calling this method.
 */
- (void)answer;

/**
 * Answers the call with the requested status code
 *
 * You probably want to have a delegate set before calling this method. You won't receive delegate
 * methods until you do.
 *
 * @param code the status code to answer the call with
 */
- (void)answerWithStatus:(SBSStatusCode)code;

/**
 * Hangs up the current call
 *
 * This method can be invoked on a call that is not currently answered. If it is, the call will be 
 * rejected by the remote.
 */
- (void)hangup;

/**
 * Returns a value for the named header
 *
 * @param header the name of the header to get the value for (case insensitive)
 * @return the header's value, if present
 */
- (NSString * _Nullable)valueForHeader:(NSString * _Nonnull)header;

@end

#endif