//
//  WaypointController.m
//  Pocket Gnome
//
//  Created by Jon Drummond on 12/16/07.
//  Copyright 2007 Savory Software, LLC. All rights reserved.
//  

#import "WaypointController.h"
#import "Controller.h"
#import "PlayerDataController.h"
#import "MovementController.h"
#import "MobController.h"
#import "BotController.h"
#import "CombatController.h"
#import "SpellController.h"
#import "InventoryController.h"

#import "WaypointActionEditor.h"

#import "RouteCollection.h"
#import "RouteSet.h"
#import "Route.h"
#import "Waypoint.h"
#import "Action.h"
#import "Mob.h"
#import "ActionMenusController.h"
#import "SaveData.h"

#import "RouteVisualizationView.h"

#import "BetterTableView.h"

#import "PTHeader.h"
#import <Growl/GrowlApplicationBridge.h>
#import <ShortcutRecorder/ShortcutRecorder.h>
 
#define AddWaypointHotkeyIdentifier @"AddWaypoint"
#define AutomatorHotkeyIdentifier @"AutomatorStartStop"

enum AutomatorIntervalType {
    AutomatorIntervalType_Time = 0,
    AutomatorIntervalType_Distance = 1,
};

@interface WaypointController (Internal)
- (void)toggleGlobalHotKey:(id)sender;
- (void)automatorPulse;
- (RouteCollection*)routeCollectionForUUID:(NSString*)UUID;
- (id)selectedRouteObject;
- (void)selectItemInOutlineViewToEdit:(id)item;
- (void)setViewTitle;
@end

@interface WaypointController ()
@property (readwrite, retain) RouteCollection *currentRouteCollection;
@end

@implementation WaypointController

+ (void) initialize {
    NSDictionary *waypointDefaults = [NSDictionary dictionaryWithObjectsAndKeys:
                                      @"0.5",                       @"RouteAutomatorIntervalValue",
                                      [NSNumber numberWithInt: 0],  @"RouteAutomatorIntervalTypeTag", nil];
    [[NSUserDefaults standardUserDefaults] registerDefaults: waypointDefaults];
}

- (id) init
{
    self = [super init];
    if (self != nil) {

		_selectedRows = nil;
		_nameBeforeRename = nil;
		
		_firstTimeEverOnTheNewRouteCollections = NO;
		_validRouteSelection = NO;
		_validRouteSetSelected = NO;
		_validRouteCollectionSelected = NO;
		_currentRouteCollection = nil;
		_routeCollectionList = [[NSMutableArray array] retain];
		
		// pull data from the .plist file
		NSArray *routes = [[self loadAllDataForKey:@"Routes" withClass:[RouteSet class]] retain];
		
		// pull routes from .route files
		_myHackVariable = YES;
		if ( !routes ){
			routes = [[self loadAllObjects] retain];
		}
		
		// delete old files!
		if ( [routes count] > 0 ){
			PGLog(@"[Routes] Converting all routes to the new format! Removing old files!");
			[self deleteAllObjects];
		}
		
		// stop using .route
		_myHackVariable = NO;
		
		// then we need to convert our routes above, I love how much I change things QQ
		if ( [routes count] > 0 ){
			
			for ( RouteSet *route in routes ){
				RouteCollection *rc = [RouteCollection routeCollectionWithName:[route name]];
				[rc addRouteSet:route];
				[rc setStartRoute:route];
				
				[_routeCollectionList addObject:rc];		
			}
			
			_firstTimeEverOnTheNewRouteCollections = YES;
		}
		else{
			_routeCollectionList = [[self loadAllObjects] retain];
		}
		
		PGLog(@"We now have %d objects of route collection", [_routeCollectionList count]);
		
        // listen for notification
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(applicationWillTerminate:) name: NSApplicationWillTerminateNotification object: nil];
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(checkHotkeys:) 
                                                     name: DidLoadViewInMainWindowNotification 
                                                   object: nil];
        [NSBundle loadNibNamed: @"Routes" owner: self];
    }
    return self;
}

- (void)awakeFromNib {
    self.minSectionSize = [self.view frame].size;
    self.maxSectionSize = NSZeroSize;

    [waypointTable registerForDraggedTypes: [NSArray arrayWithObjects: @"WaypointIndexesType", @"WaypointArrayType", nil]];
	[routesTable registerForDraggedTypes: [NSArray arrayWithObjects: @"RouteSets", nil]];

	// TO DO - auto select first one?
    /*if ( !self.currentRoute && [_routes count]) {
        [self setCurrentRouteSet: [_routes objectAtIndex: 0]];
        [waypointTable reloadData];
    }*/
    
    // Automator isn't running!
    self.isAutomatorRunning = NO;
    
    [shortcutRecorder setCanCaptureGlobalHotKeys: YES];
	[automatorRecorder setCanCaptureGlobalHotKeys: YES];
    
    KeyCombo combo = { -1, 0 };
    if([[NSUserDefaults standardUserDefaults] objectForKey: @"WaypointAdd_HotkeyCode"])
        combo.code = [[[NSUserDefaults standardUserDefaults] objectForKey: @"WaypointAdd_HotkeyCode"] intValue];
    if([[NSUserDefaults standardUserDefaults] objectForKey: @"WaypointAdd_HotkeyFlags"])
        combo.flags = [[[NSUserDefaults standardUserDefaults] objectForKey: @"WaypointAdd_HotkeyFlags"] intValue];
    
	KeyCombo combo2 = {NSShiftKeyMask, kSRKeysF14};
    if([[NSUserDefaults standardUserDefaults] objectForKey: @"WaypointAutomator_HotkeyCode"])
        combo2.code = [[[NSUserDefaults standardUserDefaults] objectForKey: @"WaypointAutomator_HotkeyCode"] intValue];
    if([[NSUserDefaults standardUserDefaults] objectForKey: @"WaypointAutomator_HotkeyFlags"])
        combo2.flags = [[[NSUserDefaults standardUserDefaults] objectForKey: @"WaypointAutomator_HotkeyFlags"] intValue];
	
    [shortcutRecorder setDelegate: nil];
    [shortcutRecorder setKeyCombo: combo];
    [shortcutRecorder setDelegate: self];
	
    [automatorRecorder setDelegate: nil];
    [automatorRecorder setKeyCombo: combo2];
    [automatorRecorder setDelegate: self];
}

- (void)saveRoutes {
	
	// lets save our routes if they've changed!
	/*for ( RouteSet *route in _routes ){
		if ( route.changed ){
			[self saveObject:route];
		}
	}*/
	
	// lets save our collections!
	for ( RouteCollection *rc in _routeCollectionList ){
		if ( rc.changed ){
			[self saveObject:rc];
		}
	}
	
	// we no longer use this anymore! Yay!
	[[NSUserDefaults standardUserDefaults] removeObjectForKey: @"Routes"];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)validateBindings {
    [self willChangeValueForKey: @"currentRoute"];
    [self didChangeValueForKey: @"currentRoute"];
    
    self.validSelection = [waypointTable numberOfSelectedRows] ? YES : NO;
    self.validWaypointCount = [[self currentRoute] waypointCount] > 1 ? YES : NO;
}

- (void)applicationWillTerminate: (NSNotification*)notification {
    [self saveRoutes];
}

#pragma mark -
#pragma mark Current State

@synthesize view;
@synthesize minSectionSize;
@synthesize maxSectionSize;
@synthesize currentRoute = _currentRoute;
@synthesize currentRouteSet = _currentRouteSet;
@synthesize currentRouteCollection = _currentRouteCollection;
@synthesize descriptionMultiRows = _descriptionMultiRows;

@synthesize disableGrowl;
@synthesize validSelection;
@synthesize validWaypointCount;
@synthesize isAutomatorRunning;

@synthesize validRouteSelection = _validRouteSelection;
@synthesize validRouteSetSelected = _validRouteSetSelected;
@synthesize validRouteCollectionSelected = _validRouteCollectionSelected;

- (NSString*)sectionTitle {
    return @"Routes & Waypoints";
}

- (NSString*)currentRouteKey {
    if( [routeTypeSegment selectedTag] == 0 )
        return PrimaryRoute;
    if( [routeTypeSegment selectedTag] == 1 )
        return CorpseRunRoute;
    return @"";
}

- (NSArray*)routeCollections{
	return [[_routeCollectionList retain] autorelease];
}

// this is literally a compilation of ALL routes
- (NSArray*)routes{
	
	
	
	NSMutableArray *allRoutes = [NSMutableArray array];
	
	for ( RouteCollection *rc in _routeCollectionList ){
		[allRoutes addObjectsFromArray:[rc routes]];
	}
	
	/*PGLog(@"total: %d", [allRoutes count]);
	
	for ( id item in allRoutes ){
		PGLog(@"%@", item);
	}
	
	
	return nil;*/
	
	return allRoutes;
}

- (Route*)currentRoute {
    return [[self currentRouteSet] routeForKey: [self currentRouteKey]];
}

- (void)setCurrentRouteSet: (RouteSet*)routeSet {
    [_currentRouteSet autorelease];
    _currentRouteSet = [routeSet retain];
    
    [routeTypeSegment selectSegmentWithTag: 0];
    [self validateBindings];

}

#pragma mark -
#pragma mark Route Actions

/*
- (void)addRoute: (RouteSet*)routeSet {
    int num = 2;
    BOOL done = NO;
    if(![routeSet isKindOfClass: [RouteSet class]]) return;
    if(![[routeSet name] length]) return;
    
    // check to see if a route exists with this name
    NSString *originalName = [routeSet name];
    while(!done) {
        BOOL conflict = NO;
        for(RouteSet *route in self.routes) {
            if( [[route name] isEqualToString: [routeSet name]]) {
                [routeSet setName: [NSString stringWithFormat: @"%@ %d", originalName, num++]];
                conflict = YES;
                break;
            }
        }
        if(!conflict) done = YES;
    }
    
    // save this route into our array
    [self willChangeValueForKey: @"routes"];
    [_routes addObject: routeSet];
    [self didChangeValueForKey: @"routes"];

    // update the current route
    [self setCurrentRouteSet: routeSet];
    [waypointTable reloadData];
	
	// so we know to save this route later!
	[self currentRouteSet].changed = YES;
    
    // PGLog(@"Added route: %@", [routeSet name]);
}*/

- (IBAction)loadRoute: (id)sender {
    [waypointTable reloadData];
}

- (IBAction)setRouteType: (id)sender {
    [waypointTable reloadData];
    [self validateBindings];
}

- (IBAction)removeRoute: (id)sender {
    if([self currentRouteSet]) {
        
       /* int ret = NSRunAlertPanel(@"Delete Route?", [NSString stringWithFormat: @"Are you sure you want to delete the route \"%@\"?", [[self currentRouteSet] name]], @"Delete", @"Cancel", NULL);
        if(ret == NSAlertDefaultReturn) {
			
            [self willChangeValueForKey: @"routes"];
            [_routes removeObject: [self currentRouteSet]];
			
			[self deleteObject:[self currentRouteSet]];
            
            if([_routes count])
                [self setCurrentRouteSet: [_routes objectAtIndex: 0]];
            else
                [self setCurrentRouteSet: nil];
                
            [self didChangeValueForKey: @"routes"];
            
            [waypointTable reloadData];
        }*/
    }
}

- (IBAction)duplicateRoute: (id)sender {
   // [self addRoute: [self.currentRouteSet copy]];
}

- (IBAction)renameRoute: (id)sender {
	
	_nameBeforeRename = [[self.currentRouteSet name] copy];
	
	[NSApp beginSheet: renamePanel
	   modalForWindow: [self.view window]
		modalDelegate: nil
	   didEndSelector: nil //@selector(sheetDidEnd: returnCode: contextInfo:)
		  contextInfo: nil];
}

- (IBAction)closeRename: (id)sender {
    [[sender window] makeFirstResponder: [[sender window] contentView]];
    [NSApp endSheet: renamePanel returnCode: 1];
    [renamePanel orderOut: nil];
	
	// did the name change?
	if ( ![_nameBeforeRename isEqualToString:[[self currentRouteSet] name]] ){
		[self currentRouteSet].changed = YES;
		[self deleteObjectWithName:_nameBeforeRename];
	}
}

#pragma mark -

- (void)importRouteAtPath: (NSString*)path {
    id importedRoute;
    NS_DURING {
        importedRoute = [NSKeyedUnarchiver unarchiveObjectWithFile: path];
    } NS_HANDLER {
        importedRoute = nil;
    } NS_ENDHANDLER
    
    if(importedRoute) {
		
		PGLog(@"%@", importedRoute);
		
        if ( [importedRoute isKindOfClass: [RouteSet class]] ) {
            //[self addRoute: importedRoute];
		}
		else if ( [importedRoute isKindOfClass: [NSDictionary class]] ) {
			//[self addRoute:[importedRoute objectForKey:@"Route"]];	
        }
		else if ( [importedRoute isKindOfClass: [NSArray class]] ) {
            for ( RouteSet *route in importedRoute) {
               // [self addRoute: route];
            }
        }
		else {
            importedRoute = nil;
        }
    }
    
    if(!importedRoute) {
        NSRunAlertPanel(@"Route not Valid", [NSString stringWithFormat: @"The file at %@ cannot be imported because it does not contain a valid route or route set.", path], @"Okay", NULL, NULL);
    }
}

- (IBAction)importRoute: (id)sender {
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];

	[openPanel setCanChooseDirectories: NO];
	[openPanel setCanCreateDirectories: NO];
	[openPanel setPrompt: @"Import Route"];
	[openPanel setCanChooseFiles: YES];
    [openPanel setAllowsMultipleSelection: YES];
	
	int ret = [openPanel runModalForTypes: [NSArray arrayWithObjects: @"route", @"routeset", nil]];
    
	if(ret == NSFileHandlingPanelOKButton) {
        for(NSString *routePath in [openPanel filenames]) {
            [self importRouteAtPath: routePath];
        }
	}
}

- (IBAction)exportRoute: (id)sender {

    NSSavePanel *savePanel = [NSSavePanel savePanel];
    [savePanel setCanCreateDirectories: YES];
    [savePanel setTitle: @"Export Route"];
    [savePanel setMessage: @"Please choose a destination for this route."];
    int ret = [savePanel runModalForDirectory: @"~/" file: [[[self currentRouteSet] name] stringByAppendingPathExtension: @"route"]];
    
	if(ret == NSFileHandlingPanelOKButton) {
        NSString *saveLocation = [savePanel filename];
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject: [self currentRouteSet]];
        [data writeToFile: saveLocation atomically: YES];
    }
}

#pragma mark -
#pragma mark Waypoint & Other Actions

- (void)selectCurrentWaypoint:(int)index{
	
	if ( [[waypointTable window] isVisible] && [scrollWithRoute state] ) {
		if ( self.currentRouteSet == botController.theRoute ){
			[waypointTable selectRow:index byExtendingSelection:NO];
			[waypointTable scrollRowToVisible:index];
		}
	}
}

- (IBAction)closestWaypoint: (id)sender{

	Waypoint *wp = nil;
	Position *playerPosition = [playerData position];
	float minDist = INFINITY, tempDist;
	int closestWaypointRow = -1, i;
	for ( i = 0; i < [[self currentRoute] waypointCount]; i++ ){
		wp = [[self currentRoute] waypointAtIndex: i];
		tempDist = [playerPosition distanceToPosition: [wp position]];
		if( (tempDist < minDist) && (tempDist >= 0.0f)) {
			minDist = tempDist;
			closestWaypointRow = i;
		}
	}
	
	if ( closestWaypointRow > 0 ){
		[waypointTable selectRow:closestWaypointRow byExtendingSelection:NO];
		[waypointTable scrollRowToVisible:closestWaypointRow];
		PGLog(@"[Waypoint] Closest waypoint is %0.2f yards away", minDist);
	}
}

- (IBAction)visualize: (id)sender {
    if([[self currentRouteKey] isEqualToString: PrimaryRoute])
        [visualizeView setShouldClosePath: YES];
    else
        [visualizeView setShouldClosePath: NO];
    
    [visualizeView setRoute: [self currentRoute]];
    [visualizeView setPlayerPosition: [playerData position]];
    [visualizeView setNeedsDisplay: YES];

	[NSApp beginSheet: visualizePanel
	   modalForWindow: [waypointTable window]
		modalDelegate: nil
	   didEndSelector: nil //@selector(sheetDidEnd: returnCode: contextInfo:)
		  contextInfo: nil];
}

- (IBAction)closeVisualize: (id)sender {
    [NSApp endSheet: visualizePanel returnCode: 1];
    [visualizePanel orderOut: nil];
}

- (IBAction)addWaypoint: (id)sender {
    if(![self currentRoute])        return;
    if(![playerData playerIsValid:self]) return;
    if(![self.view window])         return;

    Waypoint *newWP = [Waypoint waypointWithPosition: [playerData position]];
    [[self currentRoute] addWaypoint: newWP];
    [waypointTable reloadData];
	[self currentRouteSet].changed = YES;
    PGLog(@"Added: %@", newWP);
    NSString *readableRoute =  ([routeTypeSegment selectedTag] == 0) ? @"Primary" : @"Corpse Run";
    
    BOOL dontGrowl = (!sender && self.disableGrowl); // sender is nil when this is called by the automator
    if( !dontGrowl && [controller sendGrowlNotifications] && [GrowlApplicationBridge isGrowlInstalled] && [GrowlApplicationBridge isGrowlRunning]) {
        // [GrowlApplicationBridge setGrowlDelegate: @""];
        [GrowlApplicationBridge notifyWithTitle: @"Added Waypoint"
                                    description: [NSString stringWithFormat: @"Added waypoint to %@ route of \"%@\"", readableRoute, [[self currentRouteSet] name]]
                               notificationName: @"AddWaypoint"
                                       iconData: [[NSImage imageNamed: @"Ability_Rogue_Sprint"] TIFFRepresentation]
                                       priority: 0
                                       isSticky: NO
                                   clickContext: nil];
    }
}

- (IBAction)removeWaypoint: (id)sender {
    NSIndexSet *rowIndexes = [waypointTable selectedRowIndexes];
    if([rowIndexes count] == 0 || ![self currentRoute]) return;
    
    int row = [rowIndexes lastIndex];
    while(row != NSNotFound) {
        [[self currentRoute] removeWaypointAtIndex: row];
        row = [rowIndexes indexLessThanIndex: row];
    }
    
    [waypointTable selectRow: [rowIndexes firstIndex] byExtendingSelection: NO]; 
    
    [waypointTable reloadData];
	[self currentRouteSet].changed = YES;
}

- (IBAction)editWaypointAction: (id)sender {
	
    // make sure the clicked row is valid
    if ( [waypointTable clickedRow] < 0 || [waypointTable clickedRow] >= [[self currentRoute] waypointCount] ) {
        NSBeep();
        PGLog(@"Error: invalid row (%d), cannot change action.", [waypointTable clickedRow]);
        return;
    }
    
    // get our waypoint
    Waypoint *wp = [[[self currentRoute] waypointAtIndex: [waypointTable clickedRow]] retain];
	
	// setting this waypoint to nothing!
	if ( [sender tag] == ActionType_None ){
		[wp setActions:nil];
		wp.rule = nil;
		[self currentRouteSet].changed = YES;
	}
	// open our editor
	else{
		[[WaypointActionEditor sharedEditor] showEditorOnWindow: [self.view window] 
												   withWaypoint: wp
													 withAction: [sender tag]];
	}
}

- (void)waypointActionEditorClosed: (BOOL)change{
	if ( change ){
		[self currentRouteSet].changed = YES;
	}
}

- (IBAction)moveToWaypoint: (id)sender {
    int row = [[waypointTable selectedRowIndexes] firstIndex];
    if(row == NSNotFound || ![self currentRoute]) return;
	
    Waypoint *waypoint = [[self currentRoute] waypointAtIndex: row];
    
    [movementController moveToWaypoint: waypoint];
}

- (IBAction)testWaypointSequence: (id)sender {
    if(![self currentRoute] || ![[self currentRoute] waypointCount])    return;
    
    [movementController setPatrolRoute: [self currentRoute]];
    [movementController beginPatrol: 1];
}

- (IBAction)stopMovement: (id)sender {
    [movementController setPatrolRoute: nil];
}

#pragma mark -
#pragma mark Route Automator

- (IBAction)openAutomatorPanel: (id)sender {
    if([[self currentRouteKey] isEqualToString: PrimaryRoute])
        [automatorVizualizer setShouldClosePath: YES];
    else
        [automatorVizualizer setShouldClosePath: NO];
    
    [automatorVizualizer setRoute: [self currentRoute]];
    [automatorVizualizer setPlayerPosition: [playerData position]];
    [automatorVizualizer setNeedsDisplay: YES];
    
    // enable automator hotkey
    BOOL isAutomatorEnabled = ([[PTHotKeyCenter sharedCenter] hotKeyWithIdentifier: AutomatorHotkeyIdentifier]) ? YES : NO;
    if(!isAutomatorEnabled)
        [self toggleGlobalHotKey: automatorRecorder];

	[NSApp beginSheet: automatorPanel
	   modalForWindow: [self.view window]
		modalDelegate: nil
	   didEndSelector: nil //@selector(sheetDidEnd: returnCode: contextInfo:)
		  contextInfo: nil];
}

- (IBAction)closeAutomatorPanel: (id)sender {
    if(self.isAutomatorRunning) {
        [self startStopAutomator: automatorStartStopButton];
    }
    
    // disable automator hotkey
    BOOL isAutomatorEnabled = ([[PTHotKeyCenter sharedCenter] hotKeyWithIdentifier: AutomatorHotkeyIdentifier]) ? YES : NO;
    if(isAutomatorEnabled)
        [self toggleGlobalHotKey: automatorRecorder];
    
    
    [NSApp endSheet: automatorPanel returnCode: 1];
    [automatorPanel orderOut: nil];
}

- (IBAction)startStopAutomator: (id)sender {
	// OK stop automator!
	if ( self.isAutomatorRunning ) {
		PGLog(@"Waypoint recording stopped");
		self.isAutomatorRunning = NO;
        [automatorSpinner stopAnimation: nil];
        [automatorStartStopButton setState: NSOffState];
        [automatorStartStopButton setTitle: @"Start Recording"];
        [automatorStartStopButton setImage: [NSImage imageNamed: @"off"]];
	}
	else {
		PGLog(@"Waypoint recording started");
        [automatorPanel makeFirstResponder: [automatorPanel contentView]];
		self.isAutomatorRunning = YES;
        [automatorSpinner startAnimation: nil];
        [automatorStartStopButton setState: NSOnState];
        [automatorStartStopButton setTitle: @"Stop Recording"];
        [automatorStartStopButton setImage: [NSImage imageNamed: @"on"]];
	}
	
	[self automatorPulse];
}

-(void)automatorPulse {
	// Make sure we have valid route/player/window!
	if(!self.isAutomatorRunning)    return;
	if(![self currentRoute])        return;
    if(![self.view window])         return;
    if(![playerData playerIsValid:self]) return;
    
	// figure out how far we've moved
    Position *playerPosition = [playerData position];
	Waypoint *curWP = [Waypoint waypointWithPosition: playerPosition];
	Waypoint *lastWP = [[[self currentRoute] waypoints] lastObject];
    float distance = [curWP.position distanceToPosition: lastWP.position];
    
    // if we haven't moved, we dont care!
    BOOL waypointAdded = NO;
    float pulseTime = 0.1f;
    if(distance != 0.0f) {
        float interval = [[[NSUserDefaults standardUserDefaults] objectForKey: @"RouteAutomatorIntervalValue"] floatValue];
        NSInteger type = [[NSUserDefaults standardUserDefaults] integerForKey: @"RouteAutomatorIntervalTypeTag"]; 
        
        if(type == AutomatorIntervalType_Distance) {
            // record automatically after X yards
            if(distance >= interval) {
                waypointAdded = YES;
                [self addWaypoint: nil];
            }
        } else {
            // if we're recording on an time interval, we know 
            waypointAdded = YES;
            [self addWaypoint: nil];
            pulseTime = interval;
        }
    }
    
    if(waypointAdded) {
        // if we added something, have the visualizer redraw
        [automatorVizualizer setPlayerPosition: playerPosition];
        [automatorVizualizer setNeedsDisplay: YES];
    }
	
	// Check again after the specified delay!
	[self performSelector: @selector(automatorPulse) withObject: nil afterDelay: pulseTime];
}

// called by the X button in the Automator panel
- (IBAction)resetAllWaypoints: (id)sender {
    int ret = NSRunAlertPanel(@"Remove All Waypoints?", [NSString stringWithFormat: @"Are you sure you want to delete all the waypoints in route \"%@\"?  This cannot be undone.", [[self currentRouteSet] name]], @"Delete", @"Cancel", NULL);
    if(ret == NSAlertDefaultReturn) {
        Waypoint *wp = nil;
        Route *route = [self currentRoute];
        while((wp = [route waypointAtIndex: 0])) {
            [route removeWaypointAtIndex: 0];
        }
        [automatorVizualizer setNeedsDisplay: YES];
    }
}

#pragma mark TabView Delgate

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem{
	
	[self setViewTitle];
}

#pragma mark -
#pragma mark NSTableView Delesource

- (int)numberOfRowsInTableView:(NSTableView *)aTableView {
	
	if ( aTableView == waypointTable )
		return [[self currentRoute] waypointCount];
	
	return 0;
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex {
    if ( rowIndex == -1 ) return nil;
	
	if ( aTableView == waypointTable ){
		
		Waypoint *wp = [[self currentRoute] waypointAtIndex: rowIndex];
		if ( [[aTableColumn identifier] isEqualToString: @"Step"] ){
			return [NSNumber numberWithInt: rowIndex+1];
		}
		
		if( [[aTableColumn identifier] isEqualToString: @"Type"] ){
			
			int type = 0;
			
			// now we have a list of actions, choose the first one
			if ( [wp.actions count] > 0 ){
				
				Action *action = [wp.actions objectAtIndex:0];
				
				if ( action.type > ActionType_None && action.type < ActionType_Max ){
					type = action.type;
				}
			}
			
			return [NSNumber numberWithInt: type];
		}
		
		
		if ( [[aTableColumn identifier] isEqualToString: @"Coordinates"] ){
			return [NSString stringWithFormat: @"X: %.1f; Y: %.1f; Z: %.1f", [[wp position] xPosition], [[wp position] yPosition], [[wp position] zPosition]];
		}
		
		if ( [[aTableColumn identifier] isEqualToString: @"Distance"] ){
			Waypoint *prevWP = (rowIndex == 0) ? ([[self currentRoute] waypointAtIndex: [[self currentRoute] waypointCount] - 1]) : ([[self currentRoute] waypointAtIndex: rowIndex-1]);
			float distance = [[wp position] distanceToPosition: [prevWP position]];
			return [NSString stringWithFormat: @"%.2f yards", distance];
		}
		
		if ( [[aTableColumn identifier] isEqualToString: @"Description"] ){
			return wp.title;
		}
	}
    
    return nil;
}

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
	if ( rowIndex == -1 ) return;
	
	if ( aTableView == waypointTable ){
		if ( [[aTableColumn identifier] isEqualToString:@"Description"] ){
			Waypoint *wp = [[self currentRoute] waypointAtIndex: rowIndex];
			if ( wp.title != anObject ){
				wp.title = anObject;
			}
		}
	}
}

- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
	
	if ( aTableView == waypointTable ){
		if([[aTableColumn identifier] isEqualToString: @"Type"] )
			return YES;
		else if([[aTableColumn identifier] isEqualToString: @"Description"] )
			return YES;
	}

    return NO;
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
	
	//PGLog(@" %@ %@", aNotification, [aNotification object]);
	
    [self validateBindings];
}

- (void)tableView: (NSTableView*)aTableView deleteKeyPressedOnRowIndexes: (NSIndexSet*)rowIndexes {
	
	if ( aTableView == waypointTable ){
		[self removeWaypoint: nil];
	}
}

- (BOOL)tableViewCopy: (NSTableView*)aTableView {
	
	if ( aTableView == waypointTable ){
		NSIndexSet *rowIndexes = [aTableView selectedRowIndexes];
		if([rowIndexes count] == 0) {
			return NO;
		}
		NSPasteboard *pboard = [NSPasteboard generalPasteboard];
		[pboard declareTypes: [NSArray arrayWithObjects: NSStringPboardType, @"WaypointArrayType", nil] owner: nil];
		
		// create list of our waypoints
		NSMutableArray *waypointList = [NSMutableArray arrayWithCapacity: [rowIndexes count]];
		int aRow = [rowIndexes firstIndex];
		while (aRow != NSNotFound) {
			[waypointList addObject: [[self currentRoute] waypointAtIndex: aRow]];
			aRow = [rowIndexes indexGreaterThanIndex: aRow];
		}
		[pboard setData: [NSKeyedArchiver archivedDataWithRootObject: waypointList] forType: @"WaypointArrayType"];
		
		NSMutableString *stringVal = [NSMutableString string];
		for(Waypoint *wp in waypointList) {
			[stringVal appendFormat: @"{ %.2f, %.2f, %.2f }\n", wp.position.xPosition, wp.position.yPosition, wp.position.zPosition ];
		}
		[pboard setString: stringVal forType: NSStringPboardType];
		
		return YES;
	}
	
	return NO;
}

- (BOOL)tableViewPaste: (NSTableView*)aTableView {
	
	if ( aTableView == waypointTable ){
		NSPasteboard* pboard = [NSPasteboard generalPasteboard];
		NSData *data = [pboard dataForType: @"WaypointArrayType"];
		if(!data) return NO;
		
		NSArray *copiedWaypoints = [NSKeyedUnarchiver unarchiveObjectWithData: data];
		
		if( !copiedWaypoints || ![self currentRoute] ) {
			return NO;
		}
		
		int index = [[aTableView selectedRowIndexes] firstIndex];
		if(index == NSNotFound) index = [[self currentRoute] waypointCount];
		
		// insert waypoints in reverse order
		for (Waypoint *wp in [copiedWaypoints reverseObjectEnumerator]) {
			[[self currentRoute] insertWaypoint: wp atIndex: index];
		}
		
		// reload and select the pasted routes
		[aTableView reloadData];
		[aTableView selectRowIndexes: [NSIndexSet indexSetWithIndexesInRange: NSMakeRange(index, [copiedWaypoints count])] byExtendingSelection: NO];
		
		return YES;
	}
	
	return NO;
}

- (BOOL)tableViewCut: (NSTableView*)aTableView {
	if ( aTableView == waypointTable ){
		if ( [self tableViewCopy: aTableView] ){
			[self removeWaypoint: nil];
			return YES;
		}
	}
    return NO;
}

#pragma mark Table Drag & Drop

// begin drag operation, save row index
- (BOOL)tableView:(NSTableView *)aTableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard {
	
	if ( aTableView == waypointTable ){
		// Copy the row numbers to the pasteboard.
		[pboard declareTypes: [NSArray arrayWithObjects: @"WaypointIndexesType", nil] owner: self];
		[pboard setData: [NSKeyedArchiver archivedDataWithRootObject: rowIndexes] forType: @"WaypointIndexesType"];
		
		return YES;
	}
	
	return NO;
}

// validate drag operation
- (NSDragOperation) tableView: (NSTableView*) aTableView
                 validateDrop: (id ) info
                  proposedRow: (int) row
        proposedDropOperation: (NSTableViewDropOperation) op
{
    int result = NSDragOperationNone;
    
	if ( aTableView == waypointTable ){
		if (op == NSTableViewDropAbove) {
			result = NSDragOperationMove;
			
			/*NSPasteboard* pboard = [info draggingPasteboard];
			 NSData* rowData = [pboard dataForType: @"WaypointType"];
			 NSIndexSet* rowIndexes = [NSKeyedUnarchiver unarchiveObjectWithData:rowData];
			 int dragRow = [rowIndexes firstIndex];
			 
			 if(dragRow == row || dragRow == row-1) {
			 result = NSDragOperationNone;
			 }*/
		}
	}
    
    return (result);
}

// accept the drop
- (BOOL)tableView: (NSTableView *)aTableView 
       acceptDrop: (id <NSDraggingInfo>)info
              row: (int)row 
    dropOperation: (NSTableViewDropOperation)operation {
    
	if ( aTableView == waypointTable ){
		NSPasteboard* pboard = [info draggingPasteboard];
		NSData *data = [pboard dataForType: @"WaypointIndexesType"];
		if(!data) return NO;
		NSIndexSet* rowIndexes = [NSKeyedUnarchiver unarchiveObjectWithData: data];
		if(!rowIndexes ) {
			PGLog(@"Error dragging waypoints. Indexes invalid.");
			return NO;
		}
		
		// PGLog(@"Draggin %d rows to above row %d", [rowIndexes count], row);
		
		Waypoint *targetWP = [[self currentRoute] waypointAtIndex: row];
		NSMutableArray *wpToInsert = [NSMutableArray arrayWithCapacity: [rowIndexes count]];
		
		// save and remove all waypoints we are moving.
		// do it in reverse order so as to not mess up earlier indexes
		int aRow = [rowIndexes lastIndex];
		while (aRow != NSNotFound) {
			[wpToInsert addObject: [[self currentRoute] waypointAtIndex: aRow]];
			[[self currentRoute] removeWaypointAtIndex: aRow];
			aRow = [rowIndexes indexLessThanIndex: aRow];
		}
		
		// now, find the current index of the saved waypoint
		int index = [[[self currentRoute] waypoints] indexOfObjectIdenticalTo: targetWP];
		if(index == NSNotFound) index = [[self currentRoute] waypointCount];
		// PGLog(@"Target index: %d", index);
		
		// don't need to reverseEnum because the order is already reversed
		for (Waypoint *wp in wpToInsert) {
			[[self currentRoute] insertWaypoint: wp atIndex: index];
		}
		
		
		/*
		 int numIns = 0;
		 int dragRow = [rowIndexes firstIndex];
		 if(dragRow < row) { 
		 PGLog(@" --> Decrementing row to %d because dragRow (%d) < row (%d)", row-1, dragRow, row);
		 row--;
		 }
		 
		 // at this point, "row" is index of the waypoint above where we want to move everything
		 
		 //while (dragRow != NSNotFound) {
		 // Move the specified row to its new location...
		 Waypoint *dragWaypoint = [[self currentRoute] waypointAtIndex: dragRow];
		 [[self currentRoute] removeWaypointAtIndex: dragRow];
		 [[self currentRoute] insertWaypoint: dragWaypoint atIndex: (row + numIns)];
		 
		 PGLog(@" --> Moving row %d to %d", dragRow, (row + numIns));
		 
		 numIns++;
		 dragRow = [rowIndexes indexGreaterThanIndex: dragRow];
		 //}
		 */
		
		// reload and select rows
		[aTableView reloadData];
		[aTableView selectRowIndexes: [NSIndexSet indexSetWithIndexesInRange: NSMakeRange(index, [wpToInsert count])] byExtendingSelection: NO];
		
		return YES;
	}

	return NO;
}

#pragma mark Outline View

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item{
	
	// root
	if ( item == nil ){
		return [_routeCollectionList count];
	}
	// child
	else if ( [item isKindOfClass:[RouteCollection class]] ){
		return [[item routes] count];
	}
	
	return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item{
	

	// root
	if ( item == nil ){
		
		if ( index > [_routeCollectionList count] ){
			return nil;
		}
		
		return [_routeCollectionList objectAtIndex:index];
	}
	// child
	else{
		NSArray *routes = [(RouteCollection*)item routes];
		
		if ( index >= [routes count] ){
			return nil;
		}
		
		RouteCollection *parent = [(RouteSet*)[routes objectAtIndex:index] parent];
		
		if ( parent != item ){
			return nil;
		}

		return [routes objectAtIndex:index];
	}

	return nil;	
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item{

	if ( [item isKindOfClass:[RouteCollection class]] ){
		return YES;
	}
	
	return NO;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item{
	
	if ( [item isKindOfClass:[RouteCollection class]] ){
		return [item name];
	}
	
	else if ( [item isKindOfClass:[RouteSet class]] ){
		return [item name];
	}
	
	// weird
	if ( item == nil ){
		return @"WTF ERROR TELL TANARIS4!";
	}
	
	return nil;
}

- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn byItem:(id)item{
	
	// in theory should always be
	if ( [object isKindOfClass:[NSString class]] ){
		
		// rename the object
		if ( [item isKindOfClass:[RouteSet class]] )
			[(RouteSet*)item setName:object];
		else if ( [item isKindOfClass:[RouteCollection class]] )
			[(RouteCollection*)item setName:object];
	}
}

// called whenever the selection changes!
- (void)outlineViewSelectionDidChange:(NSNotification *)notification{
	
	NSOutlineView *outlineView = [notification object];
	
	if ( outlineView == routesTable ){
		
		id selectedItem = [self selectedRouteObject];
		
		// valid selection?
		if ( selectedItem ){

			if ( [selectedItem isKindOfClass:[RouteSet class]] ){
				self.currentRouteSet = selectedItem;
				[waypointTable reloadData];
			}
			else{
				self.currentRouteSet = nil;
				[waypointTable reloadData];
			}
			
			// bindings?
			
			[self willChangeValueForKey: @"validRouteSelection"];
			
			// if it's of type RouteSet, yes we can delete
			if ( [selectedItem isKindOfClass:[RouteSet class]] ){
				self.validRouteSelection = YES;
			}
			// need to make sure the route collection has NO route sets
			else if ( [selectedItem isKindOfClass:[RouteCollection class]] && [[(RouteCollection*)selectedItem routes] count] == 0 ){
				self.validRouteSelection = YES;
			}
			// otherwise we can't delete :(
			else{
				self.validRouteSelection = NO;
			}

			[self didChangeValueForKey: @"validRouteSelection"];
		}
		
		// update our selected route collection!
		if ( [selectedItem isKindOfClass:[RouteCollection class]] ){
			self.currentRouteCollection = selectedItem;
		}
		else{
			self.currentRouteCollection = nil;
		}
		
		// check the box if we need to?
		if ( [selectedItem isKindOfClass:[RouteSet class]] ){
			RouteCollection *parentRC = [(RouteSet*)selectedItem parent];
			
			[startingRouteButton setState:[parentRC isStartingRoute:selectedItem]];
		}
		
		// is a RouteSet selected?
		[self willChangeValueForKey: @"validRouteSetSelected"];
		if ( [selectedItem isKindOfClass:[RouteSet class]] )
			self.validRouteSetSelected = YES;
		else
			self.validRouteSetSelected = NO;
		[self didChangeValueForKey: @"validRouteSetSelected"];
		
		// is a RouteCollection selected?
		[self willChangeValueForKey: @"validRouteCollectionSelected"];
		if ( [selectedItem isKindOfClass:[RouteCollection class]] )
			self.validRouteCollectionSelected = YES;
		else
			self.validRouteCollectionSelected = NO;
		[self didChangeValueForKey: @"validRouteCollectionSelected"];
		
		// update our title
		[self setViewTitle];
	}
}

// do we allow pasting?
- (BOOL)outlineView:(NSOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pboard{
	
	// we don't move route collections! (for now)
	for ( id item in items ){

		if ( [item isKindOfClass:[RouteCollection class]] ){
			return NO;
		}
	}

	if ( outlineView == routesTable ){
		[pboard declareTypes: [NSArray arrayWithObjects: @"RouteSets", nil] owner: self];
		[pboard setData: [NSKeyedArchiver archivedDataWithRootObject: items] forType: @"RouteSets"];

		return YES;
	}

	return NO;
}

// is this a valid drop target?
- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id < NSDraggingInfo >)info proposedItem:(id)item proposedChildIndex:(NSInteger)index{
	
	//PGLog(@"VALIDATE: %d %@ %@", index, item, info);
	
	// can't copy a RouteSet into a RouteSet!
	if ( [item isKindOfClass:[RouteSet class]] ){
		return NSDragOperationNone;
	}
	
	// always allow a move!
	return NSDragOperationMove;	  
}

- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id < NSDraggingInfo >)info item:(id)item childIndex:(NSInteger)index{
	
	//PGLog(@"ACCEPT: %d %@ %@", index, item, info);
	
	if ( outlineView == routesTable ){
		
		if ( ![item isKindOfClass:[RouteCollection class]] ){
			return NO;
		}
	
		// note to self, the objects here are COPIES, not the originals, so act accordingly
		NSPasteboard* pboard = [info draggingPasteboard];
		NSData *data = [pboard dataForType: @"RouteSets"];
		
		if ( data ){

			NSArray *routes = [NSKeyedUnarchiver unarchiveObjectWithData: data];
			
			// now add these routes to their new home and remove from their old one :(
			for ( id route in routes ){
					
				if ( [route isKindOfClass:[RouteSet class]] ){

					// grab the old route collection
					RouteCollection *oldCollection = [(RouteSet*)route parent];
					
					// actually find it in the current list
					oldCollection = [self routeCollectionForUUID:[oldCollection UUID]];
					
					// remove the route
					[oldCollection removeRouteSet:route];
					
					// add to new!
					[(RouteCollection*)item addRouteSet:route];
				}
			}
			
			// reload the table
			[outlineView reloadData];
			
			return YES;
		}

	}
	
	return NO;
}

#pragma mark RouteCollection UI stuff

- (IBAction)deleteRoute: (id)sender{
	
	[self willChangeValueForKey: @"routeCollections"];
	
	id selectedItem = [self selectedRouteObject];
	
	if ( [selectedItem isKindOfClass:[RouteSet class]] ){
		
		RouteCollection *rc = [(RouteSet*)selectedItem parent];
		
		[rc removeRouteSet:selectedItem];
		
		[routesTable reloadData];
		
		// select the parent
		int row = [routesTable rowForItem:rc];
		
		// select the new item!
		[routesTable selectRow:row byExtendingSelection:NO];
		[routesTable scrollRowToVisible:row];
	}
	else if ( [selectedItem isKindOfClass:[RouteCollection class]] ){
		
		RouteCollection *rc = selectedItem;
		
		if ( [[rc routes] count] == 0 ){
			[_routeCollectionList removeObject:rc];
			
			// delete the file from our disk!
			[self deleteObject:rc];
			 
			[routesTable reloadData];
		}
		else{
			NSBeep();
			NSRunAlertPanel(@"Unable to delete", @"You cannot delete a set until the routes are first removed!", @"Okay", NULL, NULL);
		}		
	}
	
	[self didChangeValueForKey: @"routeCollections"];
}

- (IBAction)addRouteSet: (id)sender{
	
	id selectedItem = [self selectedRouteObject];
	
	// nothing is selected
	if ( selectedItem == nil ){
		NSBeep();
		NSRunAlertPanel(@"Select a Route Collection", @"Please select a route collection to add your route to! (you may have to create a new route collection first!)", @"Okay", NULL, NULL);
	}
	else{
		
		// we want the collection, not the set!
		if ( [selectedItem isKindOfClass:[RouteSet class]] ){
			selectedItem = [(RouteSet*)selectedItem parent];
		}

		// in theory this should always be the case
		if ( [selectedItem isKindOfClass:[RouteCollection class]] ){
			RouteSet *route = [RouteSet routeSetWithName:@"New Route"];
			[selectedItem addRouteSet:route];
			[selectedItem setChanged:YES];
			[routesTable reloadData];
			
			// expand our collection
			[routesTable expandItem:selectedItem];

			[self selectItemInOutlineViewToEdit:route];
		}
		else{
			PGLog(@"[Routes] Error when adding a set! Report to Tanaris4! %@", selectedItem);
			NSBeep();
			NSRunAlertPanel(@"Error when adding route", @"Error when adding route! Report to Tanaris4 + give him logs!", @"Okay", NULL, NULL);
		}
	}
}

- (IBAction)addRouteCollection: (id)sender{
	
	[self willChangeValueForKey: @"routeCollections"];
	
	// add item and reload the table!
	RouteCollection *rc = [RouteCollection routeCollectionWithName:@"New Set"];
	[_routeCollectionList addObject:rc];
	[routesTable reloadData];
	
	[self selectItemInOutlineViewToEdit:rc];
	
	[self didChangeValueForKey: @"routeCollections"];
}

- (IBAction)startingRouteClicked: (id)sender{
	
	RouteCollection *parentRC = [[self currentRouteSet] parent];
	
	if ( [startingRouteButton state] )
		[parentRC setStartRoute:[self currentRouteSet]];
	else
		[parentRC setStartRoute:nil];
}

#pragma mark RouteCollection helpers

- (void)selectItemInOutlineViewToEdit:(id)item{

	// get the row of our new route!
	int row = [routesTable rowForItem:item];
	
	// select the new item!
	[routesTable selectRow:row byExtendingSelection:NO];
	[routesTable scrollRowToVisible:row];
	
	// edit the new item!
	[routesTable editColumn:0 row:row withEvent:nil select:YES];
}

- (RouteCollection*)routeCollectionForUUID:(NSString*)UUID{
	
	for ( RouteCollection *rc in _routeCollectionList ){
		if ( [[rc UUID] isEqualToString:UUID] ){
			return rc;
		}
	}
	return nil;
}

- (id)selectedRouteObject{
	
	// make sure only 1 item is selected!
	if ( [routesTable numberOfSelectedRows] == 1 ){
		return [routesTable itemAtRow:[routesTable selectedRow]];
	}
	
	return nil;		
}

#pragma mark Help

- (void)showHelpPanel{
	
	[NSApp beginSheet: helpPanel
	   modalForWindow: [self.view window]
		modalDelegate: nil
	   didEndSelector: nil
		  contextInfo: nil];
}

- (IBAction)closeHelpPanel: (id)sender{
	[[sender window] makeFirstResponder: [[sender window] contentView]];
	[NSApp endSheet: helpPanel returnCode: 1];
    [helpPanel orderOut: nil];
}

#pragma mark ShortcutRecorder Delegate

- (void)checkHotkeys: (NSNotification*)notification {
    BOOL isAddWaypointEnabled = ([[PTHotKeyCenter sharedCenter] hotKeyWithIdentifier: AddWaypointHotkeyIdentifier]) ? YES : NO;
    
    if( [notification object] == self.view ) {
        if(!isAddWaypointEnabled) {
            [self toggleGlobalHotKey: shortcutRecorder];
        }
    } else {
		// Adding another waypoint
        if(isAddWaypointEnabled) {
            [self toggleGlobalHotKey: shortcutRecorder];
        }
    }
	
	// display a guide?
	if ( [notification object] == self.view && _firstTimeEverOnTheNewRouteCollections ) {
		[self showHelpPanel];
	}
}

- (void)toggleGlobalHotKey:(id)sender
{
	// Only if we come from shortcutRecorder!  Can probably combine this into one function but I'm a n00b
	if ( sender == shortcutRecorder )
	{
		if (addWaypointGlobalHotkey != nil) {
			[[PTHotKeyCenter sharedCenter] unregisterHotKey: addWaypointGlobalHotkey];
			[addWaypointGlobalHotkey release];
			addWaypointGlobalHotkey = nil;
		} else {
			KeyCombo keyCombo = [shortcutRecorder keyCombo];
			
			if(keyCombo.code >= 0 && keyCombo.flags >= 0) {
				addWaypointGlobalHotkey = [[PTHotKey alloc] initWithIdentifier: AddWaypointHotkeyIdentifier
																	  keyCombo: [PTKeyCombo keyComboWithKeyCode: keyCombo.code
																									  modifiers: [shortcutRecorder cocoaToCarbonFlags: keyCombo.flags]]];
				
				[addWaypointGlobalHotkey setTarget: self];
				[addWaypointGlobalHotkey setAction: @selector(addWaypoint:)];
				
				[[PTHotKeyCenter sharedCenter] registerHotKey: addWaypointGlobalHotkey];
			}
		}
	}
	
	// Automator only pls
	if ( sender == automatorRecorder )
	{
		if (automatorGlobalHotkey != nil) {
			[[PTHotKeyCenter sharedCenter] unregisterHotKey: automatorGlobalHotkey];
			[automatorGlobalHotkey release];
			automatorGlobalHotkey = nil;
		} else {
			KeyCombo keyCombo = [automatorRecorder keyCombo];
			
			if(keyCombo.code >= 0 && keyCombo.flags >= 0) {
				automatorGlobalHotkey = [[PTHotKey alloc] initWithIdentifier: AutomatorHotkeyIdentifier
																	  keyCombo: [PTKeyCombo keyComboWithKeyCode: keyCombo.code
																									  modifiers: [automatorRecorder cocoaToCarbonFlags: keyCombo.flags]]];
				
				[automatorGlobalHotkey setTarget: self];
				[automatorGlobalHotkey setAction: @selector(startStopAutomator:)];
				
				[[PTHotKeyCenter sharedCenter] registerHotKey: automatorGlobalHotkey];
			}
		}
		
	}
}

- (void)shortcutRecorder:(SRRecorderControl *)recorder keyComboDidChange:(KeyCombo)newKeyCombo {
    
	if(recorder == shortcutRecorder) {
		[[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithInt: newKeyCombo.code] forKey: @"WaypointAdd_HotkeyCode"];
		[[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithInt: newKeyCombo.flags] forKey: @"WaypointAdd_HotkeyFlags"];
		[[NSUserDefaults standardUserDefaults] synchronize];
	}
    
	if(recorder == automatorRecorder) {
		[[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithInt: newKeyCombo.code] forKey: @"WaypointAutomator_HotkeyCode"];
		[[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithInt: newKeyCombo.flags] forKey: @"WaypointAutomator_HotkeyFlags"];
		[[NSUserDefaults standardUserDefaults] synchronize];
	}
	
    // register this hotkey globally
    [self toggleGlobalHotKey: recorder];
}

#pragma mark Waypoint Condition/Actions - New!

- (IBAction)waypointMenuAction: (id)sender{
	
	//int clickedRow = [waypointTable clickedRow];
	
	// set description
	if ( [sender tag] == 0 ){

		[_selectedRows release]; _selectedRows = nil;
		_selectedRows = [[waypointTable selectedRowIndexes] retain];
		
		// only one row, so ezmode to set the title
		if ( [_selectedRows count] == 1 ){
			Waypoint *wp = [[self currentRoute] waypointAtIndex: [_selectedRows firstIndex]];
			self.descriptionMultiRows = wp.title;
		}
		// multiple rows, select the first value
		else {
			Waypoint *wp = nil;
			int i = [_selectedRows firstIndex];
			for ( ; i <= [_selectedRows lastIndex]; i++ ){
				wp = [[self currentRoute] waypointAtIndex: i];
				
				if ( wp && [wp.title length] > 0 ){
					self.descriptionMultiRows = wp.title;
					break;
				}
			}
		}

		// open up the screen!
		[NSApp beginSheet: descriptionPanel
		   modalForWindow: [self.view window]
			modalDelegate: nil
		   didEndSelector: nil
			  contextInfo: nil];
	}
}

- (IBAction)closeDescription: (id)sender {
    [[sender window] makeFirstResponder: [[sender window] contentView]];
    [NSApp endSheet: descriptionPanel returnCode: 1];
    [descriptionPanel orderOut: nil];
	
	// save the new description
	// only one row, so ezmode to set the title
	if ( [_selectedRows count] == 1 ){
		Waypoint *wp = [[self currentRoute] waypointAtIndex: [_selectedRows firstIndex]];
		wp.title = _descriptionMultiRows;
	}
	// multiple rows
	else{
		Waypoint *wp = nil;
		int i = [_selectedRows firstIndex];
		for ( ; i <= [_selectedRows lastIndex]; i++ ){
			wp = [[self currentRoute] waypointAtIndex: i];
			
			if ( wp ){
				wp.title = _descriptionMultiRows;;
			}
		}
	}
}

// sets our NSLabel that is above the tabs!
- (void)setViewTitle{
	
	if ( [[[waypointTabView selectedTabViewItem] identifier] intValue] == 0 ) {
		
		if ( self.currentRouteSet )
			[waypointSectionTitle setStringValue:[NSString stringWithFormat:@"Waypoints for: %@", [self.currentRouteSet name]]];
		else
			[waypointSectionTitle setStringValue:@"No route selected"];
	}
	else if ( [[[waypointTabView selectedTabViewItem] identifier] intValue] == 1 ) {
		
		NSString *name = nil;
		if ( self.currentRouteCollection ){
			name = [self.currentRouteCollection name];			
		}
		else if ( self.currentRouteSet ){
			RouteCollection *parentRC = [self.currentRouteSet parent];
			name = [parentRC name];
		}
		
		if ( name )
			[waypointSectionTitle setStringValue:[NSString stringWithFormat:@"Options for: %@", name]];
		else
			[waypointSectionTitle setStringValue:@"No route set selected"];
	}
}

#pragma mark SaveData

// for saving
- (NSString*)objectExtension{
	// just to load old data
	if ( _myHackVariable ){
		return @"route";
	}
	
	return @"routecollection";
}

- (NSString*)objectName:(id)object{
	if ( _myHackVariable ){
		return [(RouteSet*)object name];
	}
	
	return [(RouteCollection*)object name];
}

@end
