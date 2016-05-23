//
//  SipperTests.m
//  SipperTests
//
//  Created by Colin Morelli on 5/3/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "NSString+PJString.h"
#import "SBSEndpoint.h"
#import "SBSAccount.h"
#import "SBSAccountConfiguration.h"
#import "SBSEndpointConfiguration.h"
#import "SBSTransportConfiguration.h"

@interface SipperTests : XCTestCase

@end

@implementation SipperTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testExample {
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct results.
}

- (void)testPerformanceExample {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
    }];
}

- (void)testSomething {
  SBSEndpointConfiguration *configuration = [[SBSEndpointConfiguration alloc] init];
  configuration.transportConfigurations = @[[SBSTransportConfiguration configurationWithTransportType:SBSTransportTypeTCP]];
  
  SBSAccountConfiguration *accountConfiguration = [[SBSAccountConfiguration alloc] init];
  accountConfiguration.sipProxyServer = @"sip:127.0.0.1:5080;transport=tcp";
  accountConfiguration.sipDomain = @"test.com";
  accountConfiguration.sipAccount = @"test";
  accountConfiguration.sipPassword = @"asdf";
  
  SBSEndpoint *endpoint = [SBSEndpoint sharedEndpoint];
  [endpoint initializeEndpointWithConfiguration:configuration error:nil];
  SBSAccount *account = [endpoint createAccountWithConfiguration:accountConfiguration error:nil];
  [account startRegistration];

  [NSThread sleepForTimeInterval:10.0];
}

@end
