//
//  SBSRingtonePlayer.m
//  Sipper
//
//  Created by Colin Morelli on 5/1/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import "SBSRingtonePlayer.h"

#import <AVFoundation/AVFoundation.h>

#import "SBSRingtone.h"

@interface SBSRingtonePlayer ()

@property(strong, nonatomic, nonnull) AVAudioPlayer *player;

@end

@implementation SBSRingtonePlayer

- (instancetype)initWithRingtone:(SBSRingtone *)ringtone {
  if (self = [super init]) {
    _ringtone = ringtone;
  }

  return self;
}

- (void)play {
  NSError *error = nil;

  // If we already have an audio file and are playing, no-op and return here
  if ([self.player isPlaying]) {
    return;
  }

  // Create a new player, only if we have a URL to play
  if (self.ringtone.url != nil) {
    self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:self.ringtone.url error:&error];
    [self.player prepareToPlay];
    [self.player play];
  }
}

- (void)stop {
  [self.player stop];
}

@end
