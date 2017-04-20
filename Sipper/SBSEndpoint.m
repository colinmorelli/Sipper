//
//  SipperEndpoint.m
//  Sipper
//
//  Created by Colin Morelli on 4/20/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSEndpoint.h"

#if TARGET_OS_IPHONE
#endif

#import "NSString+PJString.h"
#import "NSError+SipperError.h"

#import "SBSAccount+Internal.h"
#import "SBSCall+Internal.h"
#import "SBSCodecDescriptor.h"
#import "SBSEndpointConfiguration.h"
#import "SBSTransportConfiguration.h"
#import "SBSRingbackDescription.h"
#import "pj_nat64.h"
#import <pjsua.h>
#import <pjsua-lib/pjsua_internal.h>

static NSString *const EndpointErrorDomain = @"sipper.endpoint.error";

#pragma mark - Forward Declarations

static void onLogMessage(int, const char *, int);
static void onRegState(pjsua_acc_id accountId, pjsua_reg_info *info);
static void onRegStarted(pjsua_acc_id accountId, pjsua_reg_info *info);
static void onCallState(pjsua_call_id callId, pjsip_event *event);
static void onIncomingCall(pjsua_acc_id accountId, pjsua_call_id callId, pjsip_rx_data *rdata);
static void onCallMediaState(pjsua_call_id callId);
static void onCallTsxState(pjsua_call_id callId, pjsip_transaction *tsx, pjsip_event *event);
static void onTransportState(pjsip_transport *transport, pjsip_transport_state state, const pjsip_transport_state_info *info);
static void onSdpCreated(pjsua_call_id callId, pjmedia_sdp_session *sdp, pj_pool_t *pool, const pjmedia_sdp_session *remote);
static void onCreateMediaTransportSrtp(pjsua_call_id call_id, unsigned media_idx, pjmedia_srtp_setting *srtp_opt);

#pragma mark - Endpoint

@interface SBSEndpoint () {
  pj_thread_desc pjBackgroundThreadDesc;
  pj_thread_t *pjBackgroundThread;
  pjmedia_port *pjRingbackPort;
  pjsua_conf_port_id pjRingbackConfPort;
}

@property(strong, nonatomic) NSArray *activeTransports;
@property(strong, nonatomic) NSThread *backgroundThread;
@property(strong, nonatomic) NSMutableDictionary *accountsDictionary;
@property(strong, nonatomic) NSMutableDictionary *accountsMap;
@property(strong, nonatomic) NSSet<NSNumber *> *ringingCalls;
@property(nonatomic) BOOL playingRingback;

@end

@implementation SBSEndpoint

//------------------------------------------------------------------------------

- (instancetype)init {
  if (self = [super init]) {
    _backgroundThread = [[NSThread alloc] initWithTarget:self selector:@selector(threadRunLoop:) object:nil];
    _backgroundThread.name = @"com.switchboard.sipper.background";
    _accountsDictionary = [[NSMutableDictionary alloc] init];
    _accountsMap = [[NSMutableDictionary alloc] init];
    _activeTransports = [NSArray array];
    _state = SBSEndpointStateIdle;
    _ringbackDescription = [SBSRingbackDescription usRingback];
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
              localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP error %d: %@", nil), status, fromPjError(status)]
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
              localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP error %d: %@", nil), status, fromPjError(status)]
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
                localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP error %d: %@", nil), status, fromPjError(status)]
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
              localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP error %d: %@", nil), status, fromPjError(status)]
                              errorDomain:EndpointErrorDomain
                                errorCode:SBSEndpointErrorCannotAddTransportConfiguration];
    return NO;
  }
  
  // Assign a thread priority. Answering/hanging up/calling is done on this background thread, so you probably
  // want a high thread priority to ensure the user isn't waiting on these actions to happen.
  _backgroundThread.threadPriority = configuration.backgroundThreadPriority;
  
  // Start the background thread
  [_backgroundThread start];
  
  // Perform a block to register the background thread
  [self performSelector:@selector(performAsyncWithBlock:) onThread:_backgroundThread withObject:^{
    status = pj_thread_register("background", pjBackgroundThreadDesc, &pjBackgroundThread);
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
  
  // Enable NAT64 rewrite
  status = pj_nat64_enable_rewrite_module();
  pj_nat64_set_options(NAT64_REWRITE_INCOMING_SDP);
  if (status != PJ_SUCCESS) {
    [self destroyEndpointWithError:nil];
    *error = [NSError ErrorWithUnderlying:nil
                  localizedDescriptionKey:NSLocalizedString(@"Could not enable the NAT64 rewriting module", nil)
              localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                              errorDomain:EndpointErrorDomain
                                errorCode:SBSEndpointErrorCannotRegisterThread];
    return NO;
  }
  
  // Disable sound device by default
  pjsua_set_no_snd_dev();
  
  // Create a tone generator to use for ringback
  pj_str_t ringback = pj_str("ringback");
  int samples_per_frame = media_config.audio_frame_ptime *
                          media_config.clock_rate *
                          media_config.channel_count / 1000;
  
  status = pjmedia_tonegen_create2(pjsua_var.pool, &ringback,
                          media_config.snd_clock_rate,
                          media_config.channel_count,
                          samples_per_frame,
                          16,
                          PJMEDIA_TONEGEN_LOOP,
                          &pjRingbackPort);
  if (status != PJ_SUCCESS) {
    [self destroyEndpointWithError:nil];
    *error = [NSError ErrorWithUnderlying:nil
                  localizedDescriptionKey:NSLocalizedString(@"Could not create the tone generator", nil)
              localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                              errorDomain:EndpointErrorDomain
                                errorCode:SBSEndpointErrorCannotRegisterThread];
    return NO;
  }
  
  // Register tone generator with the conference bridge
  status = pjsua_conf_add_port(pjsua_var.pool, pjRingbackPort, &pjRingbackConfPort);
  if (status != PJ_SUCCESS) {
    [self destroyEndpointWithError:nil];
    *error = [NSError ErrorWithUnderlying:nil
                  localizedDescriptionKey:NSLocalizedString(@"Could not register the tone generator with the conference bridge", nil)
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
  return self.accountsMap[account.uuid] = account;
}

//------------------------------------------------------------------------------

- (void)removeAccount:(NSUUID *)id {
  SBSAccount *account = self.accountsMap[id];
  
  [account stopRegistration];
  [self.accountsMap removeObjectForKey:id];
}

//------------------------------------------------------------------------------

- (void)updatePreferredCodecs:(NSArray<SBSCodecDescriptor *> *)descriptors completion:(void (^)(BOOL, NSError *_Nullable))callback {
  [self performAsync:^{
    NSError *error;
    pj_status_t status;
    
    const unsigned codec_info_size = 64;
    unsigned codec_count = codec_info_size;
    pjsua_codec_info codec_info[codec_info_size];
    
    status = pjsua_enum_codecs(codec_info, &codec_count);
    if (status != PJ_SUCCESS) {
      error = [NSError ErrorWithUnderlying:nil
                   localizedDescriptionKey:NSLocalizedString(@"Could not register thread", nil)
               localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                               errorDomain:EndpointErrorDomain
                                 errorCode:SBSEndpointErrorCannotRegisterThread];
      callback(NO, error);
      return;
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
        status = pjsua_codec_set_priority(&codec_info[i].codec_id, priority);
        
        if (status != PJ_SUCCESS) {
          error = [NSError ErrorWithUnderlying:nil
                       localizedDescriptionKey:NSLocalizedString(@"Could not register thread", nil)
                   localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                   errorDomain:EndpointErrorDomain
                                     errorCode:SBSEndpointErrorCannotRegisterThread];
          callback(NO, error);
          return;
        }
      }
      
    }
    
    // Disable any remaining unmatched codecs
    for (NSString *codecIdentifier in unmatchedCodecs) {
      NSLog(@"Codec %@ not found in priority list, disabling", codecIdentifier);
      
      pj_str_t codec_identifier = codecIdentifier.pjString;
      status = pjsua_codec_set_priority(&codec_identifier, 0);
      if (status != PJ_SUCCESS) {
        error = [NSError ErrorWithUnderlying:nil
                     localizedDescriptionKey:NSLocalizedString(@"Could not register thread", nil)
                 localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), status]
                                 errorDomain:EndpointErrorDomain
                                   errorCode:SBSEndpointErrorCannotRegisterThread];
        callback(NO, error);
        return;
      }
    }
    
    callback(YES, nil);
    return;
  }];
 }

//------------------------------------------------------------------------------

- (SBSAccount *)findAccount:(NSUUID *)id {
  return self.accountsMap[id];
}

//------------------------------------------------------------------------------

- (void)handleReachabilityChange {
  
  // Destroy all existing transports - they're most likely not safe at this point
  for (NSValue *wrapper in _activeTransports) {
    pj_status_t status = pjsip_transport_shutdown((pjsip_transport *) wrapper.pointerValue);
    if (status != PJ_SUCCESS) {
      NSLog(@"Failed to close active transport: %d", status);
    }
  }
  
  // Now, handle reachability on all accounts, which should fan out to perform a
  // re-invite on all calls
  for (SBSAccount *account in self.accounts) {
    [account handleReachabilityChange];
  }
}

//------------------------------------------------------------------------------

- (void)updateDeviceSampleRate:(NSUInteger)rate {
  [self performAsync:^{
    pjsua_check_snd_dev_idle();
    
    // If audo is on, temporarily disable it
    if (_audioEnabled) {
      pjsua_set_no_snd_dev();
    }
    
    // Sound device is disabled, update the preferred hardware sample rate
    pjsua_var.media_cfg.snd_clock_rate = (unsigned int) rate;
    
    // Before we go re-enable audio, let's see if we actually need to do this
    if (_audioEnabled && pjsua_var.call_cnt > 0) {
      pjsua_set_snd_dev(PJMEDIA_AUD_DEFAULT_CAPTURE_DEV, PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV);
    } else {
      PJSUA_LOCK();
      pjsua_var.cap_dev = PJMEDIA_AUD_DEFAULT_CAPTURE_DEV;
      pjsua_var.play_dev = PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV;
      PJSUA_UNLOCK();
    }
  }];
}

//------------------------------------------------------------------------------

- (void)disableAudio {
  [self performAsync:^{
    pjsua_set_no_snd_dev();
    _audioEnabled = NO;
  }];
}

//------------------------------------------------------------------------------

- (void)enableAudio {
  [self performAsync:^{
    pjsua_set_snd_dev(PJMEDIA_AUD_DEFAULT_CAPTURE_DEV, PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV);
    _audioEnabled = YES;
  }];
}

//------------------------------------------------------------------------------

- (NSArray<SBSAccount *> *)accounts {
  return [_accountsMap allValues];
}

//------------------------------------------------------------------------------

- (NSArray<SBSCall *> *)calls {
  NSMutableArray<SBSCall *> *calls = [[NSMutableArray alloc] init];
  NSArray<SBSAccount *> *accounts = [self accounts];
  
  for (SBSAccount *account in accounts) {
    [calls addObjectsFromArray:account.allCalls];
  }
  
  return calls;
}

//------------------------------------------------------------------------------

- (void)performAsync:(void (^)())block {
  [self performSelector:@selector(performAsyncWithBlock:) onThread:_backgroundThread withObject:[block copy] waitUntilDone:NO];
}

//------------------------------------------------------------------------------

- (void)performAsyncWithBlock:(void (^)())block {
  block();
}

//------------------------------------------------------------------------------

- (void)reconcileState {
  NSUInteger activeCalls = 0, ringingCalls = 0, ringbackCalls = 0;
  
  // Check the status of all active calls
  for (SBSCall *call in self.calls) {
    if (call.state == SBSCallStateDisconnected || call.state == SBSCallStatePending) {
      continue;
    }
    
    if (call.direction == SBSCallDirectionOutbound || call.state == SBSCallStateConnecting || call.state == SBSCallStateActive) {
      activeCalls++;
    } else if (call.state == SBSCallStateIncoming || call.state == SBSCallStateEarly) {
      ringingCalls++;
    }
    
    // Call is in early state with no active media legs, which means we should be playing a ringback
    if (call.state == SBSCallStateEarly && call.media.count == 0) {
      ringbackCalls++;
    }
  }
  
  // Play a ringback tone if we need to
  if (ringbackCalls > 0 && !_playingRingback && _ringbackDescription != nil) {
    pjmedia_tone_desc tones[_ringbackDescription.tones.count];
    pj_bzero(&tones, sizeof(tones));
    int i = 0;
    
    for (SBSRingbackTone *tone in _ringbackDescription.tones) {
      tones[i].freq1 = tone.firstFrequency;
      tones[i].freq2 = tone.secondFrequency;
      tones[i].on_msec = tone.onMs;
      tones[i].off_msec = tone.offMs;
      i++;
    }
    
    if (i > 0) {
      tones[i - 1].off_msec = _ringbackDescription.intervalMs;
    }
    
    if (i > 0) {
      pjmedia_tonegen_play(pjRingbackPort, i, tones, PJMEDIA_TONEGEN_LOOP);
      pjsua_conf_connect(pjRingbackConfPort, 0);
      _playingRingback = YES;
    }
  } else if (ringbackCalls == 0 && _playingRingback) {
    pjsua_conf_disconnect(pjRingbackConfPort, 0);
    pjmedia_tonegen_stop(pjRingbackPort);
    pjmedia_tonegen_rewind(pjRingbackPort);
    _playingRingback = NO;
  }
  
  SBSEndpointState endpointState = SBSEndpointStateIdle;
  if (activeCalls > 0) {
    endpointState = SBSEndpointStateActiveCalls;
  } else if (ringingCalls > 0) {
    endpointState = SBSEndpointStateRingingCalls;
  }

  if (endpointState != _state) {
    _state = endpointState;
    
    dispatch_async(dispatch_get_main_queue(), ^{
      if ([self.delegate respondsToSelector:@selector(endpoint:didChangeState:)]) {
        [self.delegate endpoint:self didChangeState:endpointState];
      }
    });
  }
}

//------------------------------------------------------------------------------

- (void)threadRunLoop:(id)object {
  
  @autoreleasepool {
    NSThread *thread = [NSThread currentThread];
    NSRunLoop *currentRunLoop = [NSRunLoop currentRunLoop];
    
    // If we dont register a mach port with the run loop, it will just exit immediately
    [currentRunLoop addPort:[NSPort port] forMode:NSRunLoopCommonModes];
    
    // Just loop until the thread is cancelled.
    while (!thread.cancelled) {
      [currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    }
    
    // Cleanup when we're done
    [currentRunLoop removePort:[NSPort port] forMode:NSRunLoopCommonModes];
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
  
  config->level = (unsigned int) configuration.logLevel;
  config->console_level = (unsigned int) configuration.logConsoleLevel;
  config->log_filename = configuration.logFilename.pjString;
  config->log_file_flags = (unsigned int) configuration.logFileFlags;
  
  if (configuration.loggingCallback != nil) {
    config->cb = &onLogMessage;
  }
}

//------------------------------------------------------------------------------

- (void)extractEndpointConfiguration:(SBSEndpointConfiguration *)configuration config:(pjsua_config *)config {
  pjsua_config_default(config);
  
  config->cb.on_reg_state2 = &onRegState;
  config->cb.on_incoming_call = &onIncomingCall;
  config->cb.on_call_state = &onCallState;
  config->cb.on_call_media_state = &onCallMediaState;
  config->cb.on_call_tsx_state = &onCallTsxState;
  config->cb.on_reg_started2 = &onRegStarted;
  config->cb.on_transport_state = &onTransportState;
  config->cb.on_call_sdp_created = &onSdpCreated;
  config->cb.on_create_media_transport_srtp = &onCreateMediaTransportSrtp;
  
  if (configuration.userAgent != nil) {
    config->user_agent = configuration.userAgent.pjString;
  }
  
  config->max_calls = (unsigned int) configuration.maxCalls;
}

//------------------------------------------------------------------------------

- (void)extractMediaConfiguration:(SBSEndpointConfiguration *)configuration config:(pjsua_media_config *)config {
  pjsua_media_config_default(config);
  config->enable_ice = PJ_TRUE;
  config->ice_no_rtcp = PJ_TRUE;
  config->ice_max_host_cands = 12;
  config->snd_auto_close_time = 0;
  config->clock_rate = (unsigned int) configuration.clockRate == 0 ? PJSUA_DEFAULT_CLOCK_RATE : (unsigned int) configuration.clockRate;
  config->snd_clock_rate = (unsigned int) configuration.sndClockRate;
  config->no_vad = PJ_TRUE;
  config->jb_init = (int) configuration.jbInit;
  config->jb_min_pre = (int) configuration.jbMinPre;
  config->jb_max_pre = (int) configuration.jbMaxPre;
  config->jb_max = (int) configuration.jbMax;
}

//------------------------------------------------------------------------------

- (void)convertTransportConfiguration:(SBSTransportConfiguration *)configuration config:(pjsua_transport_config *)config {
  pjsua_transport_config_default(config);
  
  config->port = (unsigned int) configuration.port;
  config->port_range = (unsigned int) configuration.portRange;
}

//------------------------------------------------------------------------------

- (pjsip_transport_type_e)convertTransportType:(SBSTransportType)type {
  switch (type) {
      case SBSTransportTypeUDP:
      return PJSIP_TRANSPORT_UDP;
      case SBSTransportTypeUDP6:
      return PJSIP_TRANSPORT_UDP6;
      case SBSTransportTypeTCP:
      return PJSIP_TRANSPORT_TCP;
      case SBSTransportTypeTCP6:
      return PJSIP_TRANSPORT_TCP6;
      case SBSTransportTypeTLS:
      return PJSIP_TRANSPORT_TLS;
      case SBSTransportTypeTLS6:
      return PJSIP_TRANSPORT_TLS6;
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

static void onLogMessage(int level, const char *input, int length) {
  SBSLogLevel convertedLevel = (SBSLogLevel) level;
  NSString *string = [[NSString stringWithCString:input encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  
  LoggingHandler block = [SBSEndpoint sharedEndpoint].configuration.loggingCallback;
  if (block != nil) {
    block(convertedLevel, string);
  }
}

static void onRegState(pjsua_acc_id accountId, pjsua_reg_info *info) {
  void *data = pjsua_acc_get_user_data(accountId);
  if (data == NULL) {
    return;
  }
  
  @autoreleasepool {
    SBSAccount *account = (__bridge SBSAccount *) data;
    [account handleRegistrationStateChange:info];
  }
}

static void onIncomingCall(pjsua_acc_id accountId, pjsua_call_id callId, pjsip_rx_data *rdata) {
  void *data = pjsua_acc_get_user_data(accountId);
  if (data == NULL) {
    return;
  }
  
  @autoreleasepool {
    SBSAccount *account = (__bridge SBSAccount *) data;
    [account handleIncomingCall:callId data:rdata];
    [account.endpoint reconcileState];
  }
}

static void onCallState(pjsua_call_id callId, pjsip_event *event) {
  void *data = pjsua_call_get_user_data(callId);
  if (data == NULL) {
    return;
  }
  
  @autoreleasepool {
    SBSCall *call = (__bridge SBSCall *) data;
    [call handleCallStateChange];
    [call.account.endpoint reconcileState];
  }
}

static void onCallMediaState(pjsua_call_id callId) {
  void *data = pjsua_call_get_user_data(callId);
  if (data == NULL) {
    return;
  }
  
  @autoreleasepool {
    SBSCall *call = (__bridge SBSCall *) data;
    [call handleCallMediaStateChange];
    [call.account.endpoint reconcileState];
  }
}

static void onCallTsxState(pjsua_call_id callId, pjsip_transaction *tsx, pjsip_event *event) {
  void *data = pjsua_call_get_user_data(callId);
  if (data == NULL) {
    return;
  }
  
  @autoreleasepool {
    SBSCall *call = (__bridge SBSCall *) data;
    [call handleTransactionStateChange:tsx event:event];
    [call.account.endpoint reconcileState];
  }
}

static void onRegStarted(pjsua_acc_id accountId, pjsua_reg_info *info) {
  void *data = pjsua_acc_get_user_data(accountId);
  if (data == NULL) {
    return;
  }
  
  @autoreleasepool {
    SBSAccount *account = (__bridge SBSAccount *) data;
    [account handleRegistrationStarted:info];
  }
}

static void onSdpCreated(pjsua_call_id call_id, pjmedia_sdp_session *sdp, pj_pool_t *pool, const pjmedia_sdp_session *remote) {
  
}

static void onCreateMediaTransportSrtp(pjsua_call_id call_id, unsigned media_idx, pjmedia_srtp_setting *srtp_opt) {
  
}

static void onTransportState(pjsip_transport *transport, pjsip_transport_state state, const pjsip_transport_state_info *info) {
  @autoreleasepool {
    NSArray<NSValue *> *transports = [SBSEndpoint sharedEndpoint].activeTransports;
    
    @synchronized (transports) {
      unsigned flag = pjsip_transport_get_flag_from_type((pjsip_transport_type_e) transport->key.type);
      if (!(flag & PJSIP_TRANSPORT_DATAGRAM)) {
        
        // Transport is shutting down/destroying - clean it up since we don't need to track it now
        if (state == PJSIP_TP_STATE_SHUTDOWN || state == PJSIP_TP_STATE_DESTROY) {
          NSLog(@"Removing existing transport from array, before size: %lu", (unsigned long) [transports count]);
          transports = [transports filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSValue *_Nullable evaluatedObject, NSDictionary<NSString *, id> *_Nullable bindings) {
            return evaluatedObject.pointerValue != transport;
          }]];
          NSLog(@"Removing existing transport from array, after size: %lu", (unsigned long) [transports count]);
        } else {
          NSLog(@"Adding transport to array");
          transports = [transports arrayByAddingObject:[NSValue valueWithPointer:transport]];
        }
        
        [SBSEndpoint sharedEndpoint].activeTransports = transports;
      }
    }
    
    // Forward the transport state down to all accounts
    [[SBSEndpoint sharedEndpoint].accounts enumerateObjectsUsingBlock:^(SBSAccount *_Nonnull account, NSUInteger idx, BOOL *_Nonnull stop) {
      [account handleTransportStateChange:transport state:state info:info];
    }];
  }
}

static NSString *fromPjError(pj_status_t status) {
  char error_message[PJ_ERR_MSG_SIZE];
  pj_strerror(status, error_message, sizeof(error_message));
  return [NSString stringWithCString:error_message encoding:NSUTF8StringEncoding];
}

@end
