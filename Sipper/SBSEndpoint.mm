//
//  SipperEndpoint.m
//  Sipper
//
//  Created by Colin Morelli on 4/20/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSEndpoint.h"

#import <pjsua2/endpoint.hpp>

#import "NSString+PJString.h"
#import "NSError+SipperError.h"

#import "SBSAccount.h"
#import "SBSEndpointConfiguration.h"
#import "SBSTransportConfiguration.h"

static NSString * const EndpointErrorDomain = @"sipper.endpoint.error";

//
// MARK: PJSIP Subclass
//
typedef void (^RegistrationStateHandler)(int x, int y);

class SBSEndpointWrapper : public pj::Endpoint
{
public:
  SBSEndpointWrapper() {}
  ~SBSEndpointWrapper() {}
  
};

//
// MARK: Implementation
//

@interface SBSEndpoint ()

@property (nonatomic) SBSEndpointWrapper *endpoint;
@property (strong, nonatomic) NSMutableDictionary *accounts;

@end

@implementation SBSEndpoint

- (instancetype)initWithEndpointConfiguration:(SBSEndpointConfiguration *)configuration {
  if (self = [super init]) {
    _configuration = configuration;
    _accounts = [[NSMutableDictionary alloc] init];
  }
  
  return self;
}

- (BOOL)initializeEndpointWithError:(NSError *__autoreleasing *)error {
  if (self.endpoint != nil) {
    return YES;
  }
  
  // Create the PJSUA endpoint here and load the required libraries
  try {
    self.endpoint = new SBSEndpointWrapper;
    self.endpoint->libCreate();
  } catch (pj::Error &err) {
    delete self.endpoint;
    self.endpoint = nil;

    *error = [NSError ErrorWithUnderlying:nil
                  localizedDescriptionKey:NSLocalizedString(@"Could not create endpoint", nil)
              localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), err.status]
                              errorDomain:EndpointErrorDomain
                                errorCode:SBSEndpointErrorCannotCreate];
    return NO;
  }
  
  // Initialize the endpoint with the new configuration
  try {
    self.endpoint->libInit([self convertEndpointConfiguration:self.configuration]);
  } catch (pj::Error& err) {
    [self destroyEndpointWithError:nil];
    *error = [NSError ErrorWithUnderlying:nil
                  localizedDescriptionKey:NSLocalizedString(@"Could not initialize endpoint", nil)
              localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), err.status]
                              errorDomain:EndpointErrorDomain
                                errorCode:SBSEndpointErrorCannotInitialize];
    return NO;
  }
  
  // Now, register all of the requested transports with the endpoint
  for (SBSTransportConfiguration *transportConfiguration in self.configuration.transportConfigurations) {
    try {
      self.endpoint->transportCreate([self convertTransportType:transportConfiguration.transportType], [self convertTransportConfiguration:transportConfiguration]);
    } catch (pj::Error& err) {
      [self destroyEndpointWithError:nil];
      *error = [NSError ErrorWithUnderlying:nil
                    localizedDescriptionKey:NSLocalizedString(@"Could not create transport", nil)
                localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), err.status]
                                errorDomain:EndpointErrorDomain
                                  errorCode:SBSEndpointErrorCannotAddTransportConfiguration];
      return NO;
    }
  }
  
  // And, finally, we can start the endpoint
  try {
    self.endpoint->libStart();
  } catch (pj::Error& err) {
    [self destroyEndpointWithError:nil];
    *error = [NSError ErrorWithUnderlying:nil
                  localizedDescriptionKey:NSLocalizedString(@"Could not start endpoint", nil)
              localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), err.status]
                              errorDomain:EndpointErrorDomain
                                errorCode:SBSEndpointErrorCannotStart];
    return NO;
  }
  
  // We're successful if we didn't set an error pointer
  return YES;
}

- (BOOL)destroyEndpointWithError:(NSError *__autoreleasing *)error {
  if (self.endpoint == nil) {
    return YES;
  }
  
  // Make sure we release the underlying PJSIP library
  self.endpoint->libDestroy();
  delete self.endpoint;
  self.endpoint = nil;
  return YES;
}

- (SBSAccount *)createAccountWithConfiguration:(SBSAccountConfiguration *)configuration error:(NSError *__autoreleasing *)error {
  NSString *identifier = [[NSUUID UUID] UUIDString];
  SBSAccount *account = [[SBSAccount alloc] initWithIdentifier:identifier configuration:configuration endpoint:self];
  
  // Attempt to create the account here
  if (![account createWithError:error]) {
    return nil;
  }
  
  // Successful creation, register the account with sipper
  return self.accounts[identifier] = account;
}

- (pj::EpConfig)convertEndpointConfiguration:(SBSEndpointConfiguration *)configuration {
  pj::EpConfig config = pj::EpConfig();
  config.logConfig.level        = (int) configuration.logLevel;
  config.logConfig.consoleLevel = (int) configuration.logConsoleLevel;
  config.uaConfig.maxCalls      = (int) configuration.maxCalls;
  config.medConfig.sndClockRate = (int) configuration.sndClockRate;
  config.medConfig.clockRate    = (int) configuration.clockRate;
  config.medConfig.threadCnt    = 1;
  
  // Enable logging to a file if requested
  if (configuration.logFilename != nil) {
    config.logConfig.fileFlags    = (int) configuration.logFileFlags;
    config.logConfig.filename     = std::string([configuration.logFilename UTF8String]);
  }
  
  return config;
}

- (pj::TransportConfig)convertTransportConfiguration:(SBSTransportConfiguration *)configuration {
  pj::TransportConfig config = pj::TransportConfig();
  config.port      = (int) configuration.port;
  config.portRange = (int) configuration.portRange;
  return config;
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

@end
