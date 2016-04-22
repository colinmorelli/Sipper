//
//  SBSAudioManager.h
//  Sipper
//
//  Created by Colin Morelli on 4/22/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#ifndef SBSAudioManager_h
#define SBSAudioManager_h

#import <Foundation/Foundation.h>

@class SBSAudioDevice;

@interface SBSAudioManager : NSObject

/**
 * Device that is currently used for audio input
 */
@property (strong, nonatomic, nonnull, readonly) SBSAudioDevice *currentInputDevice;

/**
 * Device that is currently used for audio output
 */
@property (strong, nonatomic, nonnull, readonly) SBSAudioDevice *currentOutputDevice;

/**
 * Returns an array of input devices available on the application
 *
 * This method returns a point-in-time snapshot of SBSAudioDevice instances that are
 * available on the system. Note that the available devices could change between receiving
 * a response here and connecting a device
 *
 * @return an array of devices supporting audio input
 */
- (NSArray * _Nonnull)availableInputDevices;

/**
 * Returns an array of output devices available on the application
 *
 * This method returns a point-in-time snapshot of SBSAudioDevice instances that are
 * available on the system. Note that the available devices could change between receiving
 * a response here and connecting a device
 *
 * @return an array of devices supporting audio input
 */
- (NSArray * _Nonnull)availableOuptutDevices;

/**
 * Selects the audio input device to use
 *
 * The audio input device provided to this method should be one returned from the available input
 * devices methods on the audio manager
 *
 * @param inputDevice the new input device to select
 * @param error       pointer to an error that will be updated if selection fails
 * @return whether or not audio device selection was successful
 */
- (BOOL)selectAudioInputDevice:(SBSAudioDevice * _Nonnull)inputDevice error:(NSError **)error;

/**
 * Selects the audio output device to use
 *
 * The audio input device provided to this method should be one returned from the available output
 * devices methods on the audio manager
 *
 * @param outputDevice the new output device to select
 * @param error        pointer to an error that will be updated if selection fails
 * @return whether or not audio device selection was successful
 */
- (BOOL)selectAudioOutputDevice:(SBSAudioDevice * _Nonnull)outputDevice error:(NSError **)error;

/**
 * The shared audio manager for the application
 *
 * Return value from this method is a singleton instance of the audio manager that can be used
 * for changing audio device settings
 */
+ (instancetype _Nonnull)sharedManager;

@end

#endif