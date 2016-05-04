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
#import "SBSMediaDescription.h"
#import "SBSNameAddressPair.h"
#import "SBSEndpoint.h"
#import "SBSRingtonePlayer.h"

static NSString * const CallErrorDomain = @"sipper.account.call";

@interface SBSCall ()

@property (strong, nonatomic) NSMutableDictionary *headers;
@property (strong, nonatomic) SBSRingtonePlayer *player;

@end

@implementation SBSCall

//------------------------------------------------------------------------------

- (instancetype)initWithAccount:(SBSAccount *)account callId:(pjsua_call_id)callId direction:(SBSCallDirection)direction {
  if (self = [super init]) {
    _account = account;
    _id = callId;
    _direction = direction;
    _media = [[NSArray alloc] init];
    _headers = [[NSMutableDictionary alloc] init];
    
    [self prepare];
  }
  
  return self;
}

//------------------------------------------------------------------------------

- (void)prepare {
  pjsua_call_set_user_data((int) _id, (__bridge void *)(self));
  
  // Get the current call state to save on the call instance - always called immediately
  [self handleCallStateChange];
  
  // Also make sure we've updated to the correct media settings
  [self handleCallMediaStateChange];
}

//------------------------------------------------------------------------------

- (void)dealloc {
  pjsua_call_set_user_data((int) _id, NULL);
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

- (NSString *)valueForHeader:(NSString *)header {
  return self.headers[header];
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
#pragma mark - Event Handlers
//------------------------------------------------------------------------------

- (void)handleCallStateChange {
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
  
  // And invoke the delegate method back on the main thread
  dispatch_async(dispatch_get_main_queue(), ^{
    if ([self.delegate respondsToSelector:@selector(call:didChangeState:)]) {
      [self.delegate call:self didChangeState:_state];
    }
  });
}

//------------------------------------------------------------------------------

- (void)handleCallMediaStateChange {
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
  }
  
  // Updated media state for the call
  _media = [descriptions copy];
  
  // Determine if the hold state changed
  _holdState = holdState;
  BOOL holdStateChanged = holdState != _holdState;
  
  // Fire the event handler back on the main thread
  dispatch_async(dispatch_get_main_queue(), ^{
    
    // Reconcile the appropriate mute state
    [self reconcileMuteState:info];
    
    // Fire the hold state delegate handler if the hold state changed
    if (holdStateChanged && [self.delegate respondsToSelector:@selector(call:didChangeHoldState:)]) {
      [self.delegate call:self didChangeHoldState:holdState];
    }
    
    // Invoke the delegate handler here
    if ([self.delegate respondsToSelector:@selector(call:didChangeMediaState:)]) {
      [self.delegate call:self didChangeMediaState:_media];
    }
  });
}

//------------------------------------------------------------------------------

- (void)handleTransactionStateChange:(pjsip_transaction *)transaction {
  
  // Check and see if we had a transport error, and drop the call if so
  if (transaction->transport_err != PJ_SUCCESS) {
    pjsua_call_hangup((int) _id, PJSIP_SC_TSX_TRANSPORT_ERROR, NULL, NULL);
  }
}

//------------------------------------------------------------------------------
#pragma mark - Media State
//------------------------------------------------------------------------------

- (void)updateAudioPorts {
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

+ (instancetype)outgoingCallWithAccount:(SBSAccount *)account callId:(pjsua_call_id)callId {
  SBSCall *call = [[SBSCall alloc] initWithAccount:account callId:callId direction:SBSCallDirectionOutbound];
  pjsip_inv_session *inv = pjsua_var.calls[callId].inv;
  pjsip_msg *msg = inv->invite_tsx->last_tx->msg;
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
    
    [call.headers setObject:headerValue forKey:[headerName lowercaseString]];
  }
  
  // Check for from/to headers
  NSString *from = [call.headers valueForKey:@"from"];
  if (from != nil) {
    call.local = [SBSNameAddressPair nameAddressPairFromString:from];
  }
  
  NSString *to = [call.headers valueForKey:@"to"];
  if (to != nil) {
    call.remote = [SBSNameAddressPair nameAddressPairFromString:to];
  }
  
  return call;
}

+ (instancetype)incomingCallWithAccount:(SBSAccount *)account callId:(pjsua_call_id)callId data:(pjsip_rx_data *)data {
  SBSCall *call = [[SBSCall alloc] initWithAccount:account callId:callId direction:SBSCallDirectionInbound];
  pjsip_msg *msg = data->msg_info.msg;
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
    
    [call.headers setObject:headerValue forKey:[headerName lowercaseString]];
  }
  
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
