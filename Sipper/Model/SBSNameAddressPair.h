//
//  SBSNameAddressPair.h
//  Sipper
//
//  Created by Colin Morelli on 4/21/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifndef SBSNameAddressPair_h
#define SBSNameAddressPair_h

#import "SBSSipURI.h"

@interface SBSNameAddressPair : NSObject

/**
 * Creates a new instance of the name/address pair
 *
 * @param name    the display name portion of the pair
 * @param address the address portion of the pair
 */
- (instancetype _Nonnull)initWithDisplayName:(NSString *_Nullable)name uri:(SBSSipURI *_Nonnull)uri;

/**
 * Creates a new instance of the name/address pair with just an address
 *
 * @param address the address portion of the URI (no name present)
 */
- (instancetype _Nonnull)initWithAddress:(SBSSipURI *_Nonnull)uri;

/**
 * The display name portion of the name/address pair
 */
@property(strong, nullable, readonly) NSString *name;

/**
 * The address portion of the name/address pair
 */
@property(strong, nonnull, readonly) SBSSipURI *uri;

/**
 * Attempts to parse a string as a name/address pair, if possible
 *
 * @param string the string to parse
 * @return an instance of the name/address pair, or nul
 */
+ (instancetype _Nullable)nameAddressPairFromString:(NSString *_Nonnull)string;

@end

#endif