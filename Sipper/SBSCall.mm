//
//  SBSCall.mm
//  Sipper
//
//  Created by Colin Morelli on 4/21/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSCall.h"
#import "SBSCall+Internal.hpp"
#import "NSString+PJString.h"

#import <pjsua2/account.hpp>
#import <pjsua2/call.hpp>

typedef void (^OnCallStateHandler)(pj::OnCallStateParam param);
typedef void (^OnCallMediaStateHandler)(pj::OnCallMediaStateParam param);

//
// MARK: PJSIP Subclass
//

class SBSCallWrapper : public pj::Call
{
public:
  SBSCallWrapper(pj::Account &acc, int call_id = PJSUA_INVALID_ID) : Call(acc, call_id) {}
  ~SBSCallWrapper() {}
  
  OnCallStateHandler onCallStateHandler;
  OnCallMediaStateHandler onCallMediaStateHandler;
  
  virtual void onCallState(pj::OnCallStateParam &prm) {
    if (onCallStateHandler != NULL) {
      onCallStateHandler(prm);
    }
  }
  
  virtual void onCallMediaState(pj::OnCallMediaStateParam &ptm) {
    if (onCallMediaStateHandler != NULL) {
      onCallMediaStateHandler(ptm);
    }
  }
};

@interface SBSCall ()

@property (nonatomic) SBSCallWrapper *call;
@property (strong, nonatomic) NSMutableDictionary *headers;

@end

@implementation SBSCall

- (instancetype)initWithAccount:(SBSAccount *)account call:(SBSCallWrapper *)wrapper direction:(SBSCallDirection)direction {
  if (self = [super init]) {
    _account = account;
    _call = wrapper;
    _direction = direction;
    _headers = [[NSMutableDictionary alloc] init];
    _state = [self convertState:wrapper->getInfo().state];
    
    [self prepare];
  }
  
  return self;
}

- (void)prepare {
  self.call->onCallStateHandler = ^(pj::OnCallStateParam param) {
    SBSCallState state = self.state;
    
    try {
      pj::CallInfo info = self.call->getInfo();
      state = [self convertState:info.state];
    } catch (pj::Error& err) {
      if (err.status == PJSIP_ESESSIONTERMINATED) {
        state = SBSCallStateDisconnected;
      } else {
        throw err;
      }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.delegate call:self didChangeState:state];
    });
  };
  
  self.call->onCallMediaStateHandler = ^(pj::OnCallMediaStateParam param) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.delegate callDidChangeMediaState:self];
    });
  };
}

- (void)answer {
  [self answerWithStatus:SBSStatusCodeOk];
}

- (void)answerWithStatus:(SBSStatusCode)code {
  pj::CallOpParam param;
  param.statusCode = (pjsip_status_code) code;
  self.call->answer(param);
}

- (void)hangup {
  pj::CallOpParam param;
  param.statusCode = (pjsip_status_code) SBSStatusCodeDecline;
  self.call->hangup(param);
}

- (NSString *)valueForHeader:(NSString *)header {
  return self.headers[header];
}

- (NSDictionary *)allHeaders {
  return [self.headers copy];
}

+ (instancetype)incomingCallWithAccount:(SBSAccount *)account underlying:(pj::Account *)underlying incomingCallData:(pj::OnIncomingCallParam)param {
  SBSCallWrapper *wrapper = new SBSCallWrapper(*underlying, param.callId);
  SBSCall *call = [[SBSCall alloc] initWithAccount:account call:wrapper direction:SBSCallDirectionInbound];
  
  // Check to see if there are any headers we can parse out of the call
  void *headers = param.rdata.pjRxData;
  if (headers == NULL) {
    return call;
  }
  
  // We have a valid call metadata object, iterate over the headers
  pjsip_rx_data *data = (pjsip_rx_data *)headers;
  pjsip_msg *msg = data->msg_info.msg;
  pjsip_hdr *hdr = msg->hdr.next,
            *end = &msg->hdr;
  
  // Iterate over all of the headers, push to dictionary
  for (; hdr != end; hdr = hdr->next) {
    NSString *headerName = [NSString stringWithPJString:hdr->name];
    char value[512] = {0};
    
    // Where we go next depends on the type of header
    if (hdr->type == PJSIP_H_FROM) {
      pjsip_fromto_hdr *header = (pjsip_fromto_hdr *) hdr;
      
      // Make sure we have a URI, and print it into the header vlaue
      if (header->uri != NULL) {
        char uri[512] = {0};
        header->uri->vptr->p_print(PJSIP_URI_IN_FROMTO_HDR, header->uri, uri, 512);
        call.from = [SBSNameAddressPair nameAddressPairFromString:[[NSString alloc] initWithCString:uri encoding:NSUTF8StringEncoding]];
      }
    } else if (hdr->type == PJSIP_H_TO) {
      pjsip_fromto_hdr *header = (pjsip_fromto_hdr *) hdr;
      
      // Make sure we have a URI, and print it into the header vlaue
      if (header->uri != NULL) {
        char uri[512] = {0};
        header->uri->vptr->p_print(PJSIP_URI_IN_FROMTO_HDR, header->uri, uri, 512);
        call.to = [SBSNameAddressPair nameAddressPairFromString:[[NSString alloc] initWithCString:uri encoding:NSUTF8StringEncoding]];
      }
    }

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
  
  return call;
}

//
// MARK: Private Methods
//

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

@end
