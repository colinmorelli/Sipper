//
//  SipperTransportConfiguration.h
//  Sipper
//
//  Created by Colin Morelli on 4/20/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#ifndef SBSTransportConfiguration_h
#define SBSTransportConfiguration_h

#import <Foundation/Foundation.h>

/**
 *  The available transports to configure.
 */
typedef NS_ENUM(NSUInteger, SBSTransportType) {
  SBSTransportTypeUDP,
  SBSTransportTypeTCP,
  SBSTransportTypeUDP6,
  SBSTransportTypeTCP6,
  SBSTransportTypeTLS,
  SBSTransportTypeTLS6
};

@interface SBSTransportConfiguration : NSObject

/**
 *  The transport type that should be used.
 */
@property (nonatomic) SBSTransportType transportType;

/**
 *  The port on which the communication should be set up.
 */
@property (nonatomic) NSUInteger port;

/**
 *  The port range that should be used.
 */
@property (nonatomic) NSUInteger portRange;

/**
 *  This function will init a SBSTransportConfiguration with default settings
 *
 *  @param transportType Transport type that will be set.
 *
 *  @return SBSTransportConfiguration instance.
 */
+ (instancetype)configurationWithTransportType:(SBSTransportType)transportType;

@end

#endif