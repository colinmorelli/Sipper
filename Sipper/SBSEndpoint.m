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
#import "SBSCodecDescriptor.h"
#import "SBSEndpointConfiguration.h"
#import "SBSTransportConfiguration.h"

static NSString * const EndpointErrorDomain = @"sipper.endpoint.error";

static void onRegState(pjsua_acc_id accountId);
static void onCallState(pjsua_call_id callId, pjsip_event *event);
static void onIncomingCall(pjsua_acc_id accountId, pjsua_call_id callId, pjsip_rx_data *rdata);
static void onCallMediaState(pjsua_call_id callId);
static void onCallTsxState(pjsua_call_id callId, pjsip_transaction *tsx, pjsip_event *event);

@interface SBSEndpoint ()

@property (strong, nonatomic) NSThread *backgroundThread;
@property (strong, nonatomic) NSMutableDictionary *accounts;

@end

@implementation SBSEndpoint

//------------------------------------------------------------------------------

- (instancetype)init {
  if (self = [super init]) {
    _backgroundThread = [[NSThread alloc] initWithTarget:self selector:@selector(threadRunLoop:) object:nil];
    _backgroundThread.threadPriority = DISPATCH_QUEUE_PRIORITY_BACKGROUND;
    _accounts = [[NSMutableDictionary alloc] init];
  }
  
  return self;
}

//------------------------------------------------------------------------------

- (BOOL)initializeEndpointWithConfiguration:(SBSEndpointConfiguration *)configuration error:(NSError *__autoreleasing *)error {
  __block pj_status_t status;
  
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
  
  // Start the background thread
  [_backgroundThread start];
  
  // Perform a block to register the background thread
  [self performSelector:@selector(performAsyncWithBlock:) onThread:_backgroundThread withObject:^{
    pj_thread_desc thread_desc;
    pj_thread_t *thread = 0;
    status = pj_thread_register("background", thread_desc, &thread);
  } waitUntilDone:YES];
  
  // Make sure thread creation was successful
  if (status != PJ_SUCCESS) {
    [self destroyEndpointWithError:nil];
    *error = [NSError ErrorWithUnderlying:nil
                  localizedDescriptionKey:NSLocalizedString(@"Could not register thread", nil)
              localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                              errorDomain:EndpointErrorDomain
                                errorCode:SBSEndpointErrorCannotRegisterThread];
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

- (BOOL)codecDescriptor:(SBSCodecDescriptor *)descriptor matchesIdentifier:(NSString *)identifier {
  NSArray<NSString *> *parts = [identifier componentsSeparatedByString:@"/"];
  NSString *encodingName = parts[0];
  NSUInteger samplingRate = [parts[1] integerValue];
  NSUInteger numberOfChannels = [parts[2] integerValue];
  
  return [encodingName isEqualToString:descriptor.encoding]
          && (descriptor.samplingRate == 0 || descriptor.samplingRate == samplingRate)
          && (descriptor.numberOfChannels == 0 || descriptor.numberOfChannels == numberOfChannels);
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

- (BOOL)updatePreferredCodecs:(NSArray<SBSCodecDescriptor *> *)descriptors error:(NSError *__autoreleasing  _Nullable *)error {
  pj_status_t status;
  
  const unsigned codec_info_size = 64;
  unsigned codec_count = codec_info_size;
  pjsua_codec_info codec_info[codec_info_size];
  
  status = pjsua_enum_codecs(codec_info, &codec_count);
  if (status != PJ_SUCCESS) {
    *error = [NSError ErrorWithUnderlying:nil
                  localizedDescriptionKey:NSLocalizedString(@"Could not register thread", nil)
              localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                              errorDomain:EndpointErrorDomain
                                errorCode:SBSEndpointErrorCannotRegisterThread];
    return NO;
  }
  
  // Push all codecs into a codec list
  NSMutableSet<NSString *> *unmatchedCodecs = [[NSMutableSet alloc] init];
  NSUInteger attachedCodecs = 0;
  for (NSUInteger i = 0; i < codec_count; i++) {
    [unmatchedCodecs addObject:[NSString stringWithPJString:codec_info[i].codec_id]];
  }
  
  // Now, iterate over our preferred codecs map and find matches
  for (SBSCodecDescriptor *descriptor in descriptors) {
    
    // Find any matching codecs in the result
    for (NSUInteger i = 0; i < codec_count; i++) {
      NSString *codecIdentifier = [NSString stringWithPJString:codec_info[i].codec_id];
      
      // Stop here if this codec doesn't match
      if (![self codecDescriptor:descriptor matchesIdentifier:codecIdentifier]) {
        continue;
      }
      
      // This codec had a match, we can pull it out of the unmatched list
      [unmatchedCodecs removeObject:codecIdentifier];
      
      // And, assign this codec's priority from the number of codecs we've already assigned
      pj_uint8_t priority = PJMEDIA_CODEC_PRIO_HIGHEST - attachedCodecs++;
      NSLog(@"Codec %@ matches codec descriptor %@, assigning priority %d", codecIdentifier, descriptor, priority);
      status = pjsua_codec_set_priority(&codec_info[i].codec_id, priority
                                        );
      if (status != PJ_SUCCESS) {
        *error = [NSError ErrorWithUnderlying:nil
                      localizedDescriptionKey:NSLocalizedString(@"Could not register thread", nil)
                  localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                  errorDomain:EndpointErrorDomain
                                    errorCode:SBSEndpointErrorCannotRegisterThread];
        return NO;
      }
    }
    
  }
  
  // Disable any remaining unmatched codecs
  for (NSString *codecIdentifier in unmatchedCodecs) {
    NSLog(@"Codec %@ not found in priority list, disabling", codecIdentifier);
    
    pj_str_t codec_identifier = codecIdentifier.pjString;
    status = pjsua_codec_set_priority(&codec_identifier, 0);
    if (status != PJ_SUCCESS) {
      *error = [NSError ErrorWithUnderlying:nil
                    localizedDescriptionKey:NSLocalizedString(@"Could not register thread", nil)
                localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                errorDomain:EndpointErrorDomain
                                  errorCode:SBSEndpointErrorCannotRegisterThread];
      return NO;
    }
  }
  
  return YES;
}

//------------------------------------------------------------------------------

- (SBSAccount *)findAccount:(NSUInteger)id {
  return self.accounts[@(id)];
}

//------------------------------------------------------------------------------

- (void)performAsync:(void (^)())block {
  [self performSelector:@selector(performAsyncWithBlock:) onThread:_backgroundThread withObject:[block copy] waitUntilDone:NO];
}

- (void)performAsyncWithBlock:(void (^)())block {
  block();
}

- (void)threadRunLoop:(id)object {
  @autoreleasepool {
    NSThread *thread = [NSThread currentThread];
    NSRunLoop *currentRunLoop = [NSRunLoop currentRunLoop];
    
    // If we dont register a mach port with the run loop, it will just exit immediately
    [currentRunLoop addPort: [NSPort port] forMode: NSRunLoopCommonModes];
    
    // Just loop until the thread is cancelled.
    while (!thread.cancelled) {
      [currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    }
    
    // Cleanup when we're done
    [currentRunLoop removePort:[NSPort port] forMode: NSRunLoopCommonModes];
    [[NSPort port] invalidate];
  }
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

//------------------------------------------------------------------------------

- (void)extractEndpointConfiguration:(SBSEndpointConfiguration *)configuration config:(pjsua_config *)config {
  pjsua_config_default(config);
  
  config->cb.on_reg_state        = &onRegState;
  config->cb.on_incoming_call    = &onIncomingCall;
  config->cb.on_call_state       = &onCallState;
  config->cb.on_call_media_state = &onCallMediaState;
  config->cb.on_call_tsx_state   = &onCallTsxState;
  
  config->max_calls = (unsigned int) configuration.maxCalls;
}

//------------------------------------------------------------------------------

- (void)extractMediaConfiguration:(SBSEndpointConfiguration *)configuration config:(pjsua_media_config *)config {
  pjsua_media_config_default(config);
  
  config->clock_rate     = (unsigned int) configuration.clockRate == 0 ? PJSUA_DEFAULT_CLOCK_RATE : (unsigned int) configuration.clockRate;
  config->snd_clock_rate = (unsigned int) configuration.sndClockRate;
}

//------------------------------------------------------------------------------

- (void)convertTransportConfiguration:(SBSTransportConfiguration *)configuration config:(pjsua_transport_config *)config {
  pjsua_transport_config_default(config);
  
  config->port       = (unsigned int) configuration.port;
  config->port_range = (unsigned int) configuration.portRange;
}

//------------------------------------------------------------------------------

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

static void onCallTsxState(pjsua_call_id callId, pjsip_transaction *tsx, pjsip_event *event) {
  void *data = pjsua_call_get_user_data(callId);
  if (data == NULL) {
    return;
  }
  
  SBSCall *call = (__bridge SBSCall *) data;
  [call.account handleCallTsxStateChange:callId transation:tsx];
}

@end
