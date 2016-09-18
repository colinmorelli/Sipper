//
//  SBSRingtone.h
//  Sipper
//
//  Created by Colin Morelli on 5/1/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SBSRingtone : NSObject

/**
 * URL to the audio file to play as a ringtone
 */
@property(strong, nonatomic, nullable) NSURL *url;

/**
 * Creates a new instance of a ringtone with the requested URL
 *
 * Note that the provided URL *must* exist or you will get an error when attempting to play
 * the ringtone.
 *
 * @parameter url the url of the audio file to play
 */
- (instancetype _Nonnull)initWithURL:(NSURL *_Nullable)url;

@end
