//
//  SBSCall.mm
//  Sipper
//
//  Created by Colin Morelli on 4/21/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSCall+Internal.h"

#import <pjsua.h>
#import <pjsua-lib/pjsua_internal.h>

#import "NSString+PJString.h"
#import "NSError+SipperError.h"

#import "SBSAccount.h"
#import "SBSEndpointConfiguration.h"
#import "SBSEventDispatcher.h"
#import "SBSMediaDescription.h"
#import "SBSNameAddressPair.h"
#import "SBSEndpoint.h"
#import "SBSTargetActionEventListener+Internal.h"
#import "SBSBlockEventListener+Internal.h"
#import "SBSRingtonePlayer.h"

NSString * const CallErrorDomain = @"sipper.account.call";
NSString * const SBSCallEventStateChange = @"call.state.changed";
NSString * const SBSCallEventReceivedMessage = @"call.state.received";

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

@interface SBSCall ()

@property (strong, nonatomic) NSMutableDictionary *headers;
@property (strong, nonatomic) SBSEventDispatcher *dispatcher;
@property (strong, nonatomic) SBSRingtonePlayer *player;
@property (nonatomic) pjsip_transport *transport;

@end

@implementation SBSCall

//------------------------------------------------------------------------------

- (instancetype)initWithAccount:(SBSAccount *)account callId:(pjsua_call_id)callId direction:(SBSCallDirection)direction {
  if (self = [super init]) {
    _uuid = [NSUUID UUID];
    _account = account;
    _id = callId;
    _direction = direction;
    _state = SBSCallStateSetup;
    _media = [[NSArray alloc] init];
    _headers = [[NSMutableDictionary alloc] init];
    _dispatcher = [[SBSEventDispatcher alloc] init];
    
    [self handleAssociateWithCall:callId];
  }
  
  return self;
}

//------------------------------------------------------------------------------

- (void)dealloc {
  
  // Clear out the reference to ourselves
  if (_id > 0) {
    pjsua_call_set_user_data((int) _id, NULL);
  }
  
  // Shouldn't happen, but let's just make sure to prevent leaks
  if (_transport) {
    pjsip_transport_dec_ref(_transport);
    _transport = NULL;
  }
}

//------------------------------------------------------------------------------

- (NSString *)valueForHeader:(NSString *)header {
  return _headers[[header lowercaseString]];
}

//------------------------------------------------------------------------------

- (void)answerWithCompletion:(void (^)(BOOL, NSError *))callback {
  [self answerWithStatus:SBSStatusCodeOk completion:callback];
}

//------------------------------------------------------------------------------

- (void)answerWithStatus:(SBSStatusCode)code completion:(void (^ _Nullable)(BOOL, NSError *))callback {
  if (callback == nil) {
    callback = ^(BOOL success, NSError *error) { };
  }
  
  if ([self validateCallAndFailIfNecessaryWithCompletion:callback]) {
    return;
  }
  
  // Stop the ringtone if it's currently playing and we have a response code
  // that justifies stopping it
  if (code != SBSStatusCodeProgress && code != SBSStatusCodeRinging) {
    [self.player stop];
  }
  
  [self.account.endpoint performAsync:^{
    pj_status_t status = pjsua_call_answer((int) _id, (pjsip_status_code) code, NULL, NULL);
    
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

- (void)hangupWithCompletion:(void (^)(BOOL, NSError * _Nullable))callback {
  [self hangupWithStatus:SBSStatusCodeDecline completion:callback];
}

//------------------------------------------------------------------------------

- (void)hangupWithStatus:(SBSStatusCode)code completion:(void (^)(BOOL, NSError * _Nullable))callback {
  if (callback == nil) {
    callback = ^(BOOL success, NSError *error) { };
  }
  
  if ([self validateCallAndFailIfNecessaryWithCompletion:callback]) {
    return;
  }
  
  // Stop the ringtone if it's currently playing
  [self.player stop];
  
  // Answer the call in the appropriate thread (it doesn't happen immediately)
  [self.account.endpoint performAsync:^{
    pj_status_t status = pjsua_call_hangup((int) _id, (pjsip_status_code) code, NULL, NULL);
    
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

- (void)holdWithCallback:(void (^)(BOOL, NSError * _Nullable))callback {
  if (callback == nil) {
    callback = ^(BOOL success, NSError *error) { };
  }
  
  if ([self validateCallAndFailIfNecessaryWithCompletion:callback]) {
    return;
  }
  
  [self.account.endpoint performAsync:^{
    pj_status_t status = pjsua_call_set_hold2((int) _id, 0, NULL);
    
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

- (void)unholdWithCallback:(void (^)(BOOL, NSError * _Nullable))callback {
  if (callback == nil) {
    callback = ^(BOOL success, NSError *error) { };
  }
  
  if ([self validateCallAndFailIfNecessaryWithCompletion:callback]) {
    return;
  }
  
  [self.account.endpoint performAsync:^{
    pjsua_call_setting setting;
    pjsua_call_setting_default(&setting);
    
    setting.flag = PJSUA_CALL_UNHOLD;
    pj_status_t status = pjsua_call_reinvite2((int) _id, &setting, NULL);
    
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

- (void)reinviteWithCallback:(void (^)(BOOL, NSError * _Nullable))callback {
  if (callback == nil) {
    callback = ^(BOOL success, NSError *error) { };
  }
  
  if ([self validateCallAndFailIfNecessaryWithCompletion:callback]) {
    return;
  }
  
  [self.account.endpoint performAsync:^{
    pjsua_call_setting setting;
    pjsua_call_setting_default(&setting);
    
//    setting.flag = PJSUA_CALL_UPDATE_CONTACT;
    pj_status_t status = pjsua_call_reinvite2((int) _id, &setting, NULL);
    
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

- (NSDictionary *)allHeaders {
  return [self.headers copy];
}

//------------------------------------------------------------------------------

- (void)setMuted:(BOOL)muted {
  _muted = muted;
  [self updateAudioPorts];
}

//------------------------------------------------------------------------------

- (void)sendDigits:(NSString *)digits {
  pj_str_t input_string = digits.pjString;
  pjsua_call_dial_dtmf((int) _id, &input_string);
}

//------------------------------------------------------------------------------

- (SBSEventBinding *)addListenerWithTarget:(id)target action:(SEL)action forEvent:(NSString *)event {
  return [self.dispatcher addEventListener:[SBSTargetActionEventListener listenerWithTarget:target action:action] forEvent:event];
}

//------------------------------------------------------------------------------

- (SBSEventBinding *)addListenerWithBlock:(SBSCallEventListener)block forEvent:(NSString *)event {
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

- (BOOL)validateCallAndFailIfNecessaryWithCompletion:(void (^)(BOOL, NSError * _Nullable))completion {
  if (_id >= 0) {
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
#pragma mark - Event Handlers
//------------------------------------------------------------------------------

- (void)handleFailureWithError:(NSError *)error {
  _state = SBSCallStateDisconnected;
  
  // TODO: FAILURE EVENT
  [self dispatchEvent:[SBSCallEvent eventWithName:SBSCallEventStateChange call:self]];
}

- (void)handleAssociateWithCall:(pjsua_call_id)callId {
  if (callId >= 0) {
    pjsua_call_set_user_data((int) callId, (__bridge void *)(self));
  }
  
  // Update the internal call identifier
  _id = callId;
  
  // And now perform a reconciliation
  [self handleCallStateChange];
  [self handleCallMediaStateChange];
}

- (void)handleCallStateChange {
  
  // If we don't have a valid call ID, then we're just in the setup state
  if (_id < 0) {
    return;
  }
  
  // Anything past here means we have a call ID
  pjsua_call_info info;
  pj_status_t status = pjsua_call_get_info((int) _id, &info);
  
  // Getting call info *will* fail when the call has been disconnected, so catch that
  // and update as appropriate. This is an unfortunate issue in pjsip that I don't
  // have a clean solution for yet
  if (status == PJSIP_ESESSIONTERMINATED) {
    _state = SBSCallStateDisconnected;
  } else if (status == PJ_SUCCESS) {
    _state = [self convertState:info.state];
  }
  
  // If the call state is not ringing, stop the ringtone player
  if (self.state != SBSCallStateEarly && self.state != SBSCallStateIncoming) {
    [self.player stop];
  }
  
  // If we're in an active state, update the call's timestamp
  if (_state == SBSCallStateActive) {
    _activeAt = [[NSDate alloc] init];
  }
  
  // And invoke the delegate method back on the main thread
  [self dispatchEvent:[SBSCallEvent eventWithName:SBSCallEventStateChange call:self]];
  
  // If we are now disconnected, release any transports we may have
  if (_state == SBSCallStateDisconnected) {
    if (_transport) {
      pjsip_transport_dec_ref(_transport);
      _transport = NULL;
    }
  }
}

//------------------------------------------------------------------------------

- (void)handleCallMediaStateChange {
  
  // If we don't have a valid call ID, then we're just in the setup state
  if (_id < 0) {
    return;
  }
  
  // Anything past here means we have a valid state
  pjsua_call_info info;
  pjsua_call_get_info((int) _id, &info);
  
  // Determine the hold state for the call
  SBSHoldState holdState = SBSHoldStateNone;
  NSMutableArray<SBSMediaDescription *> *descriptions = [[NSMutableArray alloc] init];
  
  // Calculate the aggregate media state
  for (int i = 0; i < info.media_cnt; i++) {
    pjsua_call_media_info media_info = info.media[i];
    SBSMediaState state = [self convertMediaState:media_info.status];
    SBSMediaDirection direction = [self convertMediaDirection:media_info.dir];
    SBSMediaType type = [self convertMediaType:media_info.type];
    
    SBSMediaDescription *description = [[SBSMediaDescription alloc] initWithMediaType:type direction:direction state:state];
    [descriptions addObject:description];
    
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
    [self reconcileMuteState:info];
    
    // TODO: MEDIA EVENTS
    // Fire the hold state delegate handler if the hold state changed
//    if (holdStateChanged && [self.delegate respondsToSelector:@selector(call:didChangeHoldState:)]) {
//      [self.delegate call:self didChangeHoldState:holdState];
//    }
//    
//    // Invoke the delegate handler here
//    if ([self.delegate respondsToSelector:@selector(call:didChangeMediaState:)]) {
//      [self.delegate call:self didChangeMediaState:_media];
//    }
  });
}

//------------------------------------------------------------------------------

- (void)handleTransactionStateChange:(pjsip_transaction *)transaction event:(pjsip_event * _Nonnull)event {
  
  // See if we should grab a handle to this transport
  if (_account.endpoint.configuration.preserveConnectionsForCalls) {
    if (transaction->transport != _transport) {
      if (_transport) {
        pjsip_transport_dec_ref(_transport);
      }
      
      pjsip_transport_add_ref(transaction->transport);
      _transport = transaction->transport;
    }
  }
  
  // Check and see if we had a transport error, and drop the call if so
  if (transaction->transport_err != PJ_SUCCESS) {
    pjsua_call_hangup((int) _id, PJSIP_SC_TSX_TRANSPORT_ERROR, NULL, NULL);
  }
  
  // If this is a response message from the remote, parse the response
  if (event->type == PJSIP_EVENT_TSX_STATE && event->body.tsx_state.type == PJSIP_EVENT_RX_MSG) {
    pjsip_rx_data *response = event->body.tsx_state.src.rdata;
    
    // Parse all of the headers out of the response message
    NSMutableDictionary *headers = [SBSCall headersFromMessage:response->msg_info.msg];
    
    // Set any headers that we didn't otherwise have
    [_headers addEntriesFromDictionary:headers];
    
    // Invoke the delegate method that we received a new response
    [self dispatchEvent:[SBSCallEvent eventWithName:SBSCallEventReceivedMessage call:self]];
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
#pragma mark - Media State
//------------------------------------------------------------------------------

- (void)updateAudioPorts {
  
  // Nothing to do if the call isn't active
  if (_id < 0) {
    return;
  }
  
  // Otherwise grab call info and reconcile
  pjsua_call_info info;
  pj_status_t status = pjsua_call_get_info((int) _id, &info);
  if (status != PJ_SUCCESS) {
    return;
  }
  
  // Reconcile the appropriate audio states
  [self reconcileMuteState:info];
}

//------------------------------------------------------------------------------

- (void)reconcileMuteState:(pjsua_call_info)info {
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
#pragma mark - Factory
//------------------------------------------------------------------------------

+ (instancetype)outgoingCallWithAccount:(SBSAccount *)account destination:(NSString *)destination headers:(NSDictionary<NSString *,NSString *> *)headers {
  SBSCall *call = [[SBSCall alloc] initWithAccount:account callId:-1 direction:SBSCallDirectionOutbound];
  
  if (headers != nil) {
    call.headers = [[NSMutableDictionary alloc] init];
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
      [call.headers setObject:obj forKey:[key lowercaseString]];
    }];
  }
  
  if (destination != nil) {
    call.remote = [SBSNameAddressPair nameAddressPairFromString:destination];
  }
  
  return call;
}

//------------------------------------------------------------------------------

+ (instancetype)incomingCallWithAccount:(SBSAccount *)account callId:(pjsua_call_id)callId data:(pjsip_rx_data *)data {
  SBSCall *call = [[SBSCall alloc] initWithAccount:account callId:callId direction:SBSCallDirectionInbound];
  pjsip_msg *msg = data->msg_info.msg;
  
  // Get a list of all headers
  call.headers = [self headersFromMessage:msg];
  
  // Check for from/to headers
  NSString *from = [call.headers valueForKey:@"from"];
  if (from != nil) {
    call.remote = [SBSNameAddressPair nameAddressPairFromString:from];
  }
  
  NSString *to = [call.headers valueForKey:@"to"];
  if (to != nil) {
    call.local = [SBSNameAddressPair nameAddressPairFromString:to];
  }
  
  return call;
}

//------------------------------------------------------------------------------

+ (NSMutableDictionary *)headersFromMessage:(pjsip_msg *)msg {
  NSMutableDictionary *headers = [[NSMutableDictionary alloc] init];
  
  pjsip_hdr *hdr = msg->hdr.next,
            *end = &msg->hdr;
  
  // Iterate over all of the headers, push to dictionary
  for (; hdr != end; hdr = hdr->next) {
    NSString *headerName = [NSString stringWithPJString:hdr->name];
    char value[512] = {0};
    
    // If we weren't able to read the string in 512 bytes... (we should fix this)
    if (hdr->vptr->print_on(hdr, value, 512) == -1) {
      continue;
    }
    
    // Always append the raw header value, even if we did something else above
    NSString *headerValue = [[NSString alloc] initWithCString:value encoding:NSUTF8StringEncoding];
    NSRange splitRange = [headerValue rangeOfString:@":"];
    
    // Strip out the header name from the value
    if (splitRange.location != NSNotFound) {
      headerValue = [[headerValue substringFromIndex:splitRange.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    
    [headers setObject:headerValue forKey:[headerName lowercaseString]];
  }
  
  return headers;
}

//------------------------------------------------------------------------------

+ (instancetype)fromCallId:(pjsua_call_id)callId {
  void *data = pjsua_call_get_user_data(callId);
  if (data == NULL) {
    return nil;
  }
  
  return (__bridge SBSCall *)data;
}

//------------------------------------------------------------------------------
#pragma mark - Converters
//------------------------------------------------------------------------------

- (SBSCallState)convertState:(pjsip_inv_state)state {
  switch (state) {
    case PJSIP_INV_STATE_NULL:
      return SBSCallStateUnknown;
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
}

- (SBSMediaState)convertMediaState:(pjsua_call_media_status)status {
  switch (status) {
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

- (SBSMediaType)convertMediaType:(pjmedia_type)type {
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

- (SBSMediaDirection)convertMediaDirection:(pjmedia_dir)direction {
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

@end
