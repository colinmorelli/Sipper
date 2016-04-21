//
//  SipperEndpointConfiguration.m
//  Sipper
//
//  Created by Colin Morelli on 4/20/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSEndpointConfiguration.h"
#import "SBSTransportConfiguration.h"
#import <pjsua.h>

static NSUInteger const EndpointConfigurationMaxCalls = 4;
static NSUInteger const EndpointConfigurationLogLevel = 5;
static NSUInteger const EndpointConfigurationLogConsoleLevel = 4;
static NSString * const EndpointConfigurationLogFileName = nil;
static NSUInteger const EndpointConfigurationClockRate = PJSUA_DEFAULT_CLOCK_RATE;
static NSUInteger const EndpointConfigurationSndClockRate = 0;

@implementation SBSEndpointConfiguration

- (instancetype)init {
  if (self = [super init]) {
    self.maxCalls = EndpointConfigurationMaxCalls;
    
    self.logLevel = EndpointConfigurationLogLevel;
    self.logConsoleLevel = EndpointConfigurationLogConsoleLevel;
    self.logFilename = EndpointConfigurationLogFileName;
    self.logFileFlags = PJ_O_APPEND;
    
    self.clockRate = EndpointConfigurationClockRate;
    self.sndClockRate = EndpointConfigurationSndClockRate;
  }
  return self;
}

- (NSArray *)transportConfigurations {
  if (!_transportConfigurations) {
    _transportConfigurations = [NSArray array];
  }
  return _transportConfigurations;
}

- (void)setLogLevel:(NSUInteger)logLevel {
  NSAssert(logLevel > 0, @"Log level needs to be set higher than 0");
  _logLevel = logLevel;
}

- (void)setLogConsoleLevel:(NSUInteger)logConsoleLevel {
  NSAssert(logConsoleLevel > 0, @"Console log level needs to be higher than 0");
  _logConsoleLevel = logConsoleLevel;
}

- (BOOL)hasTCPConfiguration {
  NSUInteger index = [self.transportConfigurations indexOfObjectPassingTest:^BOOL(SBSTransportConfiguration *transportConfiguration, NSUInteger idx, BOOL *stop) {
    if (transportConfiguration.transportType == SBSTransportTypeTCP || transportConfiguration.transportType == SBSTransportTypeTCP6) {
      *stop = YES;
      return YES;
    }
    return NO;
  }];
  
  return index != NSNotFound;
}

@end
