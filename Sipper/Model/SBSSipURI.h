//
//  SBSSipURI.h
//  Sipper
//
//  Created by Colin Morelli on 4/21/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SBSSipURI : NSObject

/**
 * The account portion of the SIP URI (before the password and @ sign)
 */
@property(strong, nullable, nonatomic, readonly) NSString *account;

/**
 * The password portion of the SIP URI (after a colon, before the @ sign)
 */
@property(strong, nullable, nonatomic, readonly) NSString *password;

/**
 * The host portion of the SIP URI (after the @ sign, before a port number)
 */
@property(strong, nullable, nonatomic, readonly) NSString *host;

/**
 * The port number of the SIP URI (after the host, before query parameters)
 */
@property(strong, nullable, nonatomic, readonly) NSNumber *port;

/**
 * The query parameters of the SIP URI (anything after the string)
 */
@property(strong, nullable, nonatomic, readonly) NSString *params;

/**
 * Attempt to construct a SIP URI from the provided string
 *
 * @param uri the SIP URI to parse
 * @return a SBSSipUri instance, if the uri was parsed
 */
+ (instancetype _Nullable)sipUriWithString:(NSString *_Nonnull)uri;

@end
