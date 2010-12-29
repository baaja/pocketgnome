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


@interface DBC : NSObject {

	uint recordSize;
	uint recordCount;
	uint fieldCount;
	uint stringSize;
	
	NSMutableArray *data;
	NSMutableArray *stringdata;
	
}

- (id) initWithDbcFile:(NSString *)filename;
- (uint) numberOfRecords;
- (uint) getUintForRecord:(int)record andField:(int)field;
- (NSString *) getStringForRecord:(int)record andField:(int)field;
- (int) getRecordNumberByValue:(uint)value ofField:(uint)field;

@end