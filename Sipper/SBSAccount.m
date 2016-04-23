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

#import "SBSCall+Internal.h"
#import "SBSEndpoint.h"
#import "SBSEndpointConfiguration.h"

static NSString * const AccountErrorDomain = @"sipper.account.error";

@interface SBSAccount ()

@property (weak, nonatomic) SBSEndpoint *endpoint;
@property (strong, nonnull) NSMutableDictionary *calls;

@end

@implementation SBSAccount

//------------------------------------------------------------------------------

- (instancetype)initWithConfiguration:(SBSAccountConfiguration *)configuration endpoint:(SBSEndpoint *)endpoint accountId:(pjsua_acc_id)accountId {
  if (self = [super init]) {
    _id = accountId;
    _endpoint = endpoint;
    _calls = [[NSMutableDictionary alloc] init];
    _configuration = configuration;
    
    [self prepare];
  }
  
  return self;
}

//------------------------------------------------------------------------------

- (void)prepare {
  pjsua_acc_set_user_data((int) _id, (__bridge void *)(self));
}

- (void)dealloc {
  pjsua_acc_set_user_data((int) _id, NULL);
}

//------------------------------------------------------------------------------

- (void)startRegistration {
  
  // Start the registration process
  pj_status_t status = pjsua_acc_set_registration((int) self.id, PJ_TRUE);
  if (status != PJ_SUCCESS) {
    NSError *error = [NSError ErrorWithUnderlying:nil
                          localizedDescriptionKey:NSLocalizedString(@"Could not register account", nil)
                      localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                      errorDomain:AccountErrorDomain
                                        errorCode:SBSAccountErrorCannotRegister];
    
    [self.delegate account:self registrationDidFailWithError:error];
  }
}

//------------------------------------------------------------------------------
#pragma mark - Event Handlers
//------------------------------------------------------------------------------

- (void)handleRegistrationStateChange {
  pjsua_acc_info info;
  pj_status_t status = pjsua_acc_get_info((int) _id, &info);
  if (status != PJ_SUCCESS) {
    return;
  }
  
  dispatch_async(dispatch_get_main_queue(), ^{
    if (PJSIP_IS_STATUS_IN_CLASS(info.status, 100) || PJSIP_IS_STATUS_IN_CLASS(info.status, 300)) {
      [self.delegate account:self registrationDidChangeState:SBSAccountRegistrationStateTrying withStatusCode:info.status];
    } else if (PJSIP_IS_STATUS_IN_CLASS(info.status, 200)) {
      [self.delegate account:self registrationDidChangeState:SBSAccountRegistrationStateActive withStatusCode:info.status];
    } else {
      [self.delegate account:self registrationDidChangeState:SBSAccountRegistrationStateInactive withStatusCode:info.status];
    }
  });
}

- (void)handleIncomingCall:(pjsua_call_id)callId data:(pjsip_rx_data *)data {
  SBSCall *call = [SBSCall incomingCallWithAccount:self callId:callId data:data];
  self.calls[@(call.id)] = call;
  
  dispatch_async(dispatch_get_main_queue(), ^{
    [self.delegate account:self didReceiveIncomingCall:call];
  });
}

- (void)handleCallStateChange:(pjsua_call_id)callId {
  SBSCall *call = self.calls[@(callId)];
  if (call == nil) {
    return;
  }
  
  [call handleCallStateChange];
  
  // Cleanup if the resulting call state is disconnected
  if (call.state == SBSCallStateDisconnected) {
    [self.calls removeObjectForKey:@(callId)];
  }
}

- (void)handleCallMediaStateChange:(pjsua_call_id)callId {
  [self.calls[@(callId)] handleCallMediaStateChange];
}

- (void)handleCallTsxStateChange:(pjsua_call_id)callId transation:(pjsip_transaction *)transaction {
  [self.calls[@(callId)] handleTransactionStateChange:transaction];
}

//------------------------------------------------------------------------------
#pragma mark - Converters
//------------------------------------------------------------------------------

+ (void)convertAccountConfiguration:(SBSAccountConfiguration *)configuration endpoint:(SBSEndpoint *)endpoint config:(pjsua_acc_config *)config {
  pjsua_acc_config_default(config);
  
  NSString *tcp = @"";
  if ([endpoint.configuration hasTCPConfiguration]) {
    tcp = @";transport=tcp";
  }
  
  // Create defaults for some of our variables
  NSString *registrarUri = configuration.sipRegistrarServer,
           *proxyUri     = configuration.sipProxyServer;
  if (proxyUri == nil) {
    proxyUri = [@"sip:" stringByAppendingString:configuration.sipDomain];
  }
  
  if (registrarUri == nil) {
    registrarUri = proxyUri;
  }
  
  config->id                   = configuration.sipAddress.pjString;
  config->reg_uri              = registrarUri.pjString;
  config->register_on_acc_add  = false;
  config->publish_enabled      = configuration.sipPublishEnabled ? PJ_TRUE : PJ_FALSE;
  config->reg_timeout          = 800;
  config->reg_retry_interval   = (int) configuration.sipRegistrationRetryTimeout;

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
    config->proxy[0]  = [proxyUri stringByAppendingString:tcp].pjString;
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

//------------------------------------------------------------------------------
#pragma mark - Factories
//------------------------------------------------------------------------------

+ (instancetype _Nullable)accountWithConfiguration:(SBSAccountConfiguration * _Nonnull)configuration endpoint:(SBSEndpoint * _Nonnull)endpoint error:(NSError * _Nullable * _Nullable)error {
  int acc_id;
  pjsua_acc_config config;
  [self convertAccountConfiguration:configuration endpoint:endpoint config:&config];
  
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