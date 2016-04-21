//
//  SipperTransportConfiguration.h
//  Sipper
//
//  Created by Colin Morelli on 4/20/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 *  The available transports to configure.
 */
typedef NS_ENUM(NSUInteger, SipperTransportType) {
  SipperTransportTypeUDP,
  SipperTransportTypeTCP,
  SipperTransportTypeUDP6,
  SipperTransportTypeTCP6
};

@interface SipperTransportConfiguration : NSObject

/**
 *  The transport type that should be used.
 */
@property (nonatomic) SipperTransportType transportType;

/**
 *  The port on which the communication should be set up.
 */
@property (nonatomic) NSUInteger port;

/**
 *  The port range that should be used.
 */
@property (nonatomic) NSUInteger portRange;

/**
 *  This function will init a VSLTransportConfiguration with default settings
 *
 *  @param transportType Transport type that will be set.
 *
 *  @return VSLTransportConfiguration instance.
 */
+ (instancetype)configurationWithTransportType:(SipperTransportType)transportType;

@end
