//
//  SBSNameAddressPairTests.m
//  Sipper
//
//  Created by Colin Morelli on 5/3/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "SBSNameAddressPair.h"

@interface SBSNameAddressPairTests : XCTestCase

@end

@implementation SBSNameAddressPairTests

- (void)setUp {
  [super setUp];
  // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
  // Put teardown code here. This method is called after the invocation of each test method in the class.
  [super tearDown];
}

- (void)testNameAddressPairWithOnlyUrl {
  SBSNameAddressPair *pair = [SBSNameAddressPair nameAddressPairFromString:@"sip:12345@mydomain.com"];
  
  XCTAssertNotNil(pair, @"Expected a valid SIP address to be returned");
  // This is an example of a functional test case.
  // Use XCTAssert and related functions to verify your tests produce the correct results.
}

@end