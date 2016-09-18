//
//  SBSRingtonePlayer.h
//  Sipper
//
//  Created by Colin Morelli on 5/1/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SBSRingtone;

@interface SBSRingtonePlayer : NSObject

/**
 * The ringtone instance associated with this player
 */
@property(strong, nonnull, nonatomic, readonly) SBSRingtone *ringtone;

/**
 * Creates a new ringtone instance associated with this ringtone player
 *
 * @parameter ringtone the ringtone attached to this player
 */
- (instancetype _Nonnull)initWithRingtone:(SBSRingtone *_Nonnull)ringtone;

/**
 * Plays the ringtone instance associated with this player
 *
 * This method is a no-op if the ringtone is already being played by this player. It will
 * interact with other players, however
 */
- (void)play;

/**
 * Stops the ringtone instance associated with this player
 */
- (void)stop;

@end
