//
// Created by Colin Morelli on 9/18/16.
// Copyright (c) 2016 Sipper. All rights reserved.
//

#import "SBSCall+Internal.h"

#import <pjsua.h>

#import "NSString+PJString.h"
#import "NSError+SipperError.h"

#import "SBSAccount.h"
#import "SBSAccount+Internal.h"
#import "SBSAccountConfiguration.h"
#import "SBSBlockEventListener+Internal.h"
#import "SBSEndpointConfiguration.h"
#import "SBSEndpoint.h"
#import "SBSMediaDescription.h"
#import "SBSNameAddressPair.h"
#import "SBSRingtonePlayer.h"
#import "SBSSipRequestMessage.h"
#import "SBSSipResponseMessage.h"
#import "SBSSipUtilities+Internal.h"
#import "SBSTargetActionEventListener+Internal.h"

static NSString *const CallErrorDomain = @"sipper.error.call";

#pragma mark - Forward Declarations

static SBSCallState convertState(pjsip_inv_state);
static SBSMediaState convertMediaState(pjsua_call_media_status);
static SBSMediaType convertMediaType(pjmedia_type);
static SBSMediaDirection convertMediaDirection(pjmedia_dir);

#pragma mark - Events

NSString *const SBSCallEventStateChange = @"call.state.changed";
NSString *const SBSCallEventHoldStateChange = @"call.hold_state.changed";
NSString *const SBSCallEventReceivedMessage = @"call.message.received";
NSString *const SBSCallEventMuteStateChange = @"call.mute_state.changed";
NSString *const SBSCallEventEnd = @"call.ended";

@implementation SBSCallEvent

- (instancetype)initWithEventName:(NSString *)name call:(SBSCall *)call {
  if (self = [super initWithName:name]) {
    _call = call;
  }
  
  return self;
}

+ (SBSCallEvent *)eventWithName:(NSString *)name call:(SBSCall *)call {
  return [[SBSCallEvent alloc] initWithEventName:name call:call];
}

@end

@implementation SBSCallReceivedMessageEvent

- (instancetype)initWithEventName:(NSString *)name call:(SBSCall *)call message:(SBSSipMessage *)message {
  if (self = [super initWithEventName:name call:call]) {
    _message = message;
  }
  
  return self;
}

+ (SBSCallReceivedMessageEvent *)eventWithName:(NSString *)name call:(SBSCall *)call message:(SBSSipMessage *)message {
  return [[SBSCallReceivedMessageEvent alloc] initWithEventName:name call:call message:message];
}

@end

@implementation SBSCallMediaUpdatedEvent

- (instancetype)initWithEventName:(NSString *)name call:(SBSCall *)call media:(NSArray<SBSMediaDescription *> *)media {
  if (self = [super initWithEventName:name call:call]) {
    _media = media;
  }
  
  return self;
}

+ (SBSCallMediaUpdatedEvent *)eventWithName:(NSString *)name call:(SBSCall *)call media:(NSArray<SBSMediaDescription *> *)media {
  return [[SBSCallMediaUpdatedEvent alloc] initWithEventName:name call:call media:media];
}

@end

@implementation SBSCallEndedEvent

- (instancetype)initWithEventName:(NSString *)name call:(SBSCall *)call error:(NSError *)error {
  if (self = [super initWithEventName:name call:call]) {
    _error = error;
  }
  
  return self;
}

+ (SBSCallEndedEvent *)eventWithName:(NSString *)name call:(SBSCall *)call error:(NSError *)error {
  return [[SBSCallEndedEvent alloc] initWithEventName:name call:call error:error];
}

@end

#pragma mark - Call

@interface SBSCall ()

@property (nonatomic, nullable) pjsip_transport *transport;
@property (nonatomic, nonnull, strong) SBSEventDispatcher *dispatcher;
@property (nonatomic, nullable, strong) SBSRingtonePlayer *player;
@property (nonatomic, nullable, strong) NSError *error;
@property (nonatomic) BOOL ended;

@end

@implementation SBSCall

//------------------------------------------------------------------------------

- (instancetype)initOutgoingWithEndpoint:(SBSEndpoint *)endpoint
                                 account:(SBSAccount *)account
                             destination:(NSString *)destination
                                 headers:(NSDictionary<NSString *, NSString *> *)headers {
  if (self = [super init]) {
    _endpoint = endpoint;
    _account = account;
    _destination = destination;
    _headers = headers;
    _ended = NO;
  }
  
  return self;
}

//------------------------------------------------------------------------------

- (instancetype)initIncomingWithEndpoint:(SBSEndpoint *)endpoint
                                 account:(SBSAccount *)account
                                  remote:(SBSNameAddressPair *)remote
                                  callId:(pjsua_call_id)callId {
  if (self = [super init]) {
    _endpoint = endpoint;
    _account = account;
    _remote = remote;
    _ended = NO;
    
    [self attachCall:callId];
  }
  
  return self;
}

//------------------------------------------------------------------------------

- (void)dealloc {
  
  // Clear out the reference to ourselves
  if (_callId > 0) {
    
    // Check if we were de-alloced before the call ended, in which case let's hang up
    if (_state != SBSCallStateDisconnected) {
      pjsua_call_hangup(_callId, PJSIP_SC_DECLINE, NULL, NULL);
    }
    
    // Make sure we don't store invalid references in PJSIP
    void *user_data = pjsua_call_get_user_data(_callId);
    if (user_data == (__bridge void *) self) {
      pjsua_call_set_user_data(_callId, NULL);
    }
  }
  
  // Release our hold on the transport that this call is using
  if (_transport) {
    pjsip_transport_dec_ref(_transport);
    _transport = NULL;
  }
}

//------------------------------------------------------------------------------

- (void)ring {
  if (self.ringtone == nil) {
    return;
  }
  
  // Start playing the ringtone - note that we don't worry about audio categories here. That is
  // managed by the endpoint, to ensure we don't clobber audio sessions that would be required by
  // other active calls.
  self.player = [[SBSRingtonePlayer alloc] initWithRingtone:self.ringtone];
  [self.player play];
}

//------------------------------------------------------------------------------

- (void)connectWithCompletion:(void (^)(BOOL, NSError *_Nullable))callback {
  if (callback == nil) {
    callback = ^(BOOL success, NSError *error) {
    };
  }
  
  [self.endpoint performAsync:^{
    pjsua_call_setting setting;
    pjsua_call_setting_default(&setting);
    
    // Create a temporary pool to allocate default headers from
    pj_caching_pool cp;
    pj_caching_pool_init(&cp, &pj_pool_factory_default_policy, 0);
    pj_pool_t *pool = pj_pool_create(&cp.factory, "header", 1000, 1000, NULL);
    
    // Append any required default headers
    pjsua_msg_data msg_data;
    pjsua_msg_data_init(&msg_data);
    
    // Append any default headers
    if (_headers != nil) {
      [_headers enumerateKeysAndObjectsUsingBlock:^(NSString *_Nonnull key, NSString *_Nonnull obj, BOOL *_Nonnull stop) {
        pj_str_t name = key.pjString;
        pj_str_t value = obj.pjString;
        pj_list_push_back((pjsip_hdr *) &msg_data.hdr_list, pjsip_generic_string_hdr_create(pool, &name, &value));
      }];
    }
    
    // Create the call now
    pjsua_call_id id;
    pj_str_t dst = _remote.uri.description.pjString;
    pj_status_t status = pjsua_call_make_call(_account.accountId, &dst, &setting, NULL, &msg_data, &id);
    
    // Discard the pool to cleanup
    pj_pool_release(pool);
    
    // If we couldn't setup the call, fail it now
    if (status != PJ_SUCCESS) {
      NSError *error = [NSError ErrorWithUnderlying:nil
                            localizedDescriptionKey:NSLocalizedString(@"Could not create outbound call", nil)
                        localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                        errorDomain:CallErrorDomain
                                          errorCode:SBSCallErrorInvalidOperation];
      
      [self endCallWithError:error];
    } else {
      [self attachCall:id];
    }
  }];
}

//------------------------------------------------------------------------------

- (void)answerWithCompletion:(void (^)(BOOL, NSError *))callback {
  [self answerWithStatus:SBSStatusCodeOk completion:callback];
}

//------------------------------------------------------------------------------

- (void)answerWithStatus:(SBSStatusCode)code completion:(void (^ _Nullable)(BOOL, NSError *))callback {
  if (callback == nil) {
    callback = ^(BOOL success, NSError *error) {
    };
  }
  
  if ([self validateCallAndFailIfNecessaryWithCompletion:callback]) {
    return;
  }
  
  // Stop the ringtone if it's currently playing and we have a response code
  // that justifies stopping it
  if (code != SBSStatusCodeProgress && code != SBSStatusCodeRinging) {
    [self.player stop];
  }
  
  [self.endpoint performAsync:^{
    pj_status_t status = pjsua_call_answer(_callId, (pjsip_status_code) code, NULL, NULL);
    
    // Execute the remaining method back in the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
      if (status == PJ_SUCCESS) {
        callback(YES, nil);
        return;
      }
      
      // Made it here, we got a non-successful response code
      NSError *error = [NSError ErrorWithUnderlying:nil
                            localizedDescriptionKey:NSLocalizedString(@"Could not answer the call", nil)
                        localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                        errorDomain:CallErrorDomain
                                          errorCode:SBSCallErrorCannotAnswer];
      callback(NO, error);
    });
  }];
}

//------------------------------------------------------------------------------

- (void)hangupWithCompletion:(void (^)(BOOL, NSError *_Nullable))callback {
  [self hangupWithStatus:SBSStatusCodeDecline completion:callback];
}

//------------------------------------------------------------------------------

- (void)hangupWithStatus:(SBSStatusCode)code completion:(void (^)(BOOL, NSError *_Nullable))callback {
  if (callback == nil) {
    callback = ^(BOOL success, NSError *error) {
    };
  }
  
  if ([self validateCallAndFailIfNecessaryWithCompletion:callback]) {
    return;
  }
  
  // Stop the ringtone if it's currently playing
  [self.player stop];
  
  // Answer the call in the appropriate thread (it doesn't happen immediately)
  [self.endpoint performAsync:^{
    pj_status_t status = pjsua_call_hangup(_callId, (pjsip_status_code) code, NULL, NULL);
    
    // Execute the remaining method back in the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
      if (status == PJ_SUCCESS) {
        callback(YES, nil);
        return;
      }
      
      // Made it here, we got a non-successful response code
      NSError *error = [NSError ErrorWithUnderlying:nil
                            localizedDescriptionKey:NSLocalizedString(@"Could not hangup the call", nil)
                        localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                        errorDomain:CallErrorDomain
                                          errorCode:SBSCallErrorCannotHangup];
      callback(NO, error);
    });
  }];
}

//------------------------------------------------------------------------------

- (void)holdWithCallback:(void (^)(BOOL, NSError *_Nullable))callback {
  if (callback == nil) {
    callback = ^(BOOL success, NSError *error) {
    };
  }
  
  if ([self validateCallAndFailIfNecessaryWithCompletion:callback]) {
    return;
  }
  
  [self.endpoint performAsync:^{
    pj_status_t status = pjsua_call_set_hold2(_callId, 0, NULL);
    
    // Execute the remaining method back in the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
      if (status == PJ_SUCCESS) {
        callback(YES, nil);
        return;
      }
      
      // Made it here, we got a non-successful response code
      NSError *error = [NSError ErrorWithUnderlying:nil
                            localizedDescriptionKey:NSLocalizedString(@"Could not hold the call", nil)
                        localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                        errorDomain:CallErrorDomain
                                          errorCode:SBSCallErrorCannotHold];
      callback(NO, error);
    });
  }];
}

//------------------------------------------------------------------------------

- (void)unholdWithCallback:(void (^)(BOOL, NSError *_Nullable))callback {
  if (callback == nil) {
    callback = ^(BOOL success, NSError *error) {
    };
  }
  
  if ([self validateCallAndFailIfNecessaryWithCompletion:callback]) {
    return;
  }
  
  [self.endpoint performAsync:^{
    pjsua_call_setting setting;
    pjsua_call_setting_default(&setting);
    
    setting.flag = PJSUA_CALL_UNHOLD;
    pj_status_t status = pjsua_call_reinvite2(_callId, &setting, NULL);
    
    // Execute the remaining method back in the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
      if (status == PJ_SUCCESS) {
        callback(YES, nil);
        return;
      }
      
      // Made it here, we got a non-successful response code
      NSError *error = [NSError ErrorWithUnderlying:nil
                            localizedDescriptionKey:NSLocalizedString(@"Could not unhold the call", nil)
                        localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                        errorDomain:CallErrorDomain
                                          errorCode:SBSCallErrorCannotUnhold];
      callback(NO, error);
    });
  }];
}

//------------------------------------------------------------------------------

- (void)reinviteWithCallback:(void (^)(BOOL, NSError *_Nullable))callback {
  if (callback == nil) {
    callback = ^(BOOL success, NSError *error) {
    };
  }
  
  if ([self validateCallAndFailIfNecessaryWithCompletion:callback]) {
    return;
  }
  
  [self.endpoint performAsync:^{
    pjsua_call_setting setting;
    pjsua_call_setting_default(&setting);
    pj_status_t status = pjsua_call_reinvite2(_callId, &setting, NULL);
    
    // Execute the remaining method back in the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
      if (status == PJ_SUCCESS) {
        callback(YES, nil);
        return;
      }
      
      // Made it here, we got a non-successful response code
      NSError *error = [NSError ErrorWithUnderlying:nil
                            localizedDescriptionKey:NSLocalizedString(@"Could not reinvite the call", nil)
                        localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                        errorDomain:CallErrorDomain
                                          errorCode:SBSCallErrorCannotUnhold];
      callback(NO, error);
    });
  }];
}

//------------------------------------------------------------------------------

- (void)setMuted:(BOOL)muted {
  _muted = muted;
  
  [self.endpoint performAsync:^{
    [self updateMuteState];
    
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.dispatcher dispatchEvent:[SBSCallEvent eventWithName:SBSCallEventMuteStateChange call:self]];
    });
  }];
}

//------------------------------------------------------------------------------

- (void)sendDigits:(NSString *)digits completion:(void (^ _Nullable)(BOOL, NSError *_Nullable))callback {
  if (callback == nil) {
    callback = ^(BOOL success, NSError *error) {
    };
  }
  
  if ([self validateCallAndFailIfNecessaryWithCompletion:callback]) {
    return;
  }
  
  [self.endpoint performAsync:^{
    pj_str_t input_string = digits.pjString;
    pj_status_t status = pjsua_call_dial_dtmf(_callId, &input_string);
    
    dispatch_async(dispatch_get_main_queue(), ^{
      if (status == PJ_SUCCESS) {
        callback(YES, nil);
        return;
      }
      
      // Made it here, we got a non-successful response code
      NSError *error = [NSError ErrorWithUnderlying:nil
                            localizedDescriptionKey:NSLocalizedString(@"Could not send DTMF for the call", nil)
                        localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                        errorDomain:CallErrorDomain
                                          errorCode:SBSCallErrorCannotSendDTMF];
      callback(NO, error);
    });
  }];
}

//------------------------------------------------------------------------------

- (void)referTo:(NSString *)destination completion:(void (^)(BOOL, NSError *_Nullable))callback {
  if (callback == nil) {
    callback = ^(BOOL success, NSError *error) {
    };
  }
  
  if ([self validateCallAndFailIfNecessaryWithCompletion:callback]) {
    return;
  }
  
  SBSSipURI *uri = [SBSSipURI sipUriWithString:destination];
  if (uri == nil) {
    destination = [NSString stringWithFormat:@"sip:%@@%@", destination, self.account.configuration.sipDomain];
  }
  
  [self.endpoint performAsync:^{
    pj_str_t destination_string = destination.pjString;
    pj_status_t status = pjsua_call_xfer(_callId, &destination_string, NULL);
    
    dispatch_async(dispatch_get_main_queue(), ^{
      if (status == PJ_SUCCESS) {
        callback(YES, nil);
        return;
      }
      
      // Made it here, we got a non-successful response code
      NSError *error = [NSError ErrorWithUnderlying:nil
                            localizedDescriptionKey:NSLocalizedString(@"Could not transfer call", nil)
                        localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                        errorDomain:CallErrorDomain
                                          errorCode:SBSCallErrorCannotUnhold];
      callback(NO, error);
    });
  }];
}

//------------------------------------------------------------------------------

- (SBSEventBinding *)addListenerForEvent:(NSString *)event target:(id)target action:(SEL)selector {
  return [self.dispatcher addEventListener:[SBSTargetActionEventListener listenerWithTarget:target action:selector] forEvent:event];
}

//------------------------------------------------------------------------------

- (SBSEventBinding *)addListenerForEvent:(NSString *)event block:(SBSCallEventListener)block {
  void (^ castBlock)(SBSEvent *) = (void (^)(SBSEvent *)) block;
  return [self.dispatcher addEventListener:[SBSBlockEventListener listenerWithBlock:castBlock] forEvent:event];
}

//------------------------------------------------------------------------------

- (void)removeBinding:(SBSEventBinding *)binding {
  [self.dispatcher removeBinding:binding];
}

//------------------------------------------------------------------------------

- (void)dispatchEvent:(SBSCallEvent *)event {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self.dispatcher dispatchEvent:event];
  });
}

//------------------------------------------------------------------------------

- (void)update {
  [self updateCallState];
  [self updateMediaState];
}

//------------------------------------------------------------------------------

- (void)updateCallState {
  
  // If we don't have a valid call ID, then we're just in the setup state
  if (_callId < 0) {
    return;
  }
  
  // Anything past here means we have a call ID
  pjsua_call_info info;
  pj_status_t status = pjsua_call_get_info(_callId, &info);
  
  // Getting call info *will* fail when the call has been disconnected, so catch that
  // and update as appropriate. This is an unfortunate issue in pjsip that I don't
  // have a clean solution for yet
  if (status == PJSIP_ESESSIONTERMINATED) {
    _state = SBSCallStateDisconnected;
  } else if (status == PJ_SUCCESS) {
    _state = convertState(info.state);
  }
  
  // If the call state is not ringing, stop the ringtone player
  if (self.state != SBSCallStateEarly && self.state != SBSCallStateIncoming) {
    [self.player stop];
  }
  
  // If we have any status, the call has started
  if (_state != SBSCallStatePending && _startedAt == nil) {
    _startedAt = [[NSDate alloc] init];
  }
  
  // If we're in an active state, update the call's timestamp
  if (_state == SBSCallStateActive && _activeAt == nil) {
    _activeAt = [[NSDate alloc] init];
  }
  
  // And invoke the delegate method back on the main thread
  [self dispatchEvent:[SBSCallEvent eventWithName:SBSCallEventStateChange call:self]];
  
  // If we are now disconnected, release any transports we may have and end the call
  if (_state == SBSCallStateDisconnected) {
    [self endCallWithError:nil];
    
    if (_transport) {
      pjsip_transport_dec_ref(_transport);
      _transport = NULL;
    }
  }
}

//------------------------------------------------------------------------------

- (void)updateMediaState {
  
  // If we don't have a valid call ID, then we're just in the setup state
  if (_callId < 0) {
    return;
  }
  
  // Anything past here means we have a valid state
  pjsua_call_info info;
  pjsua_call_get_info(_callId, &info);
  
  // Determine the hold state for the call
  SBSHoldState holdState = SBSHoldStateNone;
  NSMutableArray<SBSMediaDescription *> *descriptions = [[NSMutableArray alloc] init];
  
  // Calculate the aggregate media state
  for (int i = 0; i < info.media_cnt; i++) {
    pjsua_call_media_info media_info = info.media[i];
    SBSMediaState state = convertMediaState(media_info.status);
    SBSMediaDirection direction = convertMediaDirection(media_info.dir);
    SBSMediaType type = convertMediaType(media_info.type);
    
    // Append this media entry to our media descriptions array
    [descriptions addObject:[[SBSMediaDescription alloc] initWithMediaType:type direction:direction state:state]];
    
    if (holdState == SBSHoldStateNone) {
      if (state == SBSMediaStateLocalHold) {
        holdState = SBSHoldStateLocal;
      } else if (state == SBSMediaStateRemoteHold) {
        holdState = SBSHoldStateRemote;
      }
    }
  }
  
  // Updated media state for the call
  _media = [descriptions copy];
  
  // Determine if the hold state changed
  BOOL holdStateChanged = holdState != _holdState;
  _holdState = holdState;
  
  // Fire the event handler back on the main thread
  dispatch_async(dispatch_get_main_queue(), ^{
    
    // Reconcile the appropriate mute state
    [self updateMuteState:info];
    
    // Fire the hold state delegate handler if the hold state changed
    if (holdStateChanged) {
      [self dispatchEvent:[SBSCallEvent eventWithName:SBSCallEventHoldStateChange call:self]];
    }
    //
    //    // Invoke the delegate handler here
    //    if ([self.delegate respondsToSelector:@selector(call:didChangeMediaState:)]) {
    //      [self.delegate call:self didChangeMediaState:_media];
    //    }
  });
}

//------------------------------------------------------------------------------

- (void)updateMuteState {
  if (_callId < 0) {
    return;
  }
  
  // Otherwise grab call info and reconcile
  pjsua_call_info info;
  pj_status_t status = pjsua_call_get_info(_callId, &info);
  if (status != PJ_SUCCESS) {
    return;
  }
  
  // Reconcile the appropriate audio states
  [self updateMuteState:info];
}

//------------------------------------------------------------------------------

- (void)updateMuteState:(pjsua_call_info)info {
  for (unsigned i = 0; i < info.media_cnt; i++) {
    pjsua_call_media_info media = info.media[i];
    
    // If we have an active audio stream, connect the audio channels
    if (media.type == PJMEDIA_TYPE_AUDIO && media.status == PJSUA_CALL_MEDIA_ACTIVE) {
      pjsua_conf_connect(media.stream.aud.conf_slot, 0);
      
      // Only connect the microphone to the output if we're not muted
      if (!_muted) {
        pjsua_conf_connect(0, media.stream.aud.conf_slot);
      } else {
        pjsua_conf_disconnect(0, media.stream.aud.conf_slot);
      }
    }
  }
}

//------------------------------------------------------------------------------

- (void)attachCall:(pjsua_call_id)callId {
  _callId = callId;
  
  // Attach ourselves as the call's user data
  pjsua_call_set_user_data(callId, (__bridge void *) self);
  
  // Reconcile this object's state with the SIP call
  [self update];
}

//------------------------------------------------------------------------------

- (void)endCallWithError:(NSError *)error {
  SBSCallEndedEvent *event = [SBSCallEndedEvent eventWithName:SBSCallEventEnd call:self error:error];
  
  // Check to see if we need to update the call's state
  if (_state != SBSCallStateDisconnected) {
    _state = SBSCallStateDisconnected;
    [self dispatchEvent:[SBSCallEvent eventWithName:SBSCallEventStateChange call:self]];
  }
  
  // Now fire the call end event
  [self dispatchEvent:event];
}

//------------------------------------------------------------------------------

- (BOOL)validateCallAndFailIfNecessaryWithCompletion:(void (^)(BOOL, NSError *_Nullable))completion {
  if (_callId >= 0) {
    return NO;
  }
  
  NSError *error = [NSError ErrorWithUnderlying:nil
                        localizedDescriptionKey:NSLocalizedString(@"Call is not setup, cannot perform action", nil)
                    localizedFailureReasonError:NSLocalizedString(@"The requested action can only be performed when the call has left the setup state", nil)
                                    errorDomain:CallErrorDomain
                                      errorCode:SBSCallErrorCallNotReady];
  dispatch_async(dispatch_get_main_queue(), ^{
    completion(false, error);
  });
  
  return YES;
}

//------------------------------------------------------------------------------
// Event Listeners
//------------------------------------------------------------------------------

- (void)handleCallStateChange {
  [self updateCallState];
}

//------------------------------------------------------------------------------

- (void)handleCallMediaStateChange {
  [self updateMediaState];
}

//------------------------------------------------------------------------------

- (void)handleTransactionStateChange:(pjsip_transaction *)transaction event:(pjsip_event *)event {
  
  // See if we should grab a handle to this transport
  if (_account.endpoint.configuration.preserveConnectionsForCalls) {
    if (transaction->transport != _transport) {
      if (_transport) {
        pjsip_transport_dec_ref(_transport);
      }
      
      if (transaction->transport) {
        pjsip_transport_add_ref(transaction->transport);
      }
      
      _transport = transaction->transport;
    }
  }
  
  // Check and see if we had a transport error, and drop the call if so
  if (transaction->transport_err != PJ_SUCCESS) {
    pjsua_call_hangup(_callId, PJSIP_SC_TSX_TRANSPORT_ERROR, NULL, NULL);
    _error = [NSError ErrorWithUnderlying:nil
                  localizedDescriptionKey:NSLocalizedString(@"Transport failure during SIP message", nil)
              localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), transaction->transport_err]
                              errorDomain:CallErrorDomain
                                errorCode:SBSCallErrorTransportFailure];
  }
  
  // If this is a response message from the remote, parse the response
  if (event->type == PJSIP_EVENT_TSX_STATE && event->body.tsx_state.type == PJSIP_EVENT_RX_MSG) {
    pjsip_rx_data *response = event->body.tsx_state.src.rdata;
    
    // Parse all of the headers out of the response message
    NSDictionary *headers = [SBSSipUtilities headersFromMessage:response->msg_info.msg];
    
    // Check for response message types
    if (response->msg_info.msg->type == PJSIP_REQUEST_MSG) {
      int status_code = response->msg_info.msg->line.status.code;
      pj_str_t reason = response->msg_info.msg->line.status.reason;
      pj_str_t call_id = response->msg_info.cid->id;
      SBSSipResponseMessage *message = [[SBSSipResponseMessage alloc] initWithStatusCode:status_code
                                                                            statusReason:[NSString stringWithPJString:reason]
                                                                                  callId:[NSString stringWithPJString:call_id]
                                                                                 headers:headers];
      
      // Invoke the delegate method that we received a new response
      [self dispatchEvent:[SBSCallReceivedMessageEvent eventWithName:SBSCallEventReceivedMessage call:self message:message]];
      _lastMessage = message;
    } else {
      pj_str_t reason = response->msg_info.msg->line.req.method.name;
      pj_str_t call_id = response->msg_info.cid->id;
      SBSSipRequestMessage *message = [[SBSSipRequestMessage alloc] initWithMethod:[NSString stringWithPJString:reason]
                                                                            callId:[NSString stringWithPJString:call_id]
                                                                           headers:headers];
      
      // Invoke the delegate method that we received a new response
      [self dispatchEvent:[SBSCallReceivedMessageEvent eventWithName:SBSCallEventReceivedMessage call:self message:message]];
      _lastMessage = message;
    }
  }
}

//------------------------------------------------------------------------------

- (void)handleTransportStateChange:(pjsip_transport *)transport state:(pjsip_transport_state)state info:(const pjsip_transport_state_info *)info {
  // Because calls may hold onto their transport, we could run into issues where we want to explicitly shut down
  // a transport but the call is still holding onto it so it never gets destroyed. So, in this case, we listen to
  // shutdown attempts for the transport and release it, since shutdown will only be called if the user really wants
  // us to release this.
  if (state == PJSIP_TP_STATE_DESTROY || state == PJSIP_TP_STATE_SHUTDOWN) {
    if (_transport == transport) {
      pjsip_transport_dec_ref(_transport);
      _transport = NULL;
    }
  }
}

//------------------------------------------------------------------------------

+ (instancetype)outgoingCallWithAccount:(SBSAccount *)account destination:(NSString *)destination headers:(NSDictionary<NSString *,NSString *> *)headers {
  return [[SBSCall alloc] initOutgoingWithEndpoint:account.endpoint account:account destination:destination headers:headers];
}

//------------------------------------------------------------------------------

+ (instancetype)incomingCallWithAccount:(SBSAccount *)account callId:(pjsua_call_id)callId data:(pjsip_rx_data *)data {
  return [[SBSCall alloc] initIncomingWithEndpoint:account.endpoint account:account remote:nil callId:callId];
}

@end

#pragma mark - Static Methods

static SBSCallState convertState(pjsip_inv_state state) {
  switch (state) {
    case PJSIP_INV_STATE_NULL:
      return SBSCallStatePending;
    case PJSIP_INV_STATE_EARLY:
      return SBSCallStateEarly;
    case PJSIP_INV_STATE_CALLING:
      return SBSCallStateCalling;
    case PJSIP_INV_STATE_INCOMING:
      return SBSCallStateIncoming;
    case PJSIP_INV_STATE_CONFIRMED:
      return SBSCallStateActive;
    case PJSIP_INV_STATE_CONNECTING:
      return SBSCallStateConnecting;
    case PJSIP_INV_STATE_DISCONNECTED:
      return SBSCallStateDisconnected;
  }
};

static SBSMediaState convertMediaState(pjsua_call_media_status state) {
  switch (state) {
    case PJSUA_CALL_MEDIA_NONE:
      return SBSMediaStateNone;
    case PJSUA_CALL_MEDIA_ACTIVE:
      return SBSMediaStateActive;
    case PJSUA_CALL_MEDIA_LOCAL_HOLD:
      return SBSMediaStateLocalHold;
    case PJSUA_CALL_MEDIA_REMOTE_HOLD:
      return SBSMediaStateRemoteHold;
    case PJSUA_CALL_MEDIA_ERROR:
      return SBSMediaStateError;
  }
}

static SBSMediaType convertMediaType(pjmedia_type type) {
  switch (type) {
    case PJMEDIA_TYPE_NONE:
      return SBSMediaTypeNone;
    case PJMEDIA_TYPE_AUDIO:
      return SBSMediaTypeAudio;
    case PJMEDIA_TYPE_VIDEO:
      return SBSMediaTypeVideo;
    case PJMEDIA_TYPE_APPLICATION:
      return SBSMediaTypeApplication;
    case PJMEDIA_TYPE_UNKNOWN:
      return SBSMediaTypeUnknown;
  }
}

static SBSMediaDirection convertMediaDirection(pjmedia_dir direction) {
  switch (direction) {
    case PJMEDIA_DIR_NONE:
      return SBSMediaDirectionNone;
    case PJMEDIA_DIR_ENCODING:
      return SBSMediaDirectionOutbound;
    case PJMEDIA_DIR_DECODING:
      return SBSMediaDirectionInbound;
    case PJMEDIA_DIR_ENCODING_DECODING:
      return SBSMediaDirectionBidirectional;
  }
}

