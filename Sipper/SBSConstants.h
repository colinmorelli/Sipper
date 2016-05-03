//
//  SBSConstants.h
//  Sipper
//
//  Created by Colin Morelli on 4/21/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#ifndef SBSConstants_h
#define SBSConstants_h

#import <Foundation/Foundation.h>

/**
 *  Available logging levels
 */
typedef NS_ENUM(NSInteger, SBSLogLevel) {
  SBSLogLevelTrace = 6,
  SBSLogLevelDebug = 5,
  SBSLogLevelInfo  = 4,
  SBSLogLevelWarn  = 3,
  SBSLogLevelError = 2,
  SBSLogLevelFatal = 1
};

/**
 *  Available SIP status codes
 */
typedef NS_ENUM(NSInteger, SBSStatusCode) {
  SBSStatusCodeTrying = 100,
  SBSStatusCodeRinging = 180,
  SBSStatusCodeCallBeingForwarded = 181,
  SBSStatusCodeQueued = 182,
  SBSStatusCodeProgress = 183,
  
  SBSStatusCodeOk = 200,
  SBSStatusCodeAccepted = 202,
  
  SBSStatusCodeMultipleChoices = 300,
  SBSStatusCodeMovedPermanently = 301,
  SBSStatusCodeMovedTemporarily = 302,
  SBSStatusCodeUseProxy = 305,
  SBSStatusCodeAlternativeService = 380,
  
  SBSStatusCodeBadRequest = 400,
  SBSStatusCodeUnauthorized = 401,
  SBSStatusCodePaymentRequired = 402,
  SBSStatusCodeForbidden = 403,
  SBSStatusCodeNotFound = 404,
  SBSStatusCodeMethodNotAllowed = 405,
  SBSStatusCodeNotAcceptable = 406,
  SBSStatusCodeProxyAuthenticationRequired = 407,
  SBSStatusCodeRequestTimeout = 408,
  SBSStatusCodeGone = 410,
  SBSStatusCodeRequestEntityTooLarge = 413,
  SBSStatusCodeRequestUriTooLong = 414,
  SBSStatusCodeUnsupportedMediaType = 415,
  SBSStatusCodeUnsupportedUriScheme = 416,
  SBSStatusCodeBadExtension = 420,
  SBSStatusCodeExtensionRequired = 421,
  SBSStatusCodeSessionTimerTooSmall = 422,
  SBSStatusCodeIntervalTooBrief = 423,
  SBSStatusCodeTemporarilyUnavailable = 480,
  SBSStatusCodeCallTsxDoesNotExist = 481,
  SBSStatusCodeLoopDetected = 482,
  SBSStatusCodeTooManyHops = 483,
  SBSStatusCodeAddressIncomplete = 484,
  SBSStatusCodeAmbiguous = 485,
  SBSStatusCodeBusyHere = 486,
  SBSStatusCodeRequestTerminated = 487,
  SBSStatusCodeNotAcceptableHere = 488,
  SBSStatusCodeBadEvent = 489,
  SBSStatusCodeRequestUpdated = 490,
  SBSStatusCodeRequestPending = 491,
  SBSStatusCodeUndecipherable = 493,
  
  SBSStatusCodeInternalServerError = 500,
  SBSStatusCodeNotImplemented = 501,
  SBSStatusCodeBadGateway = 502,
  SBSStatusCodeServiceUnavailable = 503,
  SBSStatusCodeServerTimeout = 504,
  SBSStatusCodeVersionNotSupported = 505,
  SBSStatusCodeMessageTooLarge = 513,
  SBSStatusCodePreconditionFailure = 580,
  
  SBSStatusCodeBusyEverywhere = 600,
  SBSStatusCodeDecline = 603,
  SBSStatusCodeDoesNotExistAnywhere = 604,
  SBSStatusCodeNotAcceptableAnywhere = 606,
  
  SBSStatusCodeTsxTimeout = SBSStatusCodeRequestTimeout,
  SBSStatusCodeTsxTransportError = SBSStatusCodeServiceUnavailable,
};

#endif /* SBSConstants_h */
