//
//  SipperAccount.m
//  Sipper
//
//  Created by Colin Morelli on 4/20/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSAccount+Internal.h"

#import <Foundation/Foundation.h>
#import <pjsua.h>

#import "NSString+PJString.h"
#import "NSError+SipperError.h"

#import "SBSAccountConfiguration.h"
#import "SBSCall+Internal.h"
#import "SBSEndpoint.h"
#import "SBSEndpointConfiguration.h"
#import "SBSSipURI.h"

static NSString * const AccountErrorDomain = @"sipper.account.error";

@interface SBSAccount ()

@property (nonatomic) BOOL registrationsEnabled;
@property (nonatomic) pjsip_transport *transport;
@property (weak, nonatomic) SBSEndpoint *endpoint;
@property (strong, readwrite, nonatomic, nonnull) NSMutableArray<SBSCall *> *calls;

@end

@implementation SBSAccount

//------------------------------------------------------------------------------

- (instancetype)initWithConfiguration:(SBSAccountConfiguration *)configuration endpoint:(SBSEndpoint *)endpoint accountId:(pjsua_acc_id)accountId {
  if (self = [super init]) {
    _id = accountId;
    _endpoint = endpoint;
    _calls = [NSMutableArray array];
    _configuration = configuration;
    _registrationState = SBSAccountRegistrationStateDisabled;
    _registrationsEnabled = false;
    
    [self prepare];
  }
  
  return self;
}

//------------------------------------------------------------------------------

- (void)prepare {
  pjsua_acc_set_user_data((int) _id, (__bridge void *)(self));
}

//------------------------------------------------------------------------------

- (void)dealloc {
  pjsua_acc_set_user_data((int) _id, NULL);
  
  // Clear transport reference if we have one
  if (_transport) {
    pjsip_transport_dec_ref(_transport);
    _transport = NULL;
  }
}

//------------------------------------------------------------------------------

- (void)startRegistration {
  if (_registrationsEnabled == true) {
    return;
  }
  
  pj_status_t status = pjsua_acc_set_registration((int) _id, PJ_TRUE);
  if (status != PJ_SUCCESS) {
    NSError *error = [NSError ErrorWithUnderlying:nil
                          localizedDescriptionKey:NSLocalizedString(@"Could not register account", nil)
                      localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                      errorDomain:AccountErrorDomain
                                        errorCode:SBSAccountErrorCannotRegister];
    
    if ([self.delegate respondsToSelector:@selector(account:registrationDidFailWithError:)]) {
      [self.delegate account:self registrationDidFailWithError:error];
    }
  }
  
  _registrationsEnabled = true;
}

//------------------------------------------------------------------------------

- (void)stopRegistration {
  if (_registrationsEnabled == false) {
    return;
  }
  
  pj_status_t status = pjsua_acc_set_registration((int) _id, PJ_FALSE);
  if (status != PJ_SUCCESS) {
    NSError *error = [NSError ErrorWithUnderlying:nil
                          localizedDescriptionKey:NSLocalizedString(@"Could not register account", nil)
                      localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                      errorDomain:AccountErrorDomain
                                        errorCode:SBSAccountErrorCannotRegister];
    
    
    if ([self.delegate respondsToSelector:@selector(account:registrationDidFailWithError:)]) {
      [self.delegate account:self registrationDidFailWithError:error];
    }
  }
  
  _registrationsEnabled = false;
}

//------------------------------------------------------------------------------

- (void)updateConfiguration:(SBSAccountConfiguration *)configuration {
  pjsua_acc_config config;
  [SBSAccount convertAccountConfiguration:configuration endpoint:_endpoint config:&config account:self];
  
  // Attempt to perform the account modification
  pj_status_t status = pjsua_acc_modify((int) _id, &config);
  if (status != PJ_SUCCESS) {
    NSError *error = [NSError ErrorWithUnderlying:nil
                          localizedDescriptionKey:NSLocalizedString(@"Could not update account configuration", nil)
                      localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                      errorDomain:AccountErrorDomain
                                        errorCode:SBSAccountErrorCannotRegister];
    
    if ([self.delegate respondsToSelector:@selector(account:registrationDidFailWithError:)]) {
      [self.delegate account:self registrationDidFailWithError:error];
    }
  }
}

//------------------------------------------------------------------------------

- (void)handleReachabilityChange {
  
  // If we have an active transport, shut it down
  [self.endpoint performAsync:^{
    if (_transport) {
      pj_status_t status = pjsip_transport_shutdown(_transport);
      if (status != PJ_SUCCESS) {
        NSLog(@"Unable to destroy transport");
      }
      
      pjsip_transport_dec_ref(_transport);
      _transport = NULL;
    }
    
    // Unregister this account to ensure it's properly disabled. If registrations are
    // enabled for this account (using startRegistration), this will automatically be
    // detected by the registration handler, and the account will re-register using a
    // new transport.
    pj_status_t status = pjsua_acc_set_registration((int) _id, PJ_FALSE);
    if (status != PJ_SUCCESS) {
      NSLog(@"Unable to send new registration");
    }
  }];
}

//------------------------------------------------------------------------------

- (SBSCall *)callWithDestination:(NSString *)destination {
  SBSSipURI *uri = [SBSSipURI sipUriWithString:destination];
  if (uri == nil) {
    destination = [NSString stringWithFormat:@"sip:%@@%@", destination, self.configuration.sipDomain];
  }
  
  // Immediately create the call object to start the process
  SBSCall *call = [SBSCall outgoingCallWithAccount:self destination:destination];
  
  // Calls are not thread safe
  @synchronized (_calls) {
    [_calls addObject:call];
  }
  
  // Fire off an async task to actually perform the call setup
  [self.endpoint performAsync:^{
    pjsua_call_setting setting;
    pjsua_call_setting_default(&setting);
    
    pjsua_call_id id;
    pj_str_t dst = destination.pjString;
    pj_status_t status = pjsua_call_make_call((int) _id, &dst, &setting, NULL, NULL, &id);
    
    if (status != PJ_SUCCESS) {
      @synchronized (_calls) {
        [_calls removeObject:call];
      }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      if (status != PJ_SUCCESS) {
        NSError *error = [NSError ErrorWithUnderlying:nil
                              localizedDescriptionKey:NSLocalizedString(@"Could not create outbound call", nil)
                          localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                          errorDomain:AccountErrorDomain
                                            errorCode:SBSAccountErrorCannotRegister];

        [call handleFailureWithError:error];
        return;
      }
      
      [call handleAssociateWithCall:id];
    });
  }];
  
  // Schedule a delegate call to inform of the new call
  dispatch_async(dispatch_get_main_queue(), ^{
    if ([self.delegate respondsToSelector:@selector(account:didMakeOutgoingCall:)]) {
      [self.delegate account:self didMakeOutgoingCall:call];
    }
  });
  
  // Return the newly created call so the UI can update immediately
  return call;
}

//------------------------------------------------------------------------------
#pragma mark - Event Handlers
//------------------------------------------------------------------------------

- (void)handleRegistrationStarted:(pjsua_reg_info *)info {
  pjsip_regc_info regc_info;
  pjsip_regc_get_info(info->regc, &regc_info);
  
  if (_transport != regc_info.transport) {
    
    // If we have reference to an active transport, clear it out
    if (_transport) {
      pjsip_transport_dec_ref(_transport);
      _transport = NULL;
    }
    
    // Save the new transport for this registration
    _transport = regc_info.transport;
    pjsip_transport_add_ref(_transport);
  }
}

//------------------------------------------------------------------------------

- (void)handleRegistrationStateChange:(pjsua_reg_info *)info {
  struct pjsip_regc_cbparam *params = info->cbparam;
  int status = params->code;
  
  // If we got a successful registration - update our transport pointer
  if (params->code / 100 == 2 && params->expiration > 0 && params->contact_cnt > 0) {
    
    // Cleanup any old transport references that we have
    if (_transport) {
      pjsip_transport_dec_ref(_transport);
      _transport = NULL;
    }
    
    // Assign the new transport reference
    _transport = params->rdata->tp_info.transport;
    pjsip_transport_add_ref(_transport);
  }
  
  // Determine the new registration state
  SBSAccountRegistrationState previousState = _registrationState;
  
  // First, check for an error on the registration
  if (info->cbparam->status != PJ_SUCCESS) {
    NSError *error = [NSError ErrorWithUnderlying:nil
                          localizedDescriptionKey:NSLocalizedString(@"Could not register with remote endpoint", nil)
                      localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                      errorDomain:AccountErrorDomain
                                        errorCode:SBSAccountErrorCannotRegister];
    
    dispatch_async(dispatch_get_main_queue(), ^{
      if ([self.delegate respondsToSelector:@selector(account:registrationDidFailWithError:)]) {
        [self.delegate account:self registrationDidFailWithError:error];
      }
    });
  }
  
  // Here, we're still pending on registration
  else if (PJSIP_IS_STATUS_IN_CLASS(status, 100) || PJSIP_IS_STATUS_IN_CLASS(status, 300)) {
    _registrationState = SBSAccountRegistrationStateTrying;
    
  // Here we got a successful unregistration response back
  } else if (PJSIP_IS_STATUS_IN_CLASS(status, 200) && params->expiration == 0) {
    _registrationState = SBSAccountRegistrationStateInactive;
    
  // Here we got a successful registration back
  } else if (PJSIP_IS_STATUS_IN_CLASS(status, 200)) {
      _registrationState = SBSAccountRegistrationStateActive;
    
  // Here we don't know, assume inactive
  } else if (status == 0) {
    _registrationState = SBSAccountRegistrationStateInactive;
  }
  
  // Now, if we're inactive but registrations are enabled, re-registration
  if (_registrationState == SBSAccountRegistrationStateInactive && _registrationsEnabled) {
    NSLog(@"Received inactive registration state while registrations enabled, re-sending registration");
    pj_status_t status = pjsua_acc_set_registration((int) _id, PJ_TRUE);
    if (status != PJ_SUCCESS) {
      NSError *error = [NSError ErrorWithUnderlying:nil
                            localizedDescriptionKey:NSLocalizedString(@"Could not register account", nil)
                        localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                        errorDomain:AccountErrorDomain
                                          errorCode:SBSAccountErrorCannotRegister];
      
      dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(account:registrationDidFailWithError:)]) {
          [self.delegate account:self registrationDidFailWithError:error];
        }
      });
    }
  }
  
  // Check if the registration state has changed
  if (_registrationState != previousState) {
    
    // Attempt to reconcile active calls (if we're back into an active state)
    if (_registrationState == SBSAccountRegistrationStateActive) {
      NSLog(@"Registration state changed to active, re-inviting active calls");
      for (SBSCall *call in self.calls) {
        NSLog(@"Reinviting call");
        [call reinviteWithCallback:nil];
      }
    }
    
    // Fire the delegate handler
    dispatch_async(dispatch_get_main_queue(), ^{
      if ([self.delegate respondsToSelector:@selector(account:registrationDidChangeState:withStatusCode:)]) {
        [self.delegate account:self registrationDidChangeState:_registrationState withStatusCode:status];
      }
    });
  }
}

//------------------------------------------------------------------------------

- (void)handleIncomingCall:(pjsua_call_id)callId data:(pjsip_rx_data *)data {
  SBSCall *call = [SBSCall incomingCallWithAccount:self callId:callId data:data];
  
  // Lack of thread safe calls
  @synchronized (_calls) {
    [_calls addObject:call];
  }
  
  // Set the default call ringtone from the account
  call.ringtone = self.ringtone;
  
  // Invoke the delegate - ringtone may change after this so we call ring isndoe the delegate handler
  dispatch_async(dispatch_get_main_queue(), ^{
    if ([self.delegate respondsToSelector:@selector(account:didReceiveIncomingCall:)]) {
      [self.delegate account:self didReceiveIncomingCall:call];
    }
    
    [call ring];
  });
}

//------------------------------------------------------------------------------

- (void)handleCallStateChange:(pjsua_call_id)callId {
  SBSCall *call = [self findCall:callId];
  
  if (call == nil) {
    return;
  }
  
  [call handleCallStateChange];
  
  // Cleanup if the resulting call state is disconnected
  if (call.state == SBSCallStateDisconnected) {
    NSLog(@"Call disconnected, cleaning up");
    
    @synchronized (_calls) {
      [_calls removeObject:call];
    }
  }
}

//------------------------------------------------------------------------------

- (void)handleCallMediaStateChange:(pjsua_call_id)callId {
  [[self findCall:callId] handleCallMediaStateChange];
}

//------------------------------------------------------------------------------

- (void)handleCallTsxStateChange:(pjsua_call_id)callId transation:(pjsip_transaction *)transaction {
  [[self findCall:callId] handleTransactionStateChange:transaction];
}

//------------------------------------------------------------------------------

- (SBSCall * _Nullable)findCall:(pjsua_call_id)callId {
  @synchronized (_calls) {
    for (SBSCall *call in _calls) {
      if ((int) call.id == callId) {
        return call;
      }
    }
    
    return nil;
  }
}

//------------------------------------------------------------------------------
#pragma mark - Converters
//------------------------------------------------------------------------------

+ (void)convertAccountConfiguration:(SBSAccountConfiguration *)configuration endpoint:(SBSEndpoint *)endpoint config:(pjsua_acc_config *)config account:(SBSAccount *)account {
  pjsua_acc_config_default(config);
  
  NSString *tcp = @"";
  if ([endpoint.configuration hasTCPConfiguration]) {
    tcp = @";transport=tcp";
  }
  
  // Create defaults for some of our variables
  NSString *registrarUri = configuration.sipRegistrarServer,
           *proxyUri     = configuration.sipProxyServer;
  if (proxyUri == nil) {
    proxyUri = [[@"sip:" stringByAppendingString:configuration.sipDomain] stringByAppendingString:tcp];
  }
  
  if (registrarUri == nil) {
    registrarUri = proxyUri;
  }
  
  config->id                   = configuration.sipAddress.pjString;
  config->reg_uri              = registrarUri.pjString;
  config->register_on_acc_add  = false;
  config->publish_enabled      = configuration.sipPublishEnabled ? PJ_TRUE : PJ_FALSE;
  config->reg_timeout          = (int) configuration.sipRegistrationLifetime;
  config->reg_retry_interval   = (int) configuration.sipRegistrationRetryTimeout;
  config->use_rfc5626          = true;
  config->use_srtp             = [self convertSrtpPolicy:configuration.secureMediaPolicy];

  // Attach the account credentials to the configuration
  config->cred_count = 1;
  config->cred_info[0].scheme    = [self convertAuthenticationScheme:configuration.sipAuthScheme].pjString;
  config->cred_info[0].realm     = configuration.sipAuthRealm.pjString;
  config->cred_info[0].username  = configuration.sipAccount.pjString;
  config->cred_info[0].data_type = PJSIP_CRED_DATA_PLAIN_PASSWD;
  config->cred_info[0].data      = configuration.sipPassword.pjString;
  
  // Check if we need to push a new proxy into the list
  config->proxy_cnt = 0;
  if (proxyUri != nil) {
    config->proxy_cnt = 1;
    config->proxy[0]  = proxyUri.pjString;
  }
  
  // Attach user data if available
  if (account != nil) {
    config->user_data = (__bridge void *)account;
  }
}

//------------------------------------------------------------------------------

+ (NSString *)convertAuthenticationScheme:(SBSAuthenticationScheme)scheme {
  switch (scheme) {
    case SBSAuthenticationSchemeDigest:
      return @"digest";
  }
  
  return nil;
}

+ (pjmedia_srtp_use)convertSrtpPolicy:(SBSSecureMediaPolicy)policy {
  switch (policy) {
    case SBSSecureMediaPolicyNone:
      return PJMEDIA_SRTP_DISABLED;
    case SBSSecureMediaPolicyOptional:
      return PJMEDIA_SRTP_OPTIONAL;
    case SBSSecureMediaPolicyRequired:
      return PJMEDIA_SRTP_MANDATORY;
    default:
      return PJMEDIA_SRTP_OPTIONAL;
  }
}

//------------------------------------------------------------------------------
#pragma mark - Factories
//------------------------------------------------------------------------------

+ (instancetype _Nullable)accountWithConfiguration:(SBSAccountConfiguration * _Nonnull)configuration endpoint:(SBSEndpoint * _Nonnull)endpoint error:(NSError * _Nullable * _Nullable)error {
  int acc_id;
  pjsua_acc_config config;
  [self convertAccountConfiguration:configuration endpoint:endpoint config:&config account:nil];
  
  // Create the new account with PJSIP
  pj_status_t status = pjsua_acc_add(&config, PJ_TRUE, &acc_id);
  if (status != PJ_SUCCESS) {
    *error = [NSError ErrorWithUnderlying:nil
                  localizedDescriptionKey:NSLocalizedString(@"Could not create account", nil)
              localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                              errorDomain:AccountErrorDomain
                                errorCode:SBSAccountErrorCannotCreate];
    return nil;
  }
  
  // Store the account ID internally if successful
  return [[SBSAccount alloc] initWithConfiguration:configuration endpoint:endpoint accountId:acc_id];
}

@end