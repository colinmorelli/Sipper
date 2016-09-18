//
//  SBSEventDispatcher.h
//  Sipper
//
//  Created by Colin Morelli on 6/3/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SBSEventBinding;

@interface SBSEvent : NSObject

@property(nonatomic, readonly) NSString *name;

- (instancetype)initWithName:(NSString *)name;

@end

@protocol SBSEventListener

/**
 * Invoked each time the dispatcher wants to trigger an event to a listener
 *
 * Implementations should forward the call of this method on to the type of event listener they
 * contain, by invoking blocks or forwarding messages
 *
 * @param event the event to forward
 * @return YES if the event was dispatched, NO if it couldn't be because the pointer was de-referenced
 */
- (BOOL)dispatchEvent:(SBSEvent *)event;

@end

@interface SBSEventDispatcher : NSObject

/**
 * Adds an event listener to the dispatcher
 *
 * The dispatcher holds strong references to all listeners provided to it, though the listeners
 * themselves may choose to hold weak references to the user's code.
 *
 * @param listener the listener to register with the dispatcher
 * @param event    the event to register the listener for
 */
- (SBSEventBinding *)addEventListener:(id <SBSEventListener>)listener forEvent:(NSString *)event;

/**
 * Dispatches the event to all registered listeners
 *
 * @param event the event to dispatch
 */
- (void)dispatchEvent:(SBSEvent *)event;

/**
 * Removes a previously registered event binding
 *
 * @param binding the binding to remove a reference to
 */
- (void)removeBinding:(SBSEventBinding *)binding;

@end
