//
//  BlacklistController.h
//  Pocket Gnome
//
//  Created by Josh on 12/13/09.
//  Copyright 2009 Savory Software, LLC. All rights reserved.
//

#import <Cocoa/Cocoa.h>

// created a controller for this, as I don't want to implement the exact same versions for Combat and for nodes

@class WoWObject;

@class MobController;
@class PlayersController;

@interface BlacklistController : NSObject {
	
	IBOutlet MobController		*mobController;
	IBOutlet PlayersController	*playersController;
	

	NSMutableDictionary *_blacklist;

}

// reasons to be blacklisted!
enum{
	Reason_None					= 0,
	Reason_NotInLoS				= 1,
	Reason_NodeMadeMeFall		= 2,
	Reason_next					= 4,
};

- (void)blacklistObject:(WoWObject *)obj withReason:(int)reason;
- (void)blacklistObject: (WoWObject*)obj;
- (BOOL)isBlacklisted: (WoWObject*)obj;
- (void)removeAllUnits;

@end