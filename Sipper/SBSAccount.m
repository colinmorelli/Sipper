//
//  SipperAccount.m
//  Sipper
//
//  Created by Colin Morelli on 4/20/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSAccount+Internal.h"

#import "NSString+PJString.h"
#import "NSError+SipperError.h"

#import "SBSAccountConfiguration.h"
#import "SBSCall+Internal.h"
#import "SBSEndpoint.h"
#import "SBSEndpointConfiguration.h"
#import "SBSSipURI.h"

static NSString *const AccountErrorDomain = @"sipper.account.error";

@interface SBSAccount ()

@property(nonatomic) BOOL registrationsEnabled;
@property(weak, nonatomic) SBSEndpoint *endpoint;
@property(strong, readwrite, nonatomic, nonnull) NSMutableArray<SBSCall *> *calls;

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
  pjsua_acc_set_user_data((int) _id, (__bridge void *) (self));
}

//------------------------------------------------------------------------------

- (void)dealloc {
  pjsua_acc_set_user_data((int) _id, NULL);
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

  // Create a pool for allocating memory
  pjsua_acc_config config;
  pj_caching_pool cp;
  pj_caching_pool_init(&cp, &pj_pool_factory_default_policy, 0);
  pj_pool_t *pool = pj_pool_create(&cp.factory, "header", 1000, 1000, NULL);
  [SBSAccount convertAccountConfiguration:configuration endpoint:_endpoint config:&config account:self pool:pool];

  // Attempt to perform the account modification
  pj_status_t status = pjsua_acc_modify((int) _id, &config);

  // Ensure we release the pool
  pj_pool_release(pool);

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
      for (SBSCall *call in self.calls) {
        [call reinviteWithCallback:nil];
      }
  }];
}

//------------------------------------------------------------------------------

- (SBSCall *)callWithDestination:(NSString *)destination headers:(NSDictionary<NSString *, NSString *> *_Nullable)headers {
  return [self callWithUuid:[NSUUID UUID] destination:destination headers:headers];
}

//------------------------------------------------------------------------------

- (SBSCall *)callWithUuid:(NSUUID *)uuid destination:(NSString *)destination headers:(NSDictionary<NSString *, NSString *> *)headers {
  SBSSipURI *uri = [SBSSipURI sipUriWithString:destination];
  if (uri == nil) {
    destination = [NSString stringWithFormat:@"sip:%@@%@", destination, self.configuration.sipDomain];
  }

  // Immediately create the call object to start the process
  SBSCall *call = [SBSCall outgoingCallWithAccount:self uuid:uuid destination:destination headers:headers];

  // Arrays are not thread safe
  @synchronized (_calls) {
    [_calls addObject:call];
  }

  // Fire off an async task to actually perform the call setup
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
      if (_configuration.defaultCallHeaders != nil) {
        [_configuration.defaultCallHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *_Nonnull key, NSString *_Nonnull obj, BOOL *_Nonnull stop) {
            pj_str_t name = key.pjString;
            pj_str_t value = obj.pjString;
            pj_list_push_back((pjsip_hdr *) &msg_data.hdr_list, pjsip_generic_string_hdr_create(pool, &name, &value));
        }];
      }

      // Override with call-specific headers
      if (headers != nil) {
        [headers enumerateKeysAndObjectsUsingBlock:^(NSString *_Nonnull key, NSString *_Nonnull obj, BOOL *_Nonnull stop) {
            pj_str_t name = key.pjString;
            pj_str_t value = obj.pjString;
            pj_list_push_back((pjsip_hdr *) &msg_data.hdr_list, pjsip_generic_string_hdr_create(pool, &name, &value));
        }];
      }

      // Create the call now
      pjsua_call_id id;
      pj_str_t dst = destination.pjString;
      pj_status_t status = pjsua_call_make_call((int) _id, &dst, &setting, NULL, &msg_data, &id);

      // Discard the pool to cleanup
      pj_pool_release(pool);

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
}

//------------------------------------------------------------------------------

- (void)handleRegistrationStateChange:(pjsua_reg_info *)info {
  struct pjsip_regc_cbparam *params = info->cbparam;
  int registration_status = params->code;

  // Determine the new registration state
  SBSAccountRegistrationState previousState = _registrationState;

  // First, check for an error on the registration
  if (info->cbparam->status != PJ_SUCCESS) {
    NSError *error = [NSError ErrorWithUnderlying:nil
                          localizedDescriptionKey:NSLocalizedString(@"Could not register with remote endpoint", nil)
                      localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), registration_status]
                                      errorDomain:AccountErrorDomain
                                        errorCode:SBSAccountErrorCannotRegister];

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(account:registrationDidFailWithError:)]) {
          [self.delegate account:self registrationDidFailWithError:error];
        }
    });

    // Here, we're still pending on registration
  } else if (PJSIP_IS_STATUS_IN_CLASS(registration_status, 100) || PJSIP_IS_STATUS_IN_CLASS(registration_status, 300)) {
    _registrationState = SBSAccountRegistrationStateTrying;

    // Here we got a successful de-registration response back
  } else if (PJSIP_IS_STATUS_IN_CLASS(registration_status, 200) && params->expiration == 0) {
    _registrationState = SBSAccountRegistrationStateInactive;

    // Here we got a successful registration back
  } else if (PJSIP_IS_STATUS_IN_CLASS(registration_status, 200)) {
    _registrationState = SBSAccountRegistrationStateActive;

    // Here we don't know, assume inactive
  } else if (registration_status == 0) {
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

    // Fire the delegate handler
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(account:registrationDidChangeState:withStatusCode:)]) {
          [self.delegate account:self registrationDidChangeState:_registrationState withStatusCode:registration_status];
        }
    });
  }
}

//------------------------------------------------------------------------------

- (void)handleIncomingCall:(pjsua_call_id)callId data:(pjsip_rx_data *)data {
  SBSCall *call = [SBSCall incomingCallWithAccount:self uuid:[NSUUID UUID] callId:callId data:data];

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

- (void)handleCallTsxStateChange:(pjsua_call_id)callId transation:(pjsip_transaction *)transaction event:(pjsip_event *_Nonnull)event {
  [[self findCall:callId] handleTransactionStateChange:transaction event:event];
}

//------------------------------------------------------------------------------

- (void)handleTransportStateChange:(pjsip_transport *)transport state:(pjsip_transport_state)state info:(const pjsip_transport_state_info *)info {
  [self.calls enumerateObjectsUsingBlock:^(SBSCall *_Nonnull call, NSUInteger idx, BOOL *_Nonnull stop) {
      [call handleTransportStateChange:transport state:state info:info];
  }];
}

//------------------------------------------------------------------------------

- (SBSCall *_Nullable)findCall:(pjsua_call_id)callId {
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

+ (void)convertAccountConfiguration:(SBSAccountConfiguration *)configuration endpoint:(SBSEndpoint *)endpoint config:(pjsua_acc_config *)config account:(SBSAccount *)account pool:(pj_pool_t *)pool {
  pjsua_acc_config_default(config);

  NSString *tcp = @"";
  if ([endpoint.configuration hasTCPConfiguration]) {
    tcp = @";transport=tcp";
  }

  // Create defaults for some of our variables
  NSString *registrarUri = configuration.sipRegistrarServer,
      *proxyUri = configuration.sipProxyServer,
      *address = configuration.sipAddress;

  if (registrarUri == nil) {
    registrarUri = [[@"sip:" stringByAppendingString:configuration.sipDomain] stringByAppendingString:tcp];
  }

  // Default the address if one wasn't provided
  if (address == nil) {
    address = [NSString stringWithFormat:@"sip:%@@%@", configuration.sipAccount, configuration.sipDomain];
  }

  config->id = configuration.sipAddress.pjString;
  config->reg_uri = registrarUri.pjString;
  config->register_on_acc_add = false;
  config->publish_enabled = configuration.sipPublishEnabled ? PJ_TRUE : PJ_FALSE;
  config->reg_timeout = (int) configuration.sipRegistrationLifetime;
  config->reg_retry_interval = (int) configuration.sipRegistrationRetryTimeout;
  config->use_rfc5626 = true;
  config->use_srtp = [self convertSrtpPolicy:configuration.secureMediaPolicy];

  // Add custom headers if there are any to add
  if (configuration.registrationHeaders != nil) {
    pj_list_init(&config->reg_hdr_list);

    // Push all headers onto the map
    [configuration.registrationHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *_Nonnull key, NSString *_Nonnull obj, BOOL *_Nonnull stop) {
        pj_str_t name = key.pjString;
        pj_str_t value = obj.pjString;
        pj_list_push_back(&config->reg_hdr_list, pjsip_generic_string_hdr_create(pool, &name, &value));
    }];
  }

  // Attach the account credentials to the configuration
  if (configuration.sipPassword != nil) {
    config->cred_count = 1;
    config->cred_info[0].scheme = [self convertAuthenticationScheme:configuration.sipAuthScheme].pjString;
    config->cred_info[0].realm = configuration.sipAuthRealm.pjString;
    config->cred_info[0].username = configuration.sipAccount.pjString;
    config->cred_info[0].data_type = PJSIP_CRED_DATA_PLAIN_PASSWD;
    config->cred_info[0].data = configuration.sipPassword.pjString;
  }

  // Check if we need to push a new proxy into the list
  config->proxy_cnt = 0;
  if (proxyUri != nil) {
    config->proxy_cnt = 1;
    config->proxy[0] = proxyUri.pjString;
  }

  // Attach user data if available
  if (account != nil) {
    config->user_data = (__bridge void *) account;
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

+ (instancetype _Nullable)accountWithConfiguration:(SBSAccountConfiguration *_Nonnull)configuration endpoint:(SBSEndpoint *_Nonnull)endpoint error:(NSError *_Nullable *_Nullable)error {
  int acc_id;
  pjsua_acc_config config;

  // Create a temporary pool for allocating memory
  pj_caching_pool cp;
  pj_caching_pool_init(&cp, &pj_pool_factory_default_policy, 0);
  pj_pool_t *pool = pj_pool_create(&cp.factory, "header", 1000, 1000, NULL);
  [self convertAccountConfiguration:configuration endpoint:endpoint config:&config account:nil pool:pool];

  // Create the new account with PJSIP
  pj_status_t status = pjsua_acc_add(&config, PJ_TRUE, &acc_id);

  // Release the pool of memory regardless of the status
  pj_pool_release(pool);

  // And continue on with the process
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
