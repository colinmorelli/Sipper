//
//  SipperEndpoint.m
//  Sipper
//
//  Created by Colin Morelli on 4/20/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSEndpoint.h"

#import "NSString+PJString.h"
#import "NSError+SipperError.h"

#import "SBSAccount+Internal.h"
#import "SBSCall+Internal.h"
#import "SBSEndpointConfiguration.h"
#import "SBSTransportConfiguration.h"

static NSString * const EndpointErrorDomain = @"sipper.endpoint.error";

static void onCallState(pjsua_call_id callId, pjsip_event *event);
static void onIncomingCall(pjsua_acc_id acc_id, pjsua_call_id call_id, pjsip_rx_data *rdata);
static void onCallMediaState(pjsua_call_id call_id);

@interface SBSEndpoint ()

@property (strong, nonatomic) NSMutableDictionary *accounts;

@end

@implementation SBSEndpoint

//------------------------------------------------------------------------------

- (instancetype)init {
  if (self = [super init]) {
    _accounts = [[NSMutableDictionary alloc] init];
  }
  
  return self;
}

//------------------------------------------------------------------------------

- (BOOL)initializeEndpointWithConfiguration:(SBSEndpointConfiguration *)configuration error:(NSError *__autoreleasing *)error {
  pj_status_t status;
  
  // Create a new instance of PJSUA. The default instance will be thread-confined to the thread it was created on. However,
  // background queues can be used if they're registered with the endpoint.
  status = pjsua_create();
  if (status != PJ_SUCCESS) {
    [self destroyEndpointWithError:nil];
    *error = [NSError ErrorWithUnderlying:nil
                  localizedDescriptionKey:NSLocalizedString(@"Could not create endpoint", nil)
              localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                              errorDomain:EndpointErrorDomain
                                errorCode:SBSEndpointErrorCannotCreate];
    return NO;
  }
  
  // Convert all of the provided configuration into the appropriate structs
  pjsua_logging_config logging_config;
  pjsua_media_config media_config;
  pjsua_config config;
  [self extractLoggingConfiguration:configuration config:&logging_config];
  [self extractMediaConfiguration:configuration config:&media_config];
  [self extractEndpointConfiguration:configuration config:&config];
  
  // Initialize PJSUA with the default parameters
  status = pjsua_init(&config, &logging_config, &media_config);
  if (status != PJ_SUCCESS) {
    [self destroyEndpointWithError:nil];
    *error = [NSError ErrorWithUnderlying:nil
                  localizedDescriptionKey:NSLocalizedString(@"Could not initialize endpoint", nil)
              localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                              errorDomain:EndpointErrorDomain
                                errorCode:SBSEndpointErrorCannotInitialize];
    return NO;
  }
  
  // Now, we need to iterate through each of the requested transports and configure them here
  for (SBSTransportConfiguration *transportConfiguration in configuration.transportConfigurations) {
    pjsua_transport_config transport_config;
    pjsip_transport_type_e transport_type = [self convertTransportType:transportConfiguration.transportType];
    [self convertTransportConfiguration:transportConfiguration config:&transport_config];
    NSLog(@"%d", transport_type);
    
    pjsua_transport_id transport_id;
    status = pjsua_transport_create(transport_type, &transport_config, &transport_id);
    if (status != PJ_SUCCESS) {
      [self destroyEndpointWithError:nil];
      *error = [NSError ErrorWithUnderlying:nil
                    localizedDescriptionKey:NSLocalizedString(@"Could not create transport", nil)
                localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                errorDomain:EndpointErrorDomain
                                  errorCode:SBSEndpointErrorCannotAddTransportConfiguration];
      return NO;
    }
  }
  
  // And, finally, we can start the endpoint - this enables PJSUA to be used
  status = pjsua_start();
  if (status != PJ_SUCCESS) {
    [self destroyEndpointWithError:nil];
    *error = [NSError ErrorWithUnderlying:nil
                  localizedDescriptionKey:NSLocalizedString(@"Could not create transport", nil)
              localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                              errorDomain:EndpointErrorDomain
                                errorCode:SBSEndpointErrorCannotAddTransportConfiguration];
    return NO;
  }
  
  // Update the configuration that is in use
  _configuration = configuration;
  
  // We're successful if we didn't set an error pointer
  return YES;
}

//------------------------------------------------------------------------------

- (BOOL)destroyEndpointWithError:(NSError *__autoreleasing *)error {
  pjsua_destroy();
  
  return YES;
}

//------------------------------------------------------------------------------

- (SBSAccount *)createAccountWithConfiguration:(SBSAccountConfiguration *)configuration error:(NSError *__autoreleasing *)error {
  SBSAccount *account = [SBSAccount accountWithConfiguration:configuration endpoint:self error:error];
  
  // Stop here if we didn't get an account
  if (account == nil) {
    return nil;
  }
  
  // Successful creation, register the account with sipper
  return self.accounts[@(account.id)] = account;
}

//------------------------------------------------------------------------------

- (void)dealloc {
  NSError *error;
  
  // Attempt to gracefully shutdown if we haven't already
  if (![self destroyEndpointWithError:&error]) {
    NSLog(@"WARN: Failed to cleanly tear down SIP client - you should *always* call destroyEndpointWithError before letting the instance be released");
  }
}

//------------------------------------------------------------------------------
#pragma mark - Converters
//------------------------------------------------------------------------------

- (void)extractLoggingConfiguration:(SBSEndpointConfiguration *)configuration config:(pjsua_logging_config *)config {
  pjsua_logging_config_default(config);
  
  config->level          = (unsigned int) configuration.logLevel;
  config->console_level  = (unsigned int) configuration.logConsoleLevel;
  config->log_filename   = configuration.logFilename.pjString;
  config->log_file_flags = (unsigned int) configuration.logFileFlags;
}

- (void)extractEndpointConfiguration:(SBSEndpointConfiguration *)configuration config:(pjsua_config *)config {
  pjsua_config_default(config);
  
  config->cb.on_reg_state        = &onRegState;
  config->cb.on_incoming_call    = &onIncomingCall;
  config->cb.on_call_state       = &onCallState;
  config->cb.on_call_media_state = &onCallMediaState;
  
  config->max_calls = (unsigned int) configuration.maxCalls;
}

- (void)extractMediaConfiguration:(SBSEndpointConfiguration *)configuration config:(pjsua_media_config *)config {
  pjsua_media_config_default(config);
  
  config->clock_rate     = (unsigned int) configuration.clockRate == 0 ? PJSUA_DEFAULT_CLOCK_RATE : (unsigned int) configuration.clockRate;
  config->snd_clock_rate = (unsigned int) configuration.sndClockRate;
}

- (void)convertTransportConfiguration:(SBSTransportConfiguration *)configuration config:(pjsua_transport_config *)config {
  pjsua_transport_config_default(config);
  
  config->port       = (unsigned int) configuration.port;
  config->port_range = (unsigned int) configuration.portRange;
}

- (pjsip_transport_type_e)convertTransportType:(SBSTransportType)type {
  switch (type) {
    case SBSTransportTypeTCP:
      return PJSIP_TRANSPORT_TCP;
    case SBSTransportTypeUDP:
      return PJSIP_TRANSPORT_UDP;
    case SBSTransportTypeTCP6:
      return PJSIP_TRANSPORT_TCP6;
    case SBSTransportTypeUDP6:
      return PJSIP_TRANSPORT_UDP6;
  }
}

//------------------------------------------------------------------------------
#pragma mark - Factory
//------------------------------------------------------------------------------
+ (instancetype)sharedEndpoint {
  static dispatch_once_t p = 0;
  __strong static id _sharedObject = nil;
  
  dispatch_once(&p, ^{
    _sharedObject = [[self alloc] init];
  });
  
  return _sharedObject;
}

//------------------------------------------------------------------------------
#pragma mark - PJSUA Callbacks
//------------------------------------------------------------------------------

static void onCallState(pjsua_call_id callId, pjsip_event *event) {
  void *data = pjsua_call_get_user_data(callId);
  if (data == NULL) {
    return;
  }
  
  SBSCall *call = (__bridge SBSCall *) data;
  [call.account handleCallStateChange:callId];
}

static void onCallMediaState(pjsua_call_id callId) {
  void *data = pjsua_call_get_user_data(callId);
  if (data == NULL) {
    return;
  }
  
  SBSCall *call = (__bridge SBSCall *) data;
  [call.account handleCallMediaStateChange:callId];
}

static void onRegState(pjsua_acc_id accountId) {
  void *data = pjsua_acc_get_user_data(accountId);
  if (data == NULL) {
    return;
  }
  
  SBSAccount *account = (__bridge SBSAccount *) data;
  [account handleRegistrationStateChange];
}

static void onIncomingCall(pjsua_acc_id accountId, pjsua_call_id callId, pjsip_rx_data *rdata) {
  void *data = pjsua_acc_get_user_data(accountId);
  if (data == NULL) {
    return;
  }
  
  SBSAccount *account = (__bridge SBSAccount *) data;
  [account handleIncomingCall:callId data:rdata];
}

@end
