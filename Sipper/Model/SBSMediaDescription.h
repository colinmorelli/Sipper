//
//  SBSMediaDescription.h
//  Sipper
//
//  Created by Colin Morelli on 5/3/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 *  Different possible media types
 */
typedef NS_ENUM(NSInteger, SBSMediaType) {
  /**
   * The type of media on this stream is unspecified
   */
  SBSMediaTypeNone,
  /**
   * Audio stream
   */
  SBSMediaTypeAudio,
  /**
   * Video stream
   */
  SBSMediaTypeVideo,
  /**
   * Application stream
   */
  SBSMediaTypeApplication,
  /**
   * Unknown, unsupported, or otherwise unspecified stream
   */
  SBSMediaTypeUnknown
};

/**
 * The direction of the media stream
 */
typedef NS_ENUM(NSInteger, SBSMediaDirection) {
  /**
   * The call doesn't have any media currently
   */
  SBSMediaDirectionNone,
  /**
   * This is a receiving media stream
   */
  SBSMediaDirectionInbound,
  
  /**
   * This is a sending media stream
   */
  SBSMediaDirectionOutbound,
  
  /**
   * This is a bi-directional media stream
   */
  SBSMediaDirectionBidirectional
};

/**
 *  Different valid media states
 */
typedef NS_ENUM(NSInteger, SBSMediaState) {
  /**
   * The call doesn't have any media currently
   */
  SBSMediaStateNone,
  /**
   * The call has active media
   */
  SBSMediaStateActive,
  /**
   * The media was put on hold by the local endpoint
   */
  SBSMediaStateLocalHold,
  /**
   * The media was put on hold by the remote endpoint
   */
  SBSMediaStateRemoteHold,
  /**
   * The media has encountered an error
   */
  SBSMediaStateError
};

@interface SBSMediaDescription : NSObject

/**
 * The type of media that this stream encodes
 */
@property (nonatomic, readonly) SBSMediaType type;

/**
 * The direction of the media stream (receive, transmit, or both)
 */
@property (nonatomic, readonly) SBSMediaDirection direction;

/**
 * The current state of the media stream
 */
@property (nonatomic, readonly) SBSMediaState state;

- (instancetype)initWithMediaType:(SBSMediaType)type direction:(SBSMediaDirection)direction state:(SBSMediaState)state;

@end
