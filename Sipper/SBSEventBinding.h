//
//  SBSEventBinding.h
//  Sipper
//
//  Created by Colin Morelli on 6/3/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol SBSEventListener;

@interface SBSEventBinding : NSObject

@property(strong, nonatomic, readonly) id <SBSEventListener> listener;
@property(strong, nonatomic, readonly) NSString *eventName;

/**
 * Creates a new binding with the given listener and event name
 *
 * @param listener the listener that this binding is wrapping
 * @param name     the name of the event that this binding subscribes to
 */
+ (SBSEventBinding *)bindingWithListener:(id <SBSEventListener>)listener eventName:(NSString *)name;

@end
