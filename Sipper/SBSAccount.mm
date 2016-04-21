//
//  SipperAccount.m
//  Sipper
//
//  Created by Colin Morelli on 4/20/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSAccount.h"

#import <Foundation/Foundation.h>
#import <pjsua2/account.hpp>
#import <pjsua2/call.hpp>

#import "NSError+SipperError.h"

#import "SBSEndpoint.h"
#import "SBSEndpointConfiguration.h"

static NSString * const AccountErrorDomain = @"sipper.account.error";

//
// MARK: PJSIP Subclass
//
typedef void (^RegistrationStateHandler)(bool registered, int code);

class SBSAccountWrapper : public pj::Account
{
public:
  SBSAccountWrapper() {}
  ~SBSAccountWrapper() {}
  
  RegistrationStateHandler onRegistrationStateChange;
  
  virtual void onRegState(pj::OnRegStateParam &prm)
  {
    pj::AccountInfo info = getInfo();
    bool registered = info.regIsActive;
    pjsip_status_code code = info.regStatus;

    // Invoke the registration state change handler
    if (onRegistrationStateChange != NULL) {
      onRegistrationStateChange(registered, code);
    }
  }
  
  virtual void onIncomingCall(pj::OnIncomingCallParam &iprm)
  {
    pj::Call *call = new pj::Call(*this, iprm.callId);
    pj::CallOpParam prm;
    prm.statusCode = PJSIP_SC_OK;
    call->answer(prm);
  }
  
};

@interface SBSAccount ()

@property (nonatomic) SBSEndpoint *endpoint;
@property (nonatomic) SBSAccountWrapper *account;

@end

@implementation SBSAccount

- (instancetype)initWithIdentifier:(NSString *)identifier configuration:(SBSAccountConfiguration *)configuration endpoint:(SBSEndpoint *)endpoint {
  if (self = [super init]) {
    _endpoint = endpoint;
    _id = identifier;
    _configuration = configuration;
  }
  
  return self;
}

- (void)start {
  
  // Starts registration with the endpoint
  try {
    self.account->setRegistration(true);
  } catch (pj::Error& err) {
    NSError *error = [NSError ErrorWithUnderlying:nil
                          localizedDescriptionKey:NSLocalizedString(@"Could not register account", nil)
                      localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), err.status]
                                      errorDomain:AccountErrorDomain
                                        errorCode:SBSAccountErrorCannotRegister];

    [self.delegate account:self registrationDidFailWithError:error];
  }
}

- (BOOL)createWithError:(NSError *__autoreleasing *)error {
  
  // Convert the account configuration
  self.account = new SBSAccountWrapper;
  
  try {
    self.account->create([self convertAccountConfiguration:self.configuration]);
  } catch (pj::Error& err) {
    *error = [NSError ErrorWithUnderlying:nil
                  localizedDescriptionKey:NSLocalizedString(@"Could not create account", nil)
              localizedFailureReasonError:[NSString stringWithFormat:NSLocalizedString(@"PJSIP status code: %d", nil), err.status]
                              errorDomain:AccountErrorDomain
                                errorCode:SBSAccountErrorCannotCreate];
    return NO;
  }
  
  // Register event handlers with the registration state manager, and invoke the delegate method
  self.account->onRegistrationStateChange = ^(bool active, int code) {
    if (PJSIP_IS_STATUS_IN_CLASS(code, 100) || PJSIP_IS_STATUS_IN_CLASS(code, 300)) {
      [self.delegate account:self registrationDidChangeState:SBSAccountRegistrationStateTrying withStatusCode:code];
    } else if (PJSIP_IS_STATUS_IN_CLASS(code, 200)) {
      [self.delegate account:self registrationDidChangeState:SBSAccountRegistrationStateActive withStatusCode:code];
    } else {
      [self.delegate account:self registrationDidChangeState:SBSAccountRegistrationStateInactive withStatusCode:code];
    }
  };
  
  return YES;
}

//
// MARK: Converters
//

- (pj::AccountConfig)convertAccountConfiguration:(SBSAccountConfiguration *)configuration {
  NSString *tcp = @"";
  if ([self.endpoint.configuration hasTCPConfiguration]) {
    tcp = @";transport=tcp";
  }
  
  // Create defaults for some of our variables
  NSString *registrarUri = self.configuration.sipRegistrarServer, *proxyUri = self.configuration.sipProxyServer;
  if (proxyUri == nil) {
    proxyUri = [@"sip:" stringByAppendingString:self.configuration.sipDomain];
  }
  
  if (registrarUri == nil) {
    registrarUri = proxyUri;
  }
  
  pj::AccountConfig config          = pj::AccountConfig();
  config.idUri                      = std::string(self.configuration.sipAddress.UTF8String);
  config.regConfig.registrarUri     = std::string(registrarUri.UTF8String);
  config.regConfig.registerOnAdd    = NO;
  config.regConfig.timeoutSec       = 800;
  config.regConfig.retryIntervalSec = (int) self.configuration.sipRegistrationRetryTimeout;
  config.presConfig.publishEnabled  = self.configuration.sipPublishEnabled;
  
  if (proxyUri != nil) {
    config.sipConfig.proxies.push_back([proxyUri stringByAppendingString:tcp].UTF8String);
  }
  
  if (self.configuration.sipAccount != nil) {
    config.sipConfig.authCreds.push_back(
      pj::AuthCredInfo(
        std::string([self convertAuthenticationScheme:self.configuration.sipAuthScheme].UTF8String),
        std::string(self.configuration.sipAuthRealm.UTF8String),
        std::string(self.configuration.sipAccount.UTF8String),
        0,
        std::string(self.configuration.sipPassword.UTF8String)
      )
    );
  }
  
  return config;
}

- (NSString *)convertAuthenticationScheme:(SBSAuthenticationScheme)scheme {
  switch (self.configuration.sipAuthScheme) {
    case SBSAuthenticationSchemeDigest:
      return @"digest";
  }
  
  return nil;
}

@end