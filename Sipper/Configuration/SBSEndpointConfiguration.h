//
//  SipperEndpointConfiguration.h
//  Sipper
//
//  Created by Colin Morelli on 4/20/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#ifndef SBSEndpointConfiguration_h
#define SBSEndpointConfiguration_h

#import <Foundation/Foundation.h>
#import "SBSConstants.h"

typedef void (^LoggingHandler)(SBSLogLevel, NSString *_Nonnull);

@interface SBSEndpointConfiguration : NSObject

/**
 *  Maximum calls to support.
 *
 *  The value specified here must be smaller than the compile time maximum settings PJSUA_MAX_CALLS,
 *  which by default is 32. To increase this limit, the library must be recompiled with new PJSUA_MAX_CALLS value.
 *
 *  Default value: 4
 */
@property(nonatomic) NSUInteger maxCalls;

/**
 *  Input verbosity level
 *
 *  Default value: 5
 */
@property(nonatomic) NSUInteger logLevel;

/**
 *  Verbosity level for console.
 *
 *  Default value: 4
 */
@property(nonatomic) NSUInteger logConsoleLevel;

/**
 *  Optional log filename.
 *
 *  Default value: nil
 */
@property(strong, nonatomic, nullable) NSString *logFilename;

/**
 *  Additional flags to be given to pj_file_open() when opening the log file.
 *
 *  By default, the flag is PJ_O_WRONLY.
 *  Application may set PJ_O_APPEND here so that logs are appended to existing file instead of overwriting it.
 *
 *  Default value: PJ_O_APPEND
 */
@property(nonatomic) NSUInteger logFileFlags;

/**
 * Block to invoke for each log message
 *
 * This method will only be invoked for log messages printed at a level higher than
 * the configured level
 */
@property(strong, nonatomic, nullable) LoggingHandler loggingCallback;

/**
 *  Clock rate to be applied to the conference bridge.
 *
 *  If value is zero, default clock rate will be used (PJSUA_DEFAULT_CLOCK_RATE).
 *
 *  Default value: 16000
 */
@property(nonatomic) NSUInteger clockRate;

/**
 *  Clock rate to be applied when opening the sound device.
 *
 *  If value is zero, conference bridge clock rate will be used.
 *
 *  Default value: 0
 */
@property(nonatomic) NSUInteger sndClockRate;

/**
 *  An array which will hold all the configured transports.
 */
@property(strong, nonatomic, nonnull) NSArray *transportConfigurations;

/**
 *  The thread priority to assign to the background thread that handles SIP manipulation.
 *
 *  Default value: 0.5
 */
@property(nonatomic) double backgroundThreadPriority;

/**
 *  Determines if Sipper should retain transports for the duration of active calls
 *
 *  When enabled, Sipper increases the ref-count on transports for the duration of the call. This will prevent
 *  the transport from being destroyed for as long as the call is active. By default, this is active, because it
 *  is hard to imagine a case in which this wouldn't be wanted on devices that are practically always behind a
 *  NAT. However, it can be disabled.
 *
 *  Default value: true
 */
@property(nonatomic) BOOL preserveConnectionsForCalls;

/**
 *  The value to place in the SIP User-Agent header field
 *
 *  Leaving this value as nil wil use the underlying User-Agent of the provider framework.
 *
 *  Default value: nil
 */
@property(nonatomic, strong, nullable) NSString *userAgent;

/**
 *  To check if the endpoint has a tcp configuration.
 *
 *  @return BOOL
 */
- (BOOL)hasTCPConfiguration;

@end

#endif
