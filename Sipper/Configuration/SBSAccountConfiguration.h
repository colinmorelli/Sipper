//
//  SipperAccountConfiguration.h
//  Sipper
//
//  Created by Colin Morelli on 4/20/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#ifndef SBSAccountConfiguration_h
#define SBSAccountConfiguration_h

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SBSAuthenticationScheme) {
    SBSAuthenticationSchemeDigest
};

typedef NS_ENUM(NSInteger, SBSSecureMediaPolicy) {
    SBSSecureMediaPolicyNone,
    SBSSecureMediaPolicyOptional,
    SBSSecureMediaPolicyRequired
};

@interface SBSAccountConfiguration : NSObject

/**
 *  The account that should be used when authenticate on remote PBX.
 */
@property(strong, nonatomic, nonnull) NSString *sipAccount;

/**
 *  The password that should be used when authenticate on remote PBX.
 */
@property(strong, nonatomic, nonnull) NSString *sipPassword;

/**
 *  The domain where the PBX can be found.
 */
@property(strong, nonatomic, nonnull) NSString *sipDomain;

/**
 *  The proxy address where to connect to. Defaults to sipDomain if unset.
 */
@property(strong, nonatomic, nullable) NSString *sipProxyServer;

/**
 *  The address of the registrar server to register with. Defaults to sipProxyServer if unset.
 */
@property(strong, nonatomic, nullable) NSString *sipRegistrarServer;

/**
 *  The address which is a combination of sipAccount & sipDomain.
 */
@property(readonly, nonatomic, nonnull) NSString *sipAddress;

/**
 *  Custom headers to send along with a registration attempt
 */
@property(strong, nonatomic, nullable) NSDictionary<NSString *, NSString *> *registrationHeaders;

/**
 *  Default headers to apply to all outbound calls
 */
@property(strong, nonatomic, nullable) NSDictionary<NSString *, NSString *> *defaultCallHeaders;

/**
 *  User data to associate with the account
 */
@property(strong, nonatomic, nullable) NSDictionary<NSString *, NSObject *> *userData;

/**
 *  The authentication realm.
 *
 *  Default: *
 */
@property(strong, nonatomic) NSString *_Nonnull sipAuthRealm;

/**
 *  The authentication scheme.
 *
 *  Default: digest
 */
@property(nonatomic) SBSAuthenticationScheme sipAuthScheme;

/**
 *  The secure media policy
 *
 *  Default: optional
 */
@property(nonatomic) SBSSecureMediaPolicy secureMediaPolicy;

/**
 *  Sets the duration that registrations are active for before resetting
 *
 *  Default: 600 seconds
 */
@property(nonatomic) NSUInteger sipRegistrationLifetime;

/**
 *  Sets the duration to wait when registration fails. Set to 0 to disable.
 *
 *  Default: 5 minutes
 */
@property(nonatomic) NSUInteger sipRegistrationRetryTimeout;

/**
 *  If YES, the account presence will be published to the server where the account belongs.
 */
@property(nonatomic) BOOL sipPublishEnabled;

@end

#endif
