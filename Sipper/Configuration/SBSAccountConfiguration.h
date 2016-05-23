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
@property (strong, nonatomic) NSString * _Nonnull sipAccount;

/**
 *  The password that should be used when authenticate on remote PBX.
 */
@property (strong, nonatomic) NSString * _Nonnull sipPassword;

/**
 *  The domain where the PBX can be found.
 */
@property (strong, nonatomic) NSString * _Nonnull sipDomain;

/**
 *  The proxy address where to connect to. Defaults to sipDomain if unset.
 */
@property (strong, nonatomic) NSString * _Nullable sipProxyServer;

/**
 *  The address of the registrar server to register with. Defaults to sipProxyServer if unset.
 */
@property (strong, nonatomic) NSString * _Nullable sipRegistrarServer;

/**
 *  The address which is a combination of sipAccount & sipDomain.
 */
@property (readonly, nonatomic) NSString * _Nonnull sipAddress;

/**
 *  The authentication realm.
 *
 *  Default: *
 */
@property (strong, nonatomic) NSString * _Nonnull sipAuthRealm;

/**
 *  The authentication scheme.
 *
 *  Default: digest
 */
@property (nonatomic) SBSAuthenticationScheme sipAuthScheme;

/**
 *  The secure media policy
 *
 *  Default: optional
 */
@property (nonatomic) SBSSecureMediaPolicy secureMediaPolicy;

/**
 *  Sets the duration that registrations are active for before resetting
 *
 *  Default: 600 seconds
 */
@property (nonatomic) NSUInteger sipRegistrationLifetime;

/**
 *  Sets the duration to wait when registration fails. Set to 0 to disable.
 *
 *  Default: 5 minutes
 */
@property (nonatomic) NSUInteger sipRegistrationRetryTimeout;

/**
 *  If YES, the account presence will be published to the server where the account belongs.
 */
@property (nonatomic) BOOL sipPublishEnabled;

@end

#endif