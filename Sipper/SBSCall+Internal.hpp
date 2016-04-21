//
//  SBSCall+Internal.h
//  Sipper
//
//  Created by Colin Morelli on 4/21/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#ifndef SBSCall_Internal_h
#define SBSCall_Internal_h

#import "SBSCall.h"

#import <pjsua2/account.hpp>
#import <pjsua2/call.hpp>

@interface SBSCall ()

/**
 * Creates a new instance of a call wrapper from the incoming PJSIP call
 *
 * @param account    the account instance that this call is for
 * @param underlying the PJSIP account underlying the SBSAccount
 * @param param      the incoming call parameters that can be parsed for metadata
 * @return new call instance
 */
+ (instancetype)incomingCallWithAccount:(SBSAccount *)account underlying:(pj::Account *)account incomingCallData:(pj::OnIncomingCallParam)param;

@end

#endif