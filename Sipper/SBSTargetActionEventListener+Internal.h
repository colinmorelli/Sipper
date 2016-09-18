//
//  SBSTargetActionEventListener.h
//  Sipper
//
//  Created by Colin Morelli on 6/3/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "SBSEventDispatcher.h"

@interface SBSTargetActionEventListener : NSObject <SBSEventListener>

/**
 * Creates a new listener directed at the target/action pair
 *
 * Instances of the target/action event listener *do not* retain the target class. If the target
 * is de-alloced, dispatching the event will simply do nothing and it will signal to the dispatcher
 * to remove itself
 *
 * @param target the target to register
 * @param action the action to invoke on the target
 */
+ (SBSTargetActionEventListener *)listenerWithTarget:(id)target action:(SEL)action;

@end

@interface SBSEventDispatcher (SBSTargetActionEventListener)

/**
 * Shorthand for adding a target/action pair as a listener
 *
 * @param target the class instance to invoke when the event happens
 * @param action the selector to invoke ont he class
 * @param event  the event to invoke this listener for
 */
- (SBSEventBinding *)addListenerWithTarget:(id)target action:(SEL)action eventName:(NSString *)name;

@end
