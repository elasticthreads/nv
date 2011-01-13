/*Copyright (c) 2010, Zachary Schneirov. All rights reserved.
  Redistribution and use in source and binary forms, with or without modification, are permitted 
  provided that the following conditions are met:
   - Redistributions of source code must retain the above copyright notice, this list of conditions 
     and the following disclaimer.
   - Redistributions in binary form must reproduce the above copyright notice, this list of 
	 conditions and the following disclaimer in the documentation and/or other materials provided with
     the distribution.
   - Neither the name of Notational Velocity nor the names of its contributors may be used to endorse 
     or promote products derived from this software without specific prior written permission. */


#import "UnifiedCell.h"
#import "NoteObject.h"
#import "GlobalPrefs.h"
#import "NSString_CustomTruncation.h"

@implementation UnifiedCell

- (id)init {
	if ([super init]) {

		//should be handled by NSParagraphStyle in our string, as it is more complex than this
//		[self setLineBreakMode:NSLineBreakByTruncatingTail];
		if (IsLeopardOrLater)
			[self setTruncatesLastVisibleLine:YES];
	}
	return self;
}

- (void)dealloc {
	[super dealloc];
}

- (NoteObject*)noteObject {
	return noteObject;
}
	
- (void)setNoteObject:(NoteObject*)obj {
	[noteObject autorelease];
	noteObject = [obj retain];
}

- (BOOL)isActiveStyle {
	return isActiveStyle;
}
- (void)setIsActiveStyle:(BOOL)value {
	isActiveStyle = value;
}

- (NSMutableDictionary*)baseTextAttributes {
	static NSMutableParagraphStyle *alignStyle = nil;
	if (!alignStyle) {
		alignStyle = [[NSMutableParagraphStyle alloc] init];
		[alignStyle setAlignment:NSRightTextAlignment];
	}
	return [NSMutableDictionary dictionaryWithObjectsAndKeys:alignStyle, NSParagraphStyleAttributeName, [self font], NSFontAttributeName, nil];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {	

	[super drawWithFrame:cellFrame inView:controlView];	
	
	//draw note date and tags

	NSMutableDictionary *baseAttrs = [self baseTextAttributes];
	if ([self isHighlighted] && isActiveStyle) {
		[baseAttrs setObject:[NSColor whiteColor] forKey:NSForegroundColorAttributeName];
	} else if (![self isHighlighted]) {
		[baseAttrs setObject:[NSColor grayColor] forKey:NSForegroundColorAttributeName];
	}
	
	NSString *str = dateModifiedStringOfNote((NotesTableView*)controlView, noteObject, NSNotFound);
	[str drawInRect:NSMakeRect(NSMaxX(cellFrame) - 70.0, NSMinY(cellFrame), 70.0, [[self font] capHeight]*2) withAttributes:baseAttrs];
}

@end
