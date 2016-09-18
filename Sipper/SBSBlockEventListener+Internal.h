//
//  SBSBlockEventListener+Internal.h
//  Sipper
//
//  Created by Colin Morelli on 7/6/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "SBSEventDispatcher.h"

@interface SBSBlockEventListener : NSObject <SBSEventListener>

/**
 * Creates a new listener directed at the target/action pair
 *
 * Instances of the target/action event listener *do not* retain the target class. If the target
 * is de-alloced, dispatching the event will simply do nothing and it will signal to the dispatcher
 * to remove itself
 *
 * @param block the block to invoke when the event is triggered
 */
+ (SBSBlockEventListener *)listenerWithBlock:(void (^)(SBSEvent *))block;

@end

@interface SBSEventDispatcher (SBSBlockEventListener)

/**
 * Shorthand for adding a block listener to an event dispatcher
 *
 * @param block the block to add as a listener
 * @param name  the name of the event to add a listener for
 */
- (SBSEventBinding *)addListenerWithBlock:(void (^)(SBSEvent *))block eventName:(NSString *)name;

@end
