/*
	This file is part of ppather.

	PPather is free software: you can redistribute it and/or modify
	it under the terms of the GNU Lesser General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.

	PPather is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU Lesser General Public License for more details.

	You should have received a copy of the GNU Lesser General Public License
	along with ppather.  If not, see <http://www.gnu.org/licenses/>.

	Copyright Pontus Borg 2008
	Ported to Objective-C by wjlafrance@gmail.com
*/

#import <Cocoa/Cocoa.h>
#import "PPather.h"


@interface WDT : NSObject {
	int gnWMO;
	
	BOOL maps[64][64];
	//MapTile[64][64] mapTiles;
	
	NSMutableArray *GMOs;
	NSMutableArray *GMOIs;
}

- (id) initWithWdtFile:(NSString *)filename;

@end