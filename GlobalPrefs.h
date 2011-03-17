//
//  GlobalPrefs.h
//  Notation
//
//  Created by Zachary Schneirov on 1/31/06.

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


#import <Cocoa/Cocoa.h>
#import "SynchronizedNoteProtocol.h"

extern NSString *NoteTitleColumnString;
extern NSString *NoteLabelsColumnString;
extern NSString *NoteDateModifiedColumnString;
extern NSString *NoteDateCreatedColumnString;
extern NSString *NotePreviewString;

extern NSString *NVPTFPboardType;

@class NotesTableView;
@class BookmarksController;
@class NotationPrefs;
@class PTKeyCombo;
@class PTHotKey;

enum { NoteTitleColumn, NoteLabelsColumn, NoteDateModifiedColumn, NoteDateCreatedColumn };

#define ColumnIsSet(__ColumnEnum, __columnsBitmap) (((1 << (__ColumnEnum)) & (__columnsBitmap)) != 0)


BOOL ColorsEqualWith8BitChannels(NSColor *c1, NSColor *c2);

@interface GlobalPrefs : NSObject {
	NSUserDefaults *defaults;
	
	IMP runCallbacksIMP;
	NSMutableDictionary *selectorObservers;
	
	PTKeyCombo *appActivationKeyCombo;
	PTHotKey *appActivationHotKey;
	
	BookmarksController *bookmarksController;
	NotationPrefs *notationPrefs;
	NSDictionary *noteBodyAttributes, *searchTermHighlightAttributes;
	NSMutableParagraphStyle *noteBodyParagraphStyle;
	NSFont *noteBodyFont;
	BOOL autoCompleteSearches;
	
	NSMutableArray *tableColumns;
	unsigned int tableColsBitmap;
}

+ (GlobalPrefs *)defaultPrefs;

- (void)registerWithTarget:(id)sender forChangesInSettings:(SEL)firstSEL, ...;
- (void)registerForSettingChange:(SEL)selector withTarget:(id)sender;
- (void)unregisterForNotificationsFromSelector:(SEL)selector sender:(id)sender;
- (void)notifyCallbacksForSelector:(SEL)selector excludingSender:(id)sender;

- (void)setNotationPrefs:(NotationPrefs*)newNotationPrefs sender:(id)sender;
- (NotationPrefs*)notationPrefs;

- (void)removeTableColumn:(NSString*)columnKey sender:(id)sender;
- (void)addTableColumn:(NSString*)columnKey sender:(id)sender;
- (NSArray*)visibleTableColumns;
- (unsigned int)tableColumnsBitmap;

- (void)setSortedTableColumnKey:(NSString*)sortedKey reversed:(BOOL)reversed sender:(id)sender;
- (NSString*)sortedTableColumnKey;
- (BOOL)tableIsReverseSorted;

- (BOOL)tableColumnsShowPreview;
- (void)setTableColumnsShowPreview:(BOOL)showPreview sender:(id)sender;

- (void)resolveNoteBodyFontFromNotationPrefsFromSender:(id)sender;
- (void)setNoteBodyFont:(NSFont*)aFont sender:(id)sender;
- (void)_setNoteBodyFont:(NSFont*)aFont;
- (NSFont*)noteBodyFont;
- (NSDictionary*)noteBodyAttributes;
- (NSParagraphStyle*)noteBodyParagraphStyle;
- (BOOL)_bodyFontIsMonospace;

- (void)setForegroundTextColor:(NSColor*)aColor sender:(id)sender;
- (NSColor*)foregroundTextColor;
- (void)setBackgroundTextColor:(NSColor*)aColor sender:(id)sender;
- (NSColor*)backgroundTextColor;

- (void)setTabIndenting:(BOOL)value sender:(id)sender;
- (BOOL)tabKeyIndents;

- (void)setUseTextReplacement:(BOOL)value sender:(id)sender;
- (BOOL)useTextReplacement;	

- (void)setCheckSpellingAsYouType:(BOOL)value sender:(id)sender;
- (BOOL)checkSpellingAsYouType;

- (void)setConfirmNoteDeletion:(BOOL)value sender:(id)sender;
- (BOOL)confirmNoteDeletion;

- (void)setQuitWhenClosingWindow:(BOOL)value sender:(id)sender;
- (BOOL)quitWhenClosingWindow;

- (void)setAppActivationKeyCombo:(PTKeyCombo*)aCombo sender:(id)sender;
- (PTKeyCombo*)appActivationKeyCombo;
- (PTHotKey*)appActivationHotKey;
- (BOOL)registerAppActivationKeystrokeWithTarget:(id)target selector:(SEL)selector;

- (void)setPastePreservesStyle:(BOOL)value sender:(id)sender;
- (BOOL)pastePreservesStyle;

- (void)setAutoFormatsDoneTag:(BOOL)value sender:(id)sender;
- (BOOL)autoFormatsDoneTag;

- (BOOL)autoIndentsNewLines;
- (void)setAutoIndentsNewLines:(BOOL)value sender:(id)sender;

- (BOOL)autoFormatsListBullets;
- (void)setAutoFormatsListBullets:(BOOL)value sender:(id)sender;

- (void)setLinksAutoSuggested:(BOOL)value sender:(id)sender;
- (BOOL)linksAutoSuggested;

- (void)setMakeURLsClickable:(BOOL)value sender:(id)sender;
- (BOOL)URLsAreClickable;

- (void)setShouldHighlightSearchTerms:(BOOL)shouldHighlight sender:(id)sender;
- (BOOL)highlightSearchTerms;
- (void)setSearchTermHighlightColor:(NSColor*)color sender:(id)sender;
- (NSDictionary*)searchTermHighlightAttributes;
- (NSColor*)searchTermHighlightColorRaw:(BOOL)isRaw;

- (void)setSoftTabs:(BOOL)value sender:(id)sender;
- (BOOL)softTabs;

- (int)numberOfSpacesInTab;

- (float)tableFontSize;
- (void)setTableFontSize:(float)fontSize sender:(id)sender;

- (void)setHorizontalLayout:(BOOL)value sender:(id)sender;
- (BOOL)horizontalLayout;

- (BOOL)autoCompleteSearches;
- (void)setAutoCompleteSearches:(BOOL)value sender:(id)sender;

- (NSString*)lastSelectedPreferencesPane;
- (void)setLastSelectedPreferencesPane:(NSString*)pane sender:(id)sender;

- (double)scrollOffsetOfLastSelectedNote;
- (CFUUIDBytes)UUIDBytesOfLastSelectedNote;
- (NSString*)lastSearchString;
- (void)setLastSearchString:(NSString*)string selectedNote:(id<SynchronizedNote>)aNote scrollOffsetForTableView:(NotesTableView*)tv sender:(id)sender;

- (void)saveCurrentBookmarksFromSender:(id)sender;
- (BookmarksController*)bookmarksController;

- (void)setAliasDataForDefaultDirectory:(NSData*)alias sender:(id)sender;
- (NSData*)aliasDataForDefaultDirectory;

- (NSImage*)iconForDefaultDirectoryWithFSRef:(FSRef*)fsRef;
- (NSString*)displayNameForDefaultDirectoryWithFSRef:(FSRef*)fsRef;
- (NSString*)humanViewablePathForDefaultDirectory;

- (void)setBlorImportAttempted:(BOOL)value;
- (BOOL)triedToImportBlor;

- (void)synchronize;

//
- (NSString *)textEditor;
- (void)setTextEditor:(NSString *)inApp;
- (BOOL)managesTextWidthInWindow;
- (int)maxNoteBodyWidth;
- (void)setMaxNoteBodyWidth:(int)maxWidth;
- (void)setRTL:(BOOL)value sender:(id)sender;
- (BOOL)rtl;
- (BOOL)showWordCount;
- (void)setShowWordCount:(BOOL)value;
- (void)setUseMarkdownImport:(BOOL)value sender:(id)sender;
- (BOOL)useMarkdownImport;
- (void)setUseReadability:(BOOL)value sender:(id)sender;
- (BOOL)useReadability;
@end

@interface NSObject (GlobalPrefsDelegate)
	- (void)settingChangedForSelectorString:(NSString*)selectorString;
@end


