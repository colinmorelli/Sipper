//
//  SipperTransportConfiguration.m
//  Sipper
//
//  Created by Colin Morelli on 4/20/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSTransportConfiguration.h"

static NSInteger const TransportConfigurationPort = 5060;
static NSInteger const TransportConfigurationPortRange = 0;

@implementation SBSTransportConfiguration

//------------------------------------------------------------------------------

- (instancetype)init {
  if (self = [super init]) {
    self.port = TransportConfigurationPort;
    self.portRange = TransportConfigurationPortRange;
    self.transportType = SBSTransportTypeTCP;
  }
  return self;
}

//------------------------------------------------------------------------------

+ (instancetype)configurationWithTransportType:(SBSTransportType)transportType {
  SBSTransportConfiguration *transportConfiguration = [[SBSTransportConfiguration alloc] init];
  transportConfiguration.transportType = transportType;
  return transportConfiguration;
}

@end
