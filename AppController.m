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
//ET NV4

//#import "NVTransparentScroller.h"

#import "NSTextFinder.h"
#import "AppController.h"
#import "NoteObject.h"
#import "GlobalPrefs.h"
#import "AlienNoteImporter.h"
#import "AppController_Importing.h"
#import "NotationPrefs.h"
#import "PrefsWindowController.h"
#import "NoteAttributeColumn.h"
#import "NotationSyncServiceManager.h"
#import "NotationDirectoryManager.h"
#import "NotationFileManager.h"
#import "NSString_NV.h"
#import "NSFileManager_NV.h"
#import "EncodingsManager.h"
#import "ExporterManager.h"
#import "NSData_transformations.h"
#import "BufferUtils.h"
#import "LinkingEditor.h"
#import "EmptyView.h"
#import "DualField.h"
#import "TitlebarButton.h"
#import "RBSplitView/RBSplitView.h"
#import "AugmentedScrollView.h"
#import "BookmarksController.h"
#import "SyncSessionController.h"
#import "MultiplePageView.h"
#import "InvocationRecorder.h"
#import "LinearDividerShader.h"
#import "SecureTextEntryManager.h"
#import "TagEditingManager.h"
#import "NotesTableHeaderCell.h"
#import "DFView.h"
#import "StatusItemView.h"
#import "ETContentView.h"
#import "PreviewController.h"

#define NSApplicationPresentationAutoHideMenuBar (1 <<  2)
#define NSApplicationPresentationHideMenuBar (1 <<  3)
//#define NSApplicationPresentationAutoHideDock (1 <<  0)
#define NSApplicationPresentationHideDock (1 <<  1)
//#define NSApplicationActivationPolicyAccessory

#define NSTextViewChangedNotification @"TextView has changed contents"
#define kDefaultMarkupPreviewMode @"markupPreviewMode"

NSWindow *normalWindow;
NSSize normalInset;
int ModFlagger;
BOOL splitViewAwoke;

@implementation AppController

//an instance of this class is designated in the nib as the delegate of the window, nstextfield and two nstextviews

+ (void)initialize
{
    NSDictionary *appDefaults = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:MultiMarkdownPreview] forKey:kDefaultMarkupPreviewMode];
    
    [[NSUserDefaults standardUserDefaults] registerDefaults:appDefaults];
} // initialize


- (id)init {
    if ([super init]) {
        splitViewAwoke = NO;
		windowUndoManager = [[NSUndoManager alloc] init];

		previewController = [[PreviewController alloc] init];
		
        [[NSNotificationCenter defaultCenter] addObserver:previewController selector:@selector(requestPreviewUpdate:) name:NSTextViewChangedNotification object:self];
      
		
		// Setup URL Handling
		NSAppleEventManager *appleEventManager = [NSAppleEventManager sharedAppleEventManager];
		[appleEventManager setEventHandler:self andSelector:@selector(handleGetURLEvent:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];	
		
	//	dividerShader = [[LinearDividerShader alloc] initWithStartColor:[NSColor colorWithCalibratedWhite:0.988 alpha:1.0] 
	//														   endColor:[NSColor colorWithCalibratedWhite:0.875 alpha:1.0]];
		dividerShader = [[[LinearDividerShader alloc] initWithBaseColors:self] retain];
		isCreatingANote = isFilteringFromTyping = typedStringIsCached = NO;
		typedString = @"";
		//elasticthreads' no dock icon option (note also in info.plist that the application has been set to LSUIElement=1
        if (![[[NSUserDefaults standardUserDefaults] stringForKey:@"HideDockIcon"] isEqualToString:@"Show Dock Icon"]){		
            if((IsSnowLeopardOrLater)&&([[NSApplication sharedApplication] respondsToSelector: @selector(setActivationPolicy:)])) {
                enum {NSApplicationActivationPolicyRegular};	
                [[NSApplication sharedApplication] setActivationPolicy:NSApplicationActivationPolicyRegular];
            }else {
                ProcessSerialNumber psn = { 0, kCurrentProcess }; 
                OSStatus returnCode = TransformProcessType(&psn, kProcessTransformToForegroundApplication);
                if( returnCode != 0) {
                    NSLog(@"Could not bring the application to front. Error %d", returnCode);
                }
            }	
        }
    }
    return self;
}

- (void)awakeFromNib {
	[NSApp setDelegate:self];
	[window setDelegate:self];
    
    //ElasticThreads>> set up the rbsplitview programatically to remove dependency on IBPlugin
    NSRect mRect = [[window contentView] frame];
    mainView = [[[ETContentView alloc] initWithFrame:mRect] retain];
    [window setContentView:mainView];
    splitView = [[[RBSplitView alloc] initWithFrame:mRect andSubviews:2] retain];
    [splitView setAutosaveName:@"centralSplitView" recursively:NO];
    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(1.0,1.0)] autorelease];
    [image lockFocus];
    [[NSColor clearColor] set];
    
    NSRectFill(NSMakeRect(0.0,0.0,1.0,1.0));
    [image unlockFocus];
    [image setFlipped:YES];
    [splitView setDivider:image];
    
    [splitView setDividerThickness:8.0f];
    [splitView setDelegate:self];
    [splitView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [mainView addSubview:splitView];
    [splitView setNextKeyView:notesTableView];
    notesSubview = [[splitView subviewAtPosition:0] retain];
	[notesSubview setMinDimension: 80.0 andMaxDimension:600.0];	
    [notesSubview setCanCollapse:YES];
    [notesSubview setAutoresizesSubviews:YES];
    splitSubview = [[splitView subviewAtPosition:1] retain];
    [splitSubview setMinDimension:1 andMaxDimension:0];
    [splitSubview setCanCollapse:NO];
    [splitSubview setAutoresizesSubviews:YES];
    [notesSubview addSubview:notesScrollView];
    [notesScrollView setFrame:[notesSubview frame]];
    [notesScrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [splitSubview addSubview:textScrollView];
    [textScrollView setFrame:[splitSubview frame]];
    [textScrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    
    [mainView setNeedsDisplay:YES];
    [splitView adjustSubviews];    
    [splitView needsDisplay];
    splitViewAwoke = YES;
    
	prefsController = [GlobalPrefs defaultPrefs];
	
	normalInset = NSMakeSize(3.0f,8.0f);
	[NSColor setIgnoresAlpha:NO];
	
	//For ElasticThreads' fullscreen implementation. delete the next line of code and uncomment the following the block to undo
	[self setDualFieldInToolbar];
	/*
	NSView *dualSV = [field superview];
	dualFieldItem = [[NSToolbarItem alloc] initWithItemIdentifier:@"DualField"];
	//[[dualSV superview] setFrameSize:NSMakeSize([[dualSV superview] frame].size.width, [[dualSV superview] frame].size.height -1)];
	[dualFieldItem setView:dualSV];
	[dualFieldItem setMaxSize:NSMakeSize(FLT_MAX, [dualSV frame].size.height)];
	[dualFieldItem setMinSize:NSMakeSize(50.0f, [dualSV frame].size.height)];
    [dualFieldItem setLabel:NSLocalizedString(@"Search or Create", @"placeholder text in search/create field")];
	
	toolbar = [[NSToolbar alloc] initWithIdentifier:@"NVToolbar"];
	[toolbar setAllowsUserCustomization:NO];
	[toolbar setAutosavesConfiguration:NO];
	[toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
//	[toolbar setSizeMode:NSToolbarSizeModeRegular];
	[toolbar setShowsBaselineSeparator:YES];
	[toolbar setVisible:![[NSUserDefaults standardUserDefaults] boolForKey:@"ToolbarHidden"]];
	[toolbar setDelegate:self];
	[window setToolbar:toolbar];
	
	[window setShowsToolbarButton:NO];
	titleBarButton = [[TitlebarButton alloc] initWithFrame:NSMakeRect(0, 0, 17.0, 17.0) pullsDown:YES];
	[titleBarButton addToWindow:window];
	*/
	
	
	
//	if (IsLeopardOrLater)
//		[window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];
	
    
	[notesTableView setDelegate:self];
	[field setDelegate:self];
	[textView setDelegate:self];
    
	//set up temporary FastListDataSource containing false visible notes
		
	//this will not make a difference
	[window useOptimizedDrawing:YES];
	

	//[window makeKeyAndOrderFront:self];
	//[self setEmptyViewState:YES];
	
	// Create elasticthreads' NSStatusItem.
	if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"StatusBarItem"]) {
		float width = 25.0f;
		CGFloat height = [[NSStatusBar systemStatusBar] thickness];
		NSRect viewFrame = NSMakeRect(0.0f, 0.0f, width, height);
		statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:width] retain];
		cView = [[[StatusItemView alloc] initWithFrame:viewFrame controller:self] autorelease];
		[statusItem setView:cView];		
	}
	
	NSInteger previewMode = [[NSUserDefaults standardUserDefaults] integerForKey:kDefaultMarkupPreviewMode];
    currentPreviewMode = previewMode;
    if (previewMode == MarkdownPreview) {
        [multiMarkdownPreview setState:NSOnState];
    } else if (previewMode == MultiMarkdownPreview) {
        [multiMarkdownPreview setState:NSOnState];
    } else if (previewMode == TextilePreview) {
        [textilePreview setState:NSOnState];
    }
	
	[NSApp setServicesProvider:self];
	outletObjectAwoke(self);
}

//really need make AppController a subclass of NSWindowController and stick this junk in windowDidLoad
- (void)setupViewsAfterAppAwakened {
	static BOOL awakenedViews = NO;
	if (!awakenedViews) {
		//NSLog(@"all (hopefully relevant) views awakend!");
		[self _configureDividerForCurrentLayout];
		[splitView restoreState:YES];
		if ([notesSubview dimension]<200.0) {
			if ([splitView isVertical]) {   ///vertical means "Horiz layout"/notes list is to the left of the note body
				if (([splitView frame].size.width < 600.0) && ([splitView frame].size.width - 400 > [notesSubview dimension])) {
					[notesSubview setDimension:[splitView frame].size.width-400.0];
				}else if ([splitView frame].size.width >= 600.0) {	
					[notesSubview setDimension:200.0];
				}
			}else{
				if (([splitView frame].size.height < 600.0) && ([splitView frame].size.height - 400 > [notesSubview dimension])) {
					[notesSubview setDimension:[splitView frame].size.height-450.0];
				}else if ([splitView frame].size.height >= 600.0){		
					[notesSubview setDimension:150.0];
				}
			}
		}
		[splitView adjustSubviews];
		[splitSubview addSubview:editorStatusView positioned:NSWindowAbove relativeTo:splitSubview];
		[editorStatusView setFrame:[[textView enclosingScrollView] frame]];
		
		[notesTableView restoreColumns];
		
		[field setNextKeyView:textView];
		[textView setNextKeyView:field];
		[window setAutorecalculatesKeyViewLoop:NO];
		
		[self setMaxNoteBodyWidth];
		
		[self setEmptyViewState:YES];	
		ModFlagger = 0;
		userScheme = [[NSUserDefaults standardUserDefaults] integerForKey:@"ColorScheme"];
		if (userScheme==0) {
			[self setBWColorScheme:self];
		}else if (userScheme==1) {
			[self setLCColorScheme:self];
		}else if (userScheme==2) {
			[self setUserColorScheme:self];
		}	
		//this is necessary on 10.3; keep just in case
		[splitView display];
		
        
        if (![NSApp isActive]) {
            [NSApp activateIgnoringOtherApps:YES];
        }
		awakenedViews = YES;
	}
}

//what a hack
void outletObjectAwoke(id sender) {
	static NSMutableSet *awokenOutlets = nil;
	if (!awokenOutlets) awokenOutlets = [[NSMutableSet alloc] initWithCapacity:5];
   
        
	[awokenOutlets addObject:sender];
	
	AppController* appDelegate = (AppController*)[NSApp delegate];
	
	if ((appDelegate) && ([awokenOutlets containsObject:appDelegate] &&
		[awokenOutlets containsObject:appDelegate->notesTableView] &&
		[awokenOutlets containsObject:appDelegate->textView] &&
		[awokenOutlets containsObject:appDelegate->editorStatusView]) &&(splitViewAwoke)) {
		// && [awokenOutlets containsObject:appDelegate->splitView])
		[appDelegate setupViewsAfterAppAwakened];
	}
}

- (void)runDelayedUIActionsAfterLaunch {
	[[prefsController bookmarksController] setAppController:self];
	[[prefsController bookmarksController] restoreWindowFromSave];
	[[prefsController bookmarksController] updateBookmarksUI];
	[self updateNoteMenus];
	[textView setupFontMenu];
	[prefsController registerAppActivationKeystrokeWithTarget:self selector:@selector(toggleNVActivation:)];
	[notationController updateLabelConnectionsAfterDecoding];
	[notationController checkIfNotationIsTrashed];
	[[SecureTextEntryManager sharedInstance] checkForIncompatibleApps];
	
	//connect sparkle programmatically to avoid loading its framework at nib awake;
	
	if (!NSClassFromString(@"SUUpdater")) {
		NSString *frameworkPath = [[[NSBundle bundleForClass:[self class]] privateFrameworksPath] stringByAppendingPathComponent:@"Sparkle.framework"];
		if ([[NSBundle bundleWithPath:frameworkPath] load]) {
			id updater = [NSClassFromString(@"SUUpdater") performSelector:@selector(sharedUpdater)];
			[sparkleUpdateItem setTarget:updater];
			[sparkleUpdateItem setAction:@selector(checkForUpdates:)];
			NSMenuItem *siSparkle = [statBarMenu itemWithTag:902];
			[siSparkle setTarget:updater];
			[siSparkle setAction:@selector(checkForUpdates:)];
			if (![[prefsController notationPrefs] firstTimeUsed]) {
				//don't do anything automatically on the first launch; afterwards, check every 4 days, as specified in Info.plist
				SEL checksSEL = @selector(setAutomaticallyChecksForUpdates:);
				[updater methodForSelector:checksSEL](updater, checksSEL, YES);
			}
		} else {
			NSLog(@"Could not load %@!", frameworkPath);
		}
	}
	// add elasticthreads' menuitems
	NSMenuItem *theMenuItem = [[[NSMenuItem alloc] initWithTitle:@"Open Note in TextEdit" 
												  action:@selector(openFileInEditor:) keyEquivalent:@"O"] autorelease];
	if ([prefsController textEditor]) {
		[theMenuItem setTitle:[@"Open Note in " stringByAppendingString:[prefsController textEditor]]];
	}
	NSMenu *notesMenu = [[[NSApp mainMenu] itemWithTag:NOTES_MENU_ID] submenu];
	[theMenuItem setTarget:self];
	[notesMenu insertItem:theMenuItem atIndex:9];
	theMenuItem = [theMenuItem copy];
	[statBarMenu insertItem:theMenuItem atIndex:4];
	[theMenuItem release];
	if(IsLeopardOrLater){
		theMenuItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Toggle Fullscreen Mode",@"menu item title for toggling fs") 
												  action:@selector(toggleFullscreen:) keyEquivalent:@"F"] autorelease];
		
		[theMenuItem setTarget:self];
		NSMenu *viewMenu = [[[NSApp mainMenu] itemWithTag:VIEW_MENU_ID] submenu];
		[viewMenu insertItem:theMenuItem atIndex:1];
		theMenuItem = [theMenuItem copy];
		[statBarMenu insertItem:theMenuItem atIndex:11];
		[theMenuItem release];
	}

	if (![prefsController showWordCount]) {
		[wordCounter setHidden:NO];
	}else {			
		[wordCounter setHidden:YES];
	}
	//	
}

- (void)applicationDidFinishLaunching:(NSNotification*)aNote {
	//on tiger dualfield is often not ready to add tracking tracks until this point:
	[field setTrackingRect];
    NSDate *before = [NSDate date];
	prefsWindowController = [[PrefsWindowController alloc] init];
	
	OSStatus err = noErr;
	NotationController *newNotation = nil;
	NSData *aliasData = [prefsController aliasDataForDefaultDirectory];
	
	NSString *subMessage = @"";
	
	//if the option key is depressed, go straight to picking a new notes folder location
	if (kCGEventFlagMaskAlternate == (CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState) & NSDeviceIndependentModifierFlagsMask)) {
		goto showOpenPanel;
	}
	
	if (aliasData) {
	    newNotation = [[NotationController alloc] initWithAliasData:aliasData error:&err];
	    subMessage = NSLocalizedString(@"Please choose a different folder in which to store your notes.",nil);
	} else {
	    newNotation = [[NotationController alloc] initWithDefaultDirectoryReturningError:&err];
	    subMessage = NSLocalizedString(@"Please choose a folder in which your notes will be stored.",nil);
	}
	//no need to display an alert if the error wasn't real
	if (err == kPassCanceledErr)
		goto showOpenPanel;
	
	NSString *location = (aliasData ? [[NSFileManager defaultManager] pathCopiedFromAliasData:aliasData] : NSLocalizedString(@"your Application Support directory",nil));
	if (!location) { //fscopyaliasinfo sucks
		FSRef locationRef;
		if ([aliasData fsRefAsAlias:&locationRef] && LSCopyDisplayNameForRef(&locationRef, (CFStringRef*)&location) == noErr) {
			[location autorelease];
		} else {
			location = NSLocalizedString(@"its current location",nil);
		}
	}
	
	while (!newNotation) {
	    location = [location stringByAbbreviatingWithTildeInPath];
	    NSString *reason = [NSString reasonStringFromCarbonFSError:err];
		
	    if (NSRunAlertPanel([NSString stringWithFormat:NSLocalizedString(@"Unable to initialize notes database in \n%@ because %@.",nil), location, reason], 
							subMessage, NSLocalizedString(@"Choose another folder",nil),NSLocalizedString(@"Quit",nil),NULL) == NSAlertDefaultReturn) {
			//show nsopenpanel, defaulting to current default notes dir
			FSRef notesDirectoryRef;
		showOpenPanel:
			if (![prefsWindowController getNewNotesRefFromOpenPanel:&notesDirectoryRef returnedPath:&location]) {
				//they cancelled the open panel, or it was unable to get the path/FSRef of the file
				goto terminateApp;
			} else if ((newNotation = [[NotationController alloc] initWithDirectoryRef:&notesDirectoryRef error:&err])) {
				//have to make sure alias data is saved from setNotationController
				[newNotation setAliasNeedsUpdating:YES];
				break;
			}
	    } else {
			goto terminateApp;
	    }
	}
	
	[self setNotationController:newNotation];
	[newNotation release];
	
	NSLog(@"load time: %g, ",[[NSDate date] timeIntervalSinceDate:before]);
	//	NSLog(@"version: %s", PRODUCT_NAME);
	
	//import old database(s) here if necessary
	[AlienNoteImporter importBlorOrHelpFilesIfNecessaryIntoNotation:newNotation];
	
	if (pathsToOpenOnLaunch) {
		[notationController openFiles:[pathsToOpenOnLaunch autorelease]];
		pathsToOpenOnLaunch = nil;
	}
	
	if (URLToInterpretOnLaunch) {
		[self interpretNVURL:[URLToInterpretOnLaunch autorelease]];
		URLToInterpretOnLaunch = nil;
	}
	
	//tell us..
	[prefsController registerWithTarget:self forChangesInSettings:
	 @selector(setAliasDataForDefaultDirectory:sender:),  //when someone wants to load a new database
	 @selector(setSortedTableColumnKey:reversed:sender:),  //when sorting prefs changed
	 @selector(setNoteBodyFont:sender:),  //when to tell notationcontroller to restyle its notes
	 @selector(setForegroundTextColor:sender:),  //ditto
	 @selector(setBackgroundTextColor:sender:),  //ditto
	 @selector(setTableFontSize:sender:),  //when to tell notationcontroller to regenerate the (now potentially too-short) note-body previews
	 @selector(addTableColumn:sender:),  //ditto
	 @selector(removeTableColumn:sender:),  //ditto
	 @selector(setTableColumnsShowPreview:sender:),  //when to tell notationcontroller to generate or disable note-body previews
	 @selector(setConfirmNoteDeletion:sender:),  //whether "delete note" should have an ellipsis
	 @selector(setAutoCompleteSearches:sender:), nil];   //when to tell notationcontroller to build its title-prefix connections
	
	[self performSelector:@selector(runDelayedUIActionsAfterLaunch) withObject:nil afterDelay:0.0];
			
	return;
terminateApp:
	[NSApp terminate:self];
}

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent {
	
	NSURL *fullURL = [NSURL URLWithString:[[event paramDescriptorForKeyword:keyDirectObject] stringValue]];
	
	if (notationController) {
		if (![self interpretNVURL:fullURL])
			NSBeep();
	} else {
		URLToInterpretOnLaunch = [fullURL retain];
	}
}

- (void)setNotationController:(NotationController*)newNotation {
	
    if (newNotation) {
		if (notationController) {
			[notationController endDeletionManagerIfNecessary];
			[notationController stopSyncServices];
			[[NSNotificationCenter defaultCenter] removeObserver:self name:SyncSessionsChangedVisibleStatusNotification 
														  object:[notationController syncSessionController]];
			[notationController stopFileNotifications];
			if ([notationController flushAllNoteChanges])
				[notationController closeJournal];
		}
		
		NotationController *oldNotation = notationController;
		notationController = [newNotation retain];
		
		if (oldNotation) {
			[notesTableView abortEditing];
			[prefsController setLastSearchString:[self fieldSearchString] selectedNote:currentNote 
						scrollOffsetForTableView:notesTableView sender:self];
			//if we already had a notation, appController should already be bookmarksController's delegate
			[[prefsController bookmarksController] performSelector:@selector(updateBookmarksUI) withObject:nil afterDelay:0.0];
		}
		[notationController setSortColumn:[notesTableView noteAttributeColumnForIdentifier:[prefsController sortedTableColumnKey]]];
		[notesTableView setDataSource:[notationController notesListDataSource]];
		[notesTableView setLabelsListSource:[notationController labelsListDataSource]];
		[notationController setDelegate:self];
		
		//allow resolution of UUIDs to NoteObjects from saved searches
		[[prefsController bookmarksController] setDataSource:notationController];
		
		//update the list using the new notation and saved settings
		[self restoreListStateUsingPreferences];
		
		//window's undomanager could be referencing actions from the old notation object
		[[window undoManager] removeAllActions];
		[notationController setUndoManager:[window undoManager]];
		
		if ([notationController aliasNeedsUpdating]) {
			[prefsController setAliasDataForDefaultDirectory:[notationController aliasDataForNoteDirectory] sender:self];
		}
		if ([prefsController tableColumnsShowPreview] || [prefsController horizontalLayout]) {
			[self _forceRegeneratePreviewsForTitleColumn];
			[notesTableView setNeedsDisplay:YES];
		}
		[titleBarButton setMenu:[[notationController syncSessionController] syncStatusMenu]];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncSessionsChangedVisibleStatus:) 
													 name:SyncSessionsChangedVisibleStatusNotification 
												   object:[notationController syncSessionController]]; 
		[notationController performSelector:@selector(startSyncServices) withObject:nil afterDelay:0.0];
		
		if ([[notationController notationPrefs] secureTextEntry]) {
			[[SecureTextEntryManager sharedInstance] enableSecureTextEntry];
		} else {
			[[SecureTextEntryManager sharedInstance] disableSecureTextEntry];
		}
		
		[field selectText:nil];
		
		[oldNotation autorelease];
    }
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)sender {
    if (![prefsController quitWhenClosingWindow]) {
        [self bringFocusToControlField:nil];
        return YES;
    }
    
    return NO;
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag {
	return [itemIdentifier isEqualToString:@"DualField"] ? dualFieldItem : nil;
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)theToolbar {
	return [self toolbarDefaultItemIdentifiers:theToolbar];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)theToolbar {
	return [NSArray arrayWithObject:@"DualField"];
}


- (BOOL)validateMenuItem:(NSMenuItem*)menuItem {
	SEL selector = [menuItem action];
	int numberSelected = [notesTableView numberOfSelectedRows];
	NSInteger tag = [menuItem tag];
    
    if ((tag == TextilePreview) || (tag == MarkdownPreview) || (tag == MultiMarkdownPreview)) {
        // Allow only one Preview mode to be selected at every one time
        [menuItem setState:((tag == currentPreviewMode) ? NSOnState : NSOffState)];
        return YES;
    } else if (selector == @selector(printNote:) || 
		selector == @selector(deleteNote:) ||
		selector == @selector(exportNote:) || 
		selector == @selector(tagNote:)) {
		
		return (numberSelected > 0);
		
	} else if (selector == @selector(renameNote:) ||
			   selector == @selector(copyNoteLink:)) {
		
		return (numberSelected == 1);
		
	} else if (selector == @selector(revealNote:)) {
	
		return (numberSelected == 1) && [notationController currentNoteStorageFormat] != SingleDatabaseFormat;
		
	} else if (selector == @selector(openFileInEditor:)) {
		NSString *defApp = [prefsController textEditor];
		if (![[self getTxtAppList] containsObject:defApp]) {
			defApp = @"Default";
			[prefsController setTextEditor:@"Default"];
		}
		if (([defApp isEqualToString:@"Default"])||(![[NSFileManager defaultManager] fileExistsAtPath:[[NSWorkspace sharedWorkspace] fullPathForApplication:defApp]])) {
			
			if (![defApp isEqualToString:@"Default"]) {
				[prefsController setTextEditor:@"Default"];
			}
			CFStringRef cfFormat = (CFStringRef)noteFormat;
			defApp = [(NSString *)LSCopyDefaultRoleHandlerForContentType(cfFormat,kLSRolesEditor) autorelease];
			defApp = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier: defApp];
			defApp = [[NSFileManager defaultManager] displayNameAtPath: defApp];
		}
		if ((!defApp)||([defApp isEqualToString:@"Safari"])) {
			defApp = @"TextEdit";
		}
		[menuItem setTitle:[@"Open Note in " stringByAppendingString:defApp]];
		return (numberSelected == 1) && [notationController currentNoteStorageFormat] != SingleDatabaseFormat;
		
	} else if (selector == @selector(fixFileEncoding:)) {
		
		return (currentNote != nil && storageFormatOfNote(currentNote) == PlainTextFormat && ![currentNote contentsWere7Bit]);
	}
	
	return YES;
}

/*
 - (void)menuNeedsUpdate:(NSMenu *)menu {
 NSLog(@"mama needs update: %@", [menu title]);
 
 NSArray *selectedNotes = [notationController notesAtIndexes:[notesTableView selectedRowIndexes]];
 [selectedNotes setURLsInNotesForMenu:menu];
 }*/

- (void)updateNoteMenus {
	NSMenu *notesMenu = [[[NSApp mainMenu] itemWithTag:NOTES_MENU_ID] submenu];
	
	int menuIndex = [notesMenu indexOfItemWithTarget:self andAction:@selector(deleteNote:)];
	NSMenuItem *deleteItem = nil;
	if (menuIndex > -1 && (deleteItem = [notesMenu itemAtIndex:menuIndex]))	{
		NSString *trailingQualifier = [prefsController confirmNoteDeletion] ? NSLocalizedString(@"...", @"ellipsis character") : @"";
		[deleteItem setTitle:[NSString stringWithFormat:@"%@%@", 
							  NSLocalizedString(@"Delete", nil), trailingQualifier]];
	}
	
	NSMenu *viewMenu = [[[NSApp mainMenu] itemWithTag:VIEW_MENU_ID] submenu];
	
	menuIndex = [viewMenu indexOfItemWithTarget:notesTableView andAction:@selector(toggleNoteBodyPreviews:)];
	NSMenuItem *bodyPreviewItem = nil;
	if (menuIndex > -1 && (bodyPreviewItem = [viewMenu itemAtIndex:menuIndex])) {
		[bodyPreviewItem setTitle: [prefsController tableColumnsShowPreview] ? 
		 NSLocalizedString(@"Hide Note Previews in Title", @"menu item in the View menu to turn off note-body previews in the Title column") : 
		 NSLocalizedString(@"Show Note Previews in Title", @"menu item in the View menu to turn on note-body previews in the Title column")];
	}
	menuIndex = [viewMenu indexOfItemWithTarget:self andAction:@selector(switchViewLayout:)];
	NSMenuItem *switchLayoutItem = nil;
	NSString *switchStr = [prefsController horizontalLayout] ? 
	NSLocalizedString(@"Switch to Vertical Layout", @"title of alternate view layout menu item") : 
	NSLocalizedString(@"Switch to Horizontal Layout", @"title of view layout menu item");	
	
	if (menuIndex > -1 && (switchLayoutItem = [viewMenu itemAtIndex:menuIndex])) {
		[switchLayoutItem setTitle:switchStr];		
	}
	// add to elasticthreads' statusbar menu
	menuIndex = [statBarMenu indexOfItemWithTarget:self andAction:@selector(switchViewLayout:)];
	if (menuIndex>-1) {
		NSMenuItem *anxItem = [statBarMenu itemAtIndex:menuIndex];
		[anxItem setTitle:switchStr];
	}
}

- (void)_forceRegeneratePreviewsForTitleColumn {
	[notationController regeneratePreviewsForColumn:[notesTableView noteAttributeColumnForIdentifier:NoteTitleColumnString]	
								visibleFilteredRows:[notesTableView rowsInRect:[notesTableView visibleRect]] forceUpdate:YES];
}

- (void)_configureDividerForCurrentLayout {
	BOOL horiz = [prefsController horizontalLayout];
	BOOL isCol = [notesSubview isCollapsed];
	if (isCol) {
		[notesSubview expand];
		[splitView setVertical:horiz];
		[splitView setDividerThickness:7.0f];	
        NSSize size = [notesSubview frame].size;        
        [[notesTableView enclosingScrollView] setFrame: NSMakeRect(0, 0, size.width, size.height + 1)];
		[notesSubview collapse];
	}else {
        [splitView setVertical:horiz];
        if (!verticalDividerImg && [splitView divider]) verticalDividerImg = [[splitView divider] retain];
        [splitView setDivider: verticalDividerImg];
        [splitView setDividerThickness: horiz ? 10.0 : 9.0];		
        NSSize size = [notesSubview frame].size;        
        [[notesTableView enclosingScrollView] setFrame: NSMakeRect(0, 0, size.width, size.height + 1)];
	}
	
	[[notesTableView enclosingScrollView] setBorderType:NSNoBorder];
	[[textView enclosingScrollView] setBorderType:NSNoBorder];
    if (horiz) {
        [splitSubview setMinDimension:100.0 andMaxDimension:0.0];
    }
}

- (IBAction)switchViewLayout:(id)sender {	
	int colW = [notesSubview dimension];
	ViewLocationContext ctx = [notesTableView viewingLocation];
	ctx.pivotRowWasEdge = NO;
	[notesTableView noteFirstVisibleRow];	
	
	[prefsController setHorizontalLayout:![prefsController horizontalLayout] sender:self];
	[notationController updateDateStringsIfNecessary];
	[self _configureDividerForCurrentLayout];
	[notationController regenerateAllPreviews];
   // if (![notesSubview isCollapsed]) {
        if ([splitView isVertical]) {
            if (colW < 301) {
                colW = colW + 100;
            }
        }else{
            
            if (colW > 179) {
                colW = colW - 100;
            }
        }	
        [notesSubview setDimension:colW];
   // }
	[splitView adjustSubviews];
		
	[notesTableView setViewingLocation:ctx];
	[notesTableView makeFirstPreviouslyVisibleRowVisibleIfNecessary];
	
	[self updateNoteMenus];
	[self setMaxNoteBodyWidth];
    
	[notesTableView setBackgroundColor:backgrndColor];
	
	
	[notesTableView setNeedsDisplay];
}

- (void)createFromSelection:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
	if (!notationController || ![self addNotesFromPasteboard:pboard]) {
		*error = NSLocalizedString(@"Error: Couldn't create a note from the selection.", @"error message to set during a Service call when adding a note failed");
	}
}



- (IBAction)renameNote:(id)sender {
    //edit the first selected note	
	[notesTableView editRowAtColumnWithIdentifier:NoteTitleColumnString];
}

- (void)deleteAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {

	id retainedDeleteObj = (id)contextInfo;
	
	if (returnCode == NSAlertDefaultReturn) {
		//delete! nil-msgsnd-checking
		
		//ensure that there are no pending edits in the tableview, 
		//lest editing end with the same field editor and a different selected note
		//resulting in the renaming of notes in adjacent rows
		[notesTableView abortEditing];
		
		if ([retainedDeleteObj isKindOfClass:[NSArray class]]) {
			[notationController removeNotes:retainedDeleteObj];
		} else if ([retainedDeleteObj isKindOfClass:[NoteObject class]]) {
			[notationController removeNote:retainedDeleteObj];
		}
		
		if (IsLeopardOrLater && [[alert suppressionButton] state] == NSOnState) {
			[prefsController setConfirmNoteDeletion:NO sender:self];
		}
	}
	[retainedDeleteObj release];
}


- (IBAction)deleteNote:(id)sender {
		
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
	if ([indexes count] > 0) {
		id deleteObj = [indexes count] > 1 ? (id)([notationController notesAtIndexes:indexes]) : (id)([notationController noteObjectAtFilteredIndex:[indexes firstIndex]]);
		
		if ([prefsController confirmNoteDeletion]) {
			[deleteObj retain];
			NSString *warningSingleFormatString = NSLocalizedString(@"Delete the note titled quotemark%@quotemark?", @"alert title when asked to delete a note");
			NSString *warningMultipleFormatString = NSLocalizedString(@"Delete %d notes?", @"alert title when asked to delete multiple notes");
			NSString *warnString = currentNote ? [NSString stringWithFormat:warningSingleFormatString, titleOfNote(currentNote)] : 
			[NSString stringWithFormat:warningMultipleFormatString, [indexes count]];
			
			NSAlert *alert = [NSAlert alertWithMessageText:warnString defaultButton:NSLocalizedString(@"Delete", @"name of delete button")
										   alternateButton:NSLocalizedString(@"Cancel", @"name of cancel button") otherButton:nil 
								 informativeTextWithFormat:NSLocalizedString(@"Press Command-Z to undo this action later.", @"informational delete-this-note? text")];
			if (IsLeopardOrLater) [alert setShowsSuppressionButton:YES];
			
			[alert beginSheetModalForWindow:window modalDelegate:self didEndSelector:@selector(deleteAlertDidEnd:returnCode:contextInfo:) contextInfo:(void*)deleteObj];
		} else {
			//just delete the notes outright			
			[notationController performSelector:[indexes count] > 1 ? @selector(removeNotes:) : @selector(removeNote:) withObject:deleteObj];
		}
	}
}

- (IBAction)copyNoteLink:(id)sender {
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
	
	if ([indexes count] == 1) {
		[[[[[notationController notesAtIndexes:indexes] lastObject] 
		   uniqueNoteLink] absoluteString] copyItemToPasteboard:nil];
	}
}

- (IBAction)exportNote:(id)sender {
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
	
	NSArray *notes = [notationController notesAtIndexes:indexes];
	
	[notationController synchronizeNoteChanges:nil];
	[[ExporterManager sharedManager] exportNotes:notes forWindow:window];
}

- (IBAction)revealNote:(id)sender {
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
	NSString *path = nil;
	
	if ([indexes count] != 1 || !(path = [[notationController noteObjectAtFilteredIndex:[indexes lastIndex]] noteFilePath])) {
		NSBeep();
		return;
	}
	[[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:@""];
}

- (IBAction)printNote:(id)sender {
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
	
	[MultiplePageView printNotes:[notationController notesAtIndexes:indexes] forWindow:window];
}

- (IBAction)tagNote:(id)sender {
	//if single note, add the tag column if necessary and then begin editing
	
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
	
	if ([indexes count] > 1) {
		//Multiple Notes selected, use ElasticThreads' multitagging implementation
		TagEditer = [[[TagEditingManager alloc] init] retain];
		[TagEditer setDel:self];
		@try {			
			cTags = [[[NSArray alloc] initWithArray:[self commonLabels]] retain];
			if ([cTags count]>0) {
				[TagEditer setTF:[cTags componentsJoinedByString:@","]];
			}else {
				[TagEditer setTF:@""];	
			}
			[TagEditer popTP:self];
		}
		@catch (NSException * e) {
			NSLog(@"multitag excep this: %@",[e name]);
		}	
	} else if ([indexes count] == 1) {
		[notesTableView editRowAtColumnWithIdentifier:NoteLabelsColumnString];		
	}
}

- (void)noteImporter:(AlienNoteImporter*)importer importedNotes:(NSArray*)notes {
	
	[notationController addNotes:notes];
}
- (IBAction)importNotes:(id)sender {
	AlienNoteImporter *importer = [[AlienNoteImporter alloc] init];
	[importer importNotesFromDialogAroundWindow:window receptionDelegate:self];
	[importer autorelease];
}

- (void)settingChangedForSelectorString:(NSString*)selectorString {
    if ([selectorString isEqualToString:SEL_STR(setAliasDataForDefaultDirectory:sender:)]) {
		//defaults changed for the database location -- load the new one!
		
		OSStatus err = noErr;
		NotationController *newNotation = nil;
		NSData *newData = [prefsController aliasDataForDefaultDirectory];
		if (newData) {
			if ((newNotation = [[NotationController alloc] initWithAliasData:newData error:&err])) {
				[self setNotationController:newNotation];
				[newNotation release];
				
			} else {
				
				//set alias data back
				NSData *oldData = [notationController aliasDataForNoteDirectory];
				[prefsController setAliasDataForDefaultDirectory:oldData sender:self];
				
				//display alert with err--could not set notation directory 
				NSString *location = [[[NSFileManager defaultManager] pathCopiedFromAliasData:newData] stringByAbbreviatingWithTildeInPath];
				NSString *oldLocation = [[[NSFileManager defaultManager] pathCopiedFromAliasData:oldData] stringByAbbreviatingWithTildeInPath]; 
				NSString *reason = [NSString reasonStringFromCarbonFSError:err];
				NSRunAlertPanel([NSString stringWithFormat:NSLocalizedString(@"Unable to initialize notes database in \n%@ because %@.",nil), location, reason], 
								[NSString stringWithFormat:NSLocalizedString(@"Reverting to current location of %@.",nil), oldLocation], 
								NSLocalizedString(@"OK",nil), NULL, NULL);
			}
		}
    } else if ([selectorString isEqualToString:SEL_STR(setSortedTableColumnKey:reversed:sender:)]) {
		NoteAttributeColumn *oldSortCol = [notationController sortColumn];
		NoteAttributeColumn *newSortCol = [notesTableView noteAttributeColumnForIdentifier:[prefsController sortedTableColumnKey]];
		BOOL changedColumns = oldSortCol != newSortCol;
		
		ViewLocationContext ctx;
		if (changedColumns) {
			ctx = [notesTableView viewingLocation];
			ctx.pivotRowWasEdge = NO;
		}
		
		[notationController setSortColumn:newSortCol];
		
		if (changedColumns) [notesTableView setViewingLocation:ctx];
		
	} else if ([selectorString isEqualToString:SEL_STR(setNoteBodyFont:sender:)]) {
		
		[notationController restyleAllNotes];
		if (currentNote) {
			[self contentsUpdatedForNote:currentNote];
		}
	} else if ([selectorString isEqualToString:SEL_STR(setForegroundTextColor:sender:)]) {
		if (userScheme!=2) {
			[self setUserColorScheme:self];
		}else {
			[self setForegrndColor:[prefsController foregroundTextColor]];
			[self updateColorScheme];
		}
	} else if ([selectorString isEqualToString:SEL_STR(setBackgroundTextColor:sender:)]) {
		if (userScheme!=2) {
			[self setUserColorScheme:self];
		}else {
			[self setBackgrndColor:[prefsController backgroundTextColor]];
			[self updateColorScheme];
		}
		
	} else if ([selectorString isEqualToString:SEL_STR(setTableFontSize:sender:)] || [selectorString isEqualToString:SEL_STR(setTableColumnsShowPreview:sender:)]) {
		
		ResetFontRelatedTableAttributes();
		[notesTableView updateTitleDereferencorState];
		[notationController invalidateAllLabelPreviewImages];
		[self _forceRegeneratePreviewsForTitleColumn];
				
		if ([selectorString isEqualToString:SEL_STR(setTableColumnsShowPreview:sender:)]) [self updateNoteMenus];
		
		[notesTableView performSelector:@selector(reloadData) withObject:nil afterDelay:0];
	} else if ([selectorString isEqualToString:SEL_STR(addTableColumn:sender:)] || [selectorString isEqualToString:SEL_STR(removeTableColumn:sender:)]) {
		
		ResetFontRelatedTableAttributes();
		[self _forceRegeneratePreviewsForTitleColumn];
		[notesTableView performSelector:@selector(reloadDataIfNotEditing) withObject:nil afterDelay:0];
		
	} else if ([selectorString isEqualToString:SEL_STR(setConfirmNoteDeletion:sender:)]) {
		[self updateNoteMenus];
	} else if ([selectorString isEqualToString:SEL_STR(setAutoCompleteSearches:sender:)]) {
		if ([prefsController autoCompleteSearches])
			[notationController updateTitlePrefixConnections];
		
	} else if ([selectorString isEqualToString:SEL_STR(setMaxNoteBodyWidth:sender:)]) {
		[self setMaxNoteBodyWidth];
	
	}
	
}

- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)tableColumn {
    if (tableView == notesTableView) {
		//this sets global prefs options, which ultimately calls back to us
		[notesTableView setStatusForSortedColumn:tableColumn];
    }
}

- (BOOL)tableView:(NSTableView *)tableView shouldShowCellExpansionForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	return ![[tableColumn identifier] isEqualToString:NoteTitleColumnString];
}

- (IBAction)showHelpDocument:(id)sender {
	NSString *path = nil;
	
	switch ([sender tag]) {
		case 1:		//shortcuts
			path = [[NSBundle mainBundle] pathForResource:NSLocalizedString(@"Excruciatingly Useful Shortcuts", nil) ofType:@"nvhelp" inDirectory:nil];
		case 2:		//acknowledgments
			if (!path) path = [[NSBundle mainBundle] pathForResource:@"Acknowledgments" ofType:@"txt" inDirectory:nil];
			[[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:[NSURL fileURLWithPath:path]] withAppBundleIdentifier:@"com.apple.TextEdit" 
											options:NSWorkspaceLaunchDefault additionalEventParamDescriptor:nil launchIdentifiers:NULL];
			break;
		case 3:		//product site
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:NSLocalizedString(@"SiteURL", nil)]];
			break;
		case 4:		//development site
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://notational.net/development"]];
			break;
		default:
			NSBeep();
	}
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames {
	
	if (notationController)
		[notationController openFiles:filenames];
	else
		pathsToOpenOnLaunch = [filenames mutableCopyWithZone:nil];
	
	[NSApp replyToOpenOrPrint:[filenames count] ? NSApplicationDelegateReplySuccess : NSApplicationDelegateReplyFailure];
}

- (void)applicationWillBecomeActive:(NSNotification *)aNotification {
	
	if (IsLeopardOrLater) {
		SpaceSwitchingContext thisSpaceSwitchCtx;
		CurrentContextForWindowNumber([window windowNumber], &thisSpaceSwitchCtx);
		//what if the app is switched-to in another way? then the last-stored spaceSwitchCtx will cause us to return to the wrong app
		//unfortunately this notification occurs only after NV has become the front process, but we can still verify the space number
		
		if (thisSpaceSwitchCtx.userSpace != spaceSwitchCtx.userSpace || 
			thisSpaceSwitchCtx.windowSpace != spaceSwitchCtx.windowSpace) {
			//forget the last space-switch info if it's effectively different from how we're switching into the app now
			bzero(&spaceSwitchCtx, sizeof(SpaceSwitchingContext));
		}
	}
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification {
	[notationController checkJournalExistence];
	
    if ([notationController currentNoteStorageFormat] != SingleDatabaseFormat)
		[notationController performSelector:@selector(synchronizeNotesFromDirectory) withObject:nil afterDelay:0.0];
	[cView setColorIcon:self];
	[notationController updateDateStringsIfNecessary];
}

- (void)applicationWillResignActive:(NSNotification *)aNotification {
	//sync note files when switching apps so user doesn't have to guess when they'll be updated
	[notationController synchronizeNoteChanges:nil];
	[cView setDarkIcon:self];
	[self resetModTimers];
}

- (NSMenu *)applicationDockMenu:(NSApplication *)sender {
	static NSMenu *dockMenu = nil;
	if (!dockMenu) {
		dockMenu = [[NSMenu alloc] initWithTitle:@"NV Dock Menu"];
		[[dockMenu addItemWithTitle:NSLocalizedString(@"Add New Note from Clipboard", @"menu item title in dock menu")
							 action:@selector(paste:) keyEquivalent:@""] setTarget:notesTableView];
	}
	return dockMenu;
}

- (void)cancel:(id)sender {
	//fallback for when other views are hidden/removed during toolbar collapse
	[self cancelOperation:sender];
}

- (void)cancelOperation:(id)sender {
	//simulate a search for nothing
	if ([window isKeyWindow]) {
		
		[field setStringValue:@""];
		typedStringIsCached = NO;
		
		[notationController filterNotesFromString:@""];
		
		[notesTableView deselectAll:sender];
		[self showDualFieldView];
//		[self _expandToolbar];
		
		[field selectText:sender];
		[[field cell] setShowsClearButton:NO];
	}else if ([[TagEditer tagPanel] isKeyWindow]) {  //<--this is for ElasticThreads' multitagging window
		[TagEditer closeTP:self];
		[TagEditer release];
	}
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)aTextView doCommandBySelector:(SEL)command {
	
	if (control == (NSControl*)field) {
		
		//backwards-searching is slow enough as it is, so why not just check this first?
		if (command == @selector(deleteBackward:))
			return NO;
		
		if (command == @selector(moveDown:) || command == @selector(moveUp:) ||
			//catch shift-up/down selection behavior
			command == @selector(moveDownAndModifySelection:) ||
			command == @selector(moveUpAndModifySelection:) ||
			command == @selector(moveToBeginningOfDocumentAndModifySelection:) ||
			command == @selector(moveToEndOfDocumentAndModifySelection:)) {
			
			BOOL singleSelection = ([notesTableView numberOfRows] == 1 && [notesTableView numberOfSelectedRows] == 1);
			[notesTableView keyDown:[window currentEvent]];
			
			unsigned int strLen = [[aTextView string] length];
			if (!singleSelection && [aTextView selectedRange].length != strLen) {
				[aTextView setSelectedRange:NSMakeRange(0, strLen)];
			}
			
			return YES;
		}
		
		if ((command == @selector(insertTab:) || command == @selector(insertTabIgnoringFieldEditor:))) {
			//[self setEmptyViewState:NO];
			if (![[aTextView string] length]) {
				return YES;
			}
			if (!currentNote && [notationController preferredSelectedNoteIndex] != NSNotFound && [prefsController autoCompleteSearches]) {
				//if the current note is deselected and re-searching would auto-complete this search, then allow tab to trigger it
				[self searchForString:[self fieldSearchString]];
				return YES;
			} else if ([textView isHidden]) {
				return YES;
			}
			
			[window makeFirstResponder:textView];
			
			//don't eat the tab!
			return NO;
		}
		if (command == @selector(moveToBeginningOfDocument:)) {
		    [notesTableView selectRowAndScroll:0];
		    return YES;
		}
		if (command == @selector(moveToEndOfDocument:)) {
		    [notesTableView selectRowAndScroll:[notesTableView numberOfRows]-1];
		    return YES;
		}
		
		if (command == @selector(moveToBeginningOfLine:) || command == @selector(moveToLeftEndOfLine:)) {
			[aTextView moveToBeginningOfDocument:nil];
			return YES;
		}
		if (command == @selector(moveToEndOfLine:) || command == @selector(moveToRightEndOfLine:)) {
			[aTextView moveToEndOfDocument:nil];
			return YES;
		}
		
		if (command == @selector(moveToBeginningOfLineAndModifySelection:) || command == @selector(moveToLeftEndOfLineAndModifySelection:)) {
			
			if ([aTextView respondsToSelector:@selector(moveToBeginningOfDocumentAndModifySelection:)]) {
				[(id)aTextView performSelector:@selector(moveToBeginningOfDocumentAndModifySelection:)];
				return YES;
			}
		}
		if (command == @selector(moveToEndOfLineAndModifySelection:) || command == @selector(moveToRightEndOfLineAndModifySelection:)) {
			if ([aTextView respondsToSelector:@selector(moveToEndOfDocumentAndModifySelection:)]) {
				[(id)aTextView performSelector:@selector(moveToEndOfDocumentAndModifySelection:)];
				return YES;
			}
		}
		
		//we should make these two commands work for linking editor as well
		if (command == @selector(deleteToMark:)) {
			[aTextView deleteWordBackward:nil];
			return YES;
		}
		if (command == @selector(noop:)) {
			//control-U is not set to anything by default, so we have to check the event itself for noops
			NSEvent *event = [window currentEvent];
			if ([event modifierFlags] & NSControlKeyMask) {
				if ([event firstCharacterIgnoringModifiers] == 'u') {
					//in 1.1.1 this deleted the entire line, like tcsh. this is more in-line with bash
					[aTextView deleteToBeginningOfLine:nil];
					return YES;
				}
			}
		}
		
	} else if (control == (NSControl*)notesTableView) {
		
		if (command == @selector(insertNewline:)) {
			//hit return in cell
			[window makeFirstResponder:textView];
			return YES;
		}
	} else
		NSLog(@"%@/%@ got %@", [control description], [aTextView description], NSStringFromSelector(command));
	
	return NO;
}

- (void)_setCurrentNote:(NoteObject*)aNote {
	//save range of old current note
	//we really only want to save the insertion point position if it's currently invisible
	//how do we test that?
	BOOL wasAutomatic = NO;
	NSRange currentRange = [textView selectedRangeWasAutomatic:&wasAutomatic];
	if (!wasAutomatic) [currentNote setSelectedRange:currentRange];
	
	//regenerate content cache before switching to new note
	[currentNote updateContentCacheCStringIfNecessary];
	
	
	[currentNote release];
	currentNote = [aNote retain];
}

- (NoteObject*)selectedNoteObject {
	return currentNote;
}

- (NSString*)fieldSearchString {
	NSString *typed = [self typedString];
	if (typed) return typed;
	
	if (!currentNote) return [field stringValue];
	
	return nil;
}

- (NSString*)typedString {
	if (typedStringIsCached)
		return typedString;
	
	return nil;
}

- (void)cacheTypedStringIfNecessary:(NSString*)aString {
	if (!typedStringIsCached) {
		[typedString release];
		typedString = [(aString ? aString : [field stringValue]) copy];
		typedStringIsCached = YES;
	}
}

//from fieldeditor
- (void)controlTextDidChange:(NSNotification *)aNotification {
	
	if ([aNotification object] == field) {
		typedStringIsCached = NO;
		isFilteringFromTyping = YES;
		
		NSTextView *fieldEditor = [[aNotification userInfo] objectForKey:@"NSFieldEditor"];
		NSString *fieldString = [fieldEditor string];
		
		BOOL didFilter = [notationController filterNotesFromString:fieldString];
		
		if ([fieldString length] > 0) {
			[field setSnapbackString:nil];
			

			NSUInteger preferredNoteIndex = [notationController preferredSelectedNoteIndex];
			
			//lastLengthReplaced depends on textView:shouldChangeTextInRange:replacementString: being sent before controlTextDidChange: runs			
			if ([prefsController autoCompleteSearches] && preferredNoteIndex != NSNotFound && ([field lastLengthReplaced] > 0)) {
				
				[notesTableView selectRowAndScroll:preferredNoteIndex];
				
				if (didFilter) { 
					//current selection may be at the same row, but note at that row may have changed
					[self displayContentsForNoteAtIndex:preferredNoteIndex];
				}
				
				NSAssert(currentNote != nil, @"currentNote must not--cannot--be nil!");
				
				NSRange typingRange = [fieldEditor selectedRange];
				
				//fill in the remaining characters of the title and select
				if ([field lastLengthReplaced] > 0 && typingRange.location < [titleOfNote(currentNote) length]) {
					
					[self cacheTypedStringIfNecessary:fieldString];
					
					NSAssert([fieldString isEqualToString:[fieldEditor string]], @"I don't think it makes sense for fieldString to change");
					
					NSString *remainingTitle = [titleOfNote(currentNote) substringFromIndex:typingRange.location];
					typingRange.length = [fieldString length] - typingRange.location;
					typingRange.length = MAX(typingRange.length, 0U);
					
					[fieldEditor replaceCharactersInRange:typingRange withString:remainingTitle];
					typingRange.length = [remainingTitle length];
					[fieldEditor setSelectedRange:typingRange];
				}
				
			} else {
				//auto-complete is off, search string doesn't prefix any title, or part of the search string is being removed
				goto selectNothing;
			}
		} else {
			//selecting nothing; nothing typed
		selectNothing:
			isFilteringFromTyping = NO;
			[notesTableView deselectAll:nil];
			
			//reloadData could have already de-selected us, and hence this notification would not be sent from -deselectAll:
			[self processChangedSelectionForTable:notesTableView];
		}
		
		isFilteringFromTyping = NO;
	}
}

- (void)tableViewSelectionIsChanging:(NSNotification *)aNotification {
	
	BOOL allowMultipleSelection = NO;
	NSEvent *event = [window currentEvent];
    
	NSEventType type = [event type];
	//do not allow drag-selections unless a modifier is pressed
	if (type == NSLeftMouseDragged || type == NSLeftMouseDown) {
		unsigned flags = [event modifierFlags];
		if ((flags & NSShiftKeyMask) || (flags & NSCommandKeyMask)) {
			allowMultipleSelection = YES;
		}
	}
	
	if (allowMultipleSelection != [notesTableView allowsMultipleSelection]) {
		//we may need to hack some hidden NSTableView instance variables to improve mid-drag flags-changing
		//NSLog(@"set allows mult: %d", allowMultipleSelection);
		
		[notesTableView setAllowsMultipleSelection:allowMultipleSelection];
		
		//we need this because dragging a selection back to the same note will nto trigger a selectionDidChange notification
		[self performSelector:@selector(setTableAllowsMultipleSelection) withObject:nil afterDelay:0];
	}
    
	if ([window firstResponder] != notesTableView) {
		//occasionally changing multiple selection ability in-between selecting multiple items causes total deselection
		[window makeFirstResponder:notesTableView];
	}
	
	[self processChangedSelectionForTable:[aNotification object]];
}

- (void)setTableAllowsMultipleSelection {
	[notesTableView setAllowsMultipleSelection:YES];
	//NSLog(@"allow mult: %d", [notesTableView allowsMultipleSelection]);
	//[textView setNeedsDisplay:YES];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
	NSEventType type = [[window currentEvent] type];
	if (type != NSKeyDown && type != NSKeyUp) {
		[self performSelector:@selector(setTableAllowsMultipleSelection) withObject:nil afterDelay:0];
	}
	
	[self processChangedSelectionForTable:[aNotification object]];
}

- (void)processChangedSelectionForTable:(NSTableView*)table {
	int selectedRow = [table selectedRow];
	int numberSelected = [table numberOfSelectedRows];
	
	NSTextView *fieldEditor = (NSTextView*)[field currentEditor];
	
	if (table == (NSTableView*)notesTableView) {
		
		if (selectedRow > -1 && numberSelected == 1) {
			//if it is uncached, cache the typed string only if we are selecting a note
			
			[self cacheTypedStringIfNecessary:[fieldEditor string]];
			
			//add snapback-button here?
			if (!isFilteringFromTyping && !isCreatingANote)
				[field setSnapbackString:typedString];
			
			if ([self displayContentsForNoteAtIndex:selectedRow]) {
				
				[[field cell] setShowsClearButton:YES];
				
				//there doesn't seem to be any situation in which a note will be selected
				//while the user is typing and auto-completion is disabled, so should be OK

				if (!isFilteringFromTyping) {
				//	if ([toolbar isVisible]) {
                    if ([self dualFieldIsVisible]) {
						if (fieldEditor) {
							//the field editor has focus--select text, too
							[fieldEditor setString:titleOfNote(currentNote)];
							unsigned int strLen = [titleOfNote(currentNote) length];
							if (strLen != [fieldEditor selectedRange].length)
								[fieldEditor setSelectedRange:NSMakeRange(0, strLen)];
						} else {
							//this could be faster
							[field setStringValue:titleOfNote(currentNote)];
						}
					} else {
						[window setTitle:titleOfNote(currentNote)];
					}
				}
			}
			return;
		}
	} else { //tags
#if 0
		if (numberSelected == 1)
			[notationController filterNotesFromLabelAtIndex:selectedRow];
		else if (numberSelected > 1)
			[notationController filterNotesFromLabelIndexSet:[table selectedRowIndexes]];		
#endif
	}
	
	if (!isFilteringFromTyping) {
		if (currentNote) {
			//selected nothing and something is currently selected
			
			[self _setCurrentNote:nil];
			[field setShowsDocumentIcon:NO];
			
			if (typedStringIsCached) {
				//restore the un-selected state, but only if something had been first selected to cause that state to be saved
				[field setStringValue:typedString];
			}
			[textView setString:@""];
		}
		//[self _expandToolbar];
		[self showDualFieldView];
        [[window contentView] setNeedsDisplay:YES];
		if (!currentNote) {
			if (selectedRow == -1 && (!fieldEditor || [window firstResponder] != fieldEditor)) {
				//don't select the field if we're already there
				[window makeFirstResponder:field];
				fieldEditor = (NSTextView*)[field currentEditor];
			}
			if (fieldEditor && [fieldEditor selectedRange].length)
				[fieldEditor setSelectedRange:NSMakeRange([[fieldEditor string] length], 0)];
			
			
			//remove snapback-button from dual field here?
			[field setSnapbackString:nil];
			
			if (!numberSelected && savedSelectedNotes) {
				//savedSelectedNotes needs to be empty after de-selecting all notes, 
				//to ensure that any delayed list-resorting does not re-select savedSelectedNotes

				[savedSelectedNotes release];
				savedSelectedNotes = nil;
			}
		}
	}
	[self setEmptyViewState:currentNote == nil];
	[field setShowsDocumentIcon:currentNote != nil];
	[[field cell] setShowsClearButton:currentNote != nil || [[field stringValue] length]];
}

- (void)setEmptyViewState:(BOOL)state {
    //return;
	
	[self postTextUpdate];
    [self updateWordCount];
	//int numberSelected = [notesTableView numberOfSelectedRows];
	BOOL enable = /*numberSelected != 1;*/ state;
	[textView setHidden:enable];
	[editorStatusView setHidden:!enable];
	
	if (enable) {
		[editorStatusView setLabelStatus:[notesTableView numberOfSelectedRows]];
	}
}

- (BOOL)displayContentsForNoteAtIndex:(int)noteIndex {
	NoteObject *note = [notationController noteObjectAtFilteredIndex:noteIndex];
	if (note != currentNote) {
		[self setEmptyViewState:NO];
		[field setShowsDocumentIcon:YES];
		
		//actually load the new note
		[self _setCurrentNote:note];
		
		NSRange firstFoundTermRange = NSMakeRange(NSNotFound,0);
		NSRange noteSelectionRange = [currentNote lastSelectedRange];
		
		if (noteSelectionRange.location == NSNotFound || 
			NSMaxRange(noteSelectionRange) > [[note contentString] length]) {
			//revert to the top; selection is invalid
			noteSelectionRange = NSMakeRange(0,0);
		}
		
		//[textView beginInhibitingUpdates];
		//scroll to the top first in the old note body if necessary, because the text will (or really ought to) have already been laid-out
		//if ([textView visibleRect].origin.y > 0)
		//	[textView scrollRangeToVisible:NSMakeRange(0,0)];
		
		if (![textView didRenderFully]) { 
			//NSLog(@"redisplay because last note was too long to finish before we switched");
			[textView setNeedsDisplayInRect:[textView visibleRect] avoidAdditionalLayout:YES];
		}
		
		//restore string
		[[textView textStorage] setAttributedString:[note contentString]];
		[self postTextUpdate];
		[self updateWordCount];
		//[textView setAutomaticallySelectedRange:NSMakeRange(0,0)];
		
		//highlight terms--delay this, too
		if ((unsigned)noteIndex != [notationController preferredSelectedNoteIndex])
			firstFoundTermRange = [textView highlightTermsTemporarilyReturningFirstRange:typedString avoidHighlight:
								   ![prefsController highlightSearchTerms]];
		
		//if there was nothing selected, select the first found range
		if (!noteSelectionRange.length && firstFoundTermRange.location != NSNotFound)
			noteSelectionRange = firstFoundTermRange;
		
		//select and scroll
		[textView setAutomaticallySelectedRange:noteSelectionRange];
		[textView scrollRangeToVisible:noteSelectionRange];
		
		//NSString *words = noteIndex != [notationController preferredSelectedNoteIndex] ? typedString : nil;
		//[textView setFutureSelectionRange:noteSelectionRange highlightingWords:words];
		
		return YES;
	}
	
	return NO;
}

//from linkingeditor
- (void)textDidChange:(NSNotification *)aNotification {
	id textObject = [aNotification object];
	
	if (textObject == textView) {
		[currentNote setContentString:[textView textStorage]];
		[self postTextUpdate];
		[self updateWordCount];
	}
}

- (void)textDidBeginEditing:(NSNotification *)aNotification {
	if ([aNotification object] == textView) {
		[textView removeHighlightedTerms];
	    [self createNoteIfNecessary];
	}
}

- (void)textDidEndEditing:(NSNotification *)aNotification {
	if ([aNotification object] == textView) {
		//save last selection range for currentNote?
		//[currentNote setSelectedRange:[textView selectedRange]];
		
		//we need to set this here as we could return to searching before changing notes
		//and the next time the note would change would be when searching had triggered it
		//which would be too late
		[currentNote updateContentCacheCStringIfNecessary];
	}
}

- (NSMenu *)textView:(NSTextView *)view menu:(NSMenu *)menu forEvent:(NSEvent *)event atIndex:(NSUInteger)charIndex {
	NSInteger idx;
	if ((idx = [menu indexOfItemWithTarget:nil andAction:@selector(_removeLinkFromMenu:)]) > -1)
		[menu removeItemAtIndex:idx];
	if ((idx = [menu indexOfItemWithTarget:nil andAction:@selector(orderFrontLinkPanel:)]) > -1)
		[menu removeItemAtIndex:idx];
	return menu;
}

- (NSArray *)textView:(NSTextView *)aTextView completions:(NSArray *)words 
  forPartialWordRange:(NSRange)charRange indexOfSelectedItem:(NSInteger *)anIndex {
	
	NSArray *noteTitles = [notationController noteTitlesPrefixedByString:[[aTextView string] substringWithRange:charRange]
													 indexOfSelectedItem:anIndex];
	return noteTitles;
}


- (IBAction)fieldAction:(id)sender {
	
	[self createNoteIfNecessary];
	[window makeFirstResponder:textView];
	
}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)sender {
	
	if ([sender firstResponder] == textView) {
		if ((floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_3) && currentNote) {
			NSLog(@"windowWillReturnUndoManager should not be called when textView is first responder on Tiger or higher");
		}
		
		NSUndoManager *undoMan = [self undoManagerForTextView:textView];
		if (undoMan) 
			return undoMan;
	}
	return windowUndoManager;
}

- (NSUndoManager *)undoManagerForTextView:(NSTextView *)aTextView {
    if (aTextView == textView && currentNote)
		return [currentNote undoManager];
    
    return nil;
}

- (NoteObject*)createNoteIfNecessary {
    
    if (!currentNote) {
		//this assertion not yet valid until labels list changes notes list
		NSAssert([notesTableView numberOfSelectedRows] != 1, @"cannot create a note when one is already selected");
		
		[textView setTypingAttributes:[prefsController noteBodyAttributes]];
		[textView setFont:[prefsController noteBodyFont]];
		
		isCreatingANote = YES;
		NSString *title = [[field stringValue] length] ? [field stringValue] : NSLocalizedString(@"Untitled Note", @"Title of a nameless note");
		NSAttributedString *attributedContents = [textView textStorage] ? [textView textStorage] : [[[NSAttributedString alloc] initWithString:@"" attributes:
																									 [prefsController noteBodyAttributes]] autorelease];		
		NoteObject *note = [[[NoteObject alloc] initWithNoteBody:attributedContents title:title delegate:notationController
														  format:[notationController currentNoteStorageFormat] labels:nil] autorelease];
		[notationController addNewNote:note];
		
		isCreatingANote = NO;
		return note;
    }
    
    return currentNote;
}

- (void)restoreListStateUsingPreferences {
	//to be invoked after loading a notationcontroller
	
	NSString *searchString = [prefsController lastSearchString];
	if ([searchString length])
		[self searchForString:searchString];
	else
		[notationController refilterNotes];
		
	CFUUIDBytes bytes = [prefsController UUIDBytesOfLastSelectedNote];
	NSUInteger idx = [self revealNote:[notationController noteForUUIDBytes:&bytes] options:NVDoNotChangeScrollPosition];
	//scroll using saved scrollbar position
	[notesTableView scrollRowToVisible:NSNotFound == idx ? 0 : idx withVerticalOffset:[prefsController scrollOffsetOfLastSelectedNote]];
}

- (NSUInteger)revealNote:(NoteObject*)note options:(NSUInteger)opts {
	if (note) {
		NSUInteger selectedNoteIndex = [notationController indexInFilteredListForNoteIdenticalTo:note];
		
		if (selectedNoteIndex == NSNotFound) {
			NSLog(@"Note was not visible--showing all notes and trying again");
			[self cancelOperation:nil];
			
			selectedNoteIndex = [notationController indexInFilteredListForNoteIdenticalTo:note];
		}
		
		if (selectedNoteIndex != NSNotFound) {
			if (opts & NVDoNotChangeScrollPosition) { //select the note only
				[notesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedNoteIndex] byExtendingSelection:NO];
			} else {
				[notesTableView selectRowAndScroll:selectedNoteIndex];
			}
		}
		
		if (opts & NVEditNoteToReveal) {
			[window makeFirstResponder:textView];
		}
		if (opts & NVOrderFrontWindow) {
			//for external url-handling, often the app will already have been brought to the foreground
			if (![NSApp isActive]) {
				if (IsLeopardOrLater)
					CurrentContextForWindowNumber([window windowNumber], &spaceSwitchCtx);
				[NSApp activateIgnoringOtherApps:YES];
			}
			if (![window isKeyWindow])
				[window makeKeyAndOrderFront:nil];
		}
		return selectedNoteIndex;
	} else {
		[notesTableView deselectAll:self];
		return NSNotFound;
	}
}

- (void)notation:(NotationController*)notation revealNote:(NoteObject*)note options:(NSUInteger)opts {
	[self revealNote:note options:opts];
}

- (void)notation:(NotationController*)notation revealNotes:(NSArray*)notes {
	
	NSIndexSet *indexes = [notation indexesOfNotes:notes];
	if ([notes count] != [indexes count]) {
		[self cancelOperation:nil];
		
		indexes = [notation indexesOfNotes:notes];
	}
	if ([indexes count]) {
		[notesTableView selectRowIndexes:indexes byExtendingSelection:NO];
		[notesTableView scrollRowToVisible:[indexes firstIndex]];
	}
}

- (void)searchForString:(NSString*)string {
	
	if (string) {
		
		//problem: this won't work when the toolbar (and consequently the searchfield) is hidden;
		//and neither will the controlTextDidChange implementation
		//[self _expandToolbar];
		[self showDualFieldView];
        [[window contentView] setNeedsDisplay:YES];
		[window makeFirstResponder:field];
		NSTextView* fieldEditor = (NSTextView*)[field currentEditor];
		NSRange fullRange = NSMakeRange(0, [[fieldEditor string] length]);
		if ([fieldEditor shouldChangeTextInRange:fullRange replacementString:string]) {
			[fieldEditor replaceCharactersInRange:fullRange withString:string];
			[fieldEditor didChangeText];
		} else {
			NSLog(@"I shouldn't change text?");
		}
	}
}

- (void)bookmarksController:(BookmarksController*)controller restoreNoteBookmark:(NoteBookmark*)aBookmark inBackground:(BOOL)inBG {
	if (aBookmark) {
		[self searchForString:[aBookmark searchString]];
		[self revealNote:[aBookmark noteObject] options:!inBG ? NVOrderFrontWindow : 0];
	}
}



- (void)splitView:(RBSplitView*)sender wasResizedFrom:(CGFloat)oldDimension to:(CGFloat)newDimension {
	if (sender == splitView) {
		//if ([prefsController managesTextWidthInWindow]) {
		//	if ([splitSubview frame].size.width<600) {
		//		[textView setTextContainerInset:normalInset];
		//	}else {
				[self setMaxNoteBodyWidth];
		//	}
		//}
		[sender adjustSubviewsExcepting:notesSubview];
	}
}

- (BOOL)splitView:(RBSplitView*)sender shouldHandleEvent:(NSEvent*)theEvent inDivider:(NSUInteger)divider 
	  betweenView:(RBSplitSubview*)leading andView:(RBSplitSubview*)trailing {
	//if upon the first mousedown, the top selected index is visible, snap to it when resizing
	[notesTableView noteFirstVisibleRow];
	if ([theEvent clickCount]>1) {
		[self toggleCollapse:sender];
		/*BOOL wasVisible = YES;
		if ([[window contentView] isInFullScreenMode]) {
			wasVisible = [[field superview] isHidden];
		}else {
			wasVisible = [toolbar isVisible];
		}

		if (wasVisible) {
			//pseudo-collapsing splitviews; the built-in collapsing makes it difficult to handle dragging to hide toolbar
			
			[self hideDualFieldView];			
			[splitView setDividerThickness: 7.0];
			[notesSubview collapse]; // setDimension:0.0];
			[splitView adjustSubviews];
			//[self _collapseToolbar];
			[window makeFirstResponder:textView];
		} else {
			[notesSubview expand];
			[self showDualFieldView];
			//[self _expandToolbar];
		}
		if (!wasVisible && [window firstResponder] == window) {
			[field selectText:sender];
		}*/
		
		return NO;
	}
	return YES;
}

//mail.app-like resizing behavior wrt item selections
- (void)willAdjustSubviews:(RBSplitView*)sender {
	//problem: don't do this if the horizontal splitview is being resized; in horizontal layout, only do this when resizing the window
	if (![prefsController horizontalLayout]) {
		[notesTableView makeFirstPreviouslyVisibleRowVisibleIfNecessary];
	}
}

- (NSSize)windowWillResize:(NSWindow *)window toSize:(NSSize)proposedFrameSize {
	if ([prefsController horizontalLayout]) {
		[notesTableView makeFirstPreviouslyVisibleRowVisibleIfNecessary];
	}
	return proposedFrameSize;
}

- (void)_expandToolbar {
	if (![toolbar isVisible]) {
		[window setTitle:@"Notation"];
		if (currentNote)
			[field setStringValue:titleOfNote(currentNote)];
		[toolbar setVisible:YES];
		//[window toggleToolbarShown:nil];
	//	if (![splitView isDragging])
			//[[splitView subviewAtPosition:0] setDimension:100.0];
		[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"ToolbarHidden"];
	}
	//if ([[splitView subviewAtPosition:0] isCollapsed])
	//	[[splitView subviewAtPosition:0] expand];

}

- (void)_collapseToolbar {
	if ([toolbar isVisible]) {
		if (currentNote)
			[window setTitle:titleOfNote(currentNote)];
//		[window toggleToolbarShown:nil];
		
		[toolbar setVisible:NO];
		[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"ToolbarHidden"];
	}
}

- (BOOL)splitView:(RBSplitView*)sender shouldResizeWindowForDivider:(NSUInteger)divider 
	  betweenView:(RBSplitSubview*)leading andView:(RBSplitSubview*)trailing willGrow:(BOOL)grow {

	if ([sender isDragging]) {
		BOOL toolbarVisible  = [self dualFieldIsVisible];
		/* if ([mainView isInFullScreenMode]) {
		toolbarVisible = [[field superview] isHidden];
		 }else {
		 toolbarVisible  = [toolbar isVisible];
		 }*/
		//BOOL toolbarVisible = [toolbar isVisible];
		NSPoint mouse = [sender convertPoint:[[window currentEvent] locationInWindow] fromView:nil];
		
		if ((toolbarVisible && !grow && mouse.y < -28.0 && ![leading canShrink]) || 
			(!toolbarVisible && grow)) {
			BOOL wasVisible = toolbarVisible;
			if (toolbarVisible) {
				[self hideDualFieldView];
				//[self _collapseToolbar];
			} else {
				[self showDualFieldView];
//				[self _expandToolbar];
			}
			
            [[window contentView] setNeedsDisplay:YES];
			if (!wasVisible && [window firstResponder] == window) {
				//if dualfield had first responder previously, it might need to be restored 
				//if it had been removed from the view hierarchy due to hiding the toolbar
				[field selectText:sender];
			}
		}
		
		//if (([[window contentView] isInFullScreenMode])&&([splitView isVertical])) {
		//	if ([splitSubview frame].size.width<600) {
		//		[textView setTextContainerInset:normalInset];
		//	}else {
		//		[self setTextMarginsInFullScreen];
		//	}
		//}else {
			//if (([splitView isVertical])&&([prefsController managesTextWidthInWindow])) {
			//	if ([splitSubview frame].size.width<600) {
			//		[textView setTextContainerInset:normalInset];
			//	}else {
					[self setMaxNoteBodyWidth];
			//	}
			//}
		//}
	}

	return NO;
}

- (void)tableViewColumnDidResize:(NSNotification *)aNotification {
	NoteAttributeColumn *col = [[aNotification userInfo] objectForKey:@"NSTableColumn"];
	if ([[col identifier] isEqualToString:NoteTitleColumnString]) {
		[notationController regeneratePreviewsForColumn:col visibleFilteredRows:[notesTableView rowsInRect:[notesTableView visibleRect]] forceUpdate:NO];
		
	 	[NSObject cancelPreviousPerformRequestsWithTarget:notesTableView selector:@selector(reloadDataIfNotEditing) object:nil];
		[notesTableView performSelector:@selector(reloadDataIfNotEditing) withObject:nil afterDelay:0.0];
	}
}

- (NSRect)splitView:(RBSplitView*)sender willDrawDividerInRect:(NSRect)dividerRect betweenView:(RBSplitSubview*)leading 
			andView:(RBSplitSubview*)trailing withProposedRect:(NSRect)imageRect {
	
	[dividerShader drawDividerInRect:dividerRect withDimpleRect:imageRect blendVertically:![prefsController horizontalLayout]];
	
	return NSZeroRect;
}

- (NSUInteger)splitView:(RBSplitView*)sender dividerForPoint:(NSPoint)point inSubview:(RBSplitSubview*)subview {
	//if ([(AugmentedScrollView*)[notesTableView enclosingScrollView] shouldDragWithPoint:point sender:sender]) {
	//	return 0;       // [firstSplit position], which we assume to be zero
	//}
	return NSNotFound;
}

- (BOOL)splitView:(RBSplitView*)sender canCollapse:(RBSplitSubview*)subview {
	if ([sender subviewAtPosition:0] == subview) {
		return currentNote != nil;
		//this is the list view; let it collapse in horizontal layout when a note is being edited
		//return [prefsController horizontalLayout] && currentNote != nil;
	}
	return NO;
}


//the notationcontroller must call notationListShouldChange: first 
//if it's going to do something that could mess up the tableview's field eidtor
- (BOOL)notationListShouldChange:(NotationController*)someNotation {
	
	if (someNotation == notationController) {
		if ([notesTableView currentEditor])
			return NO;
	}
	
	return YES;
}

- (void)notationListMightChange:(NotationController*)someNotation {
	
	if (!isFilteringFromTyping) {
		if (someNotation == notationController) {
			//deal with one notation at a time
			
			if ([notesTableView numberOfSelectedRows] > 0) {
				NSIndexSet *indexSet = [notesTableView selectedRowIndexes];
					
				[savedSelectedNotes release];
				savedSelectedNotes = [[someNotation notesAtIndexes:indexSet] retain];
			}
			
			listUpdateViewCtx = [notesTableView viewingLocation];
		}
	}
}

- (void)notationListDidChange:(NotationController*)someNotation {
	
	if (someNotation == notationController) {
		//deal with one notation at a time

		[notesTableView reloadData];
		//[notesTableView noteNumberOfRowsChanged];
		
		if (!isFilteringFromTyping) {
			if (savedSelectedNotes) {
				NSIndexSet *indexes = [someNotation indexesOfNotes:savedSelectedNotes];
				[savedSelectedNotes release];
				savedSelectedNotes = nil;
				
				[notesTableView selectRowIndexes:indexes byExtendingSelection:NO];
			}
			
			[notesTableView setViewingLocation:listUpdateViewCtx];
		}
	}
}

- (void)titleUpdatedForNote:(NoteObject*)aNoteObject {
    if (aNoteObject == currentNote) {
	//	if ([toolbar isVisible]) {
        if ([self dualFieldIsVisible]) {
			[field setStringValue:titleOfNote(currentNote)];
		} else {
			[window setTitle:titleOfNote(currentNote)];
		}
    }
	[[prefsController bookmarksController] updateBookmarksUI];
}

- (void)contentsUpdatedForNote:(NoteObject*)aNoteObject {
	if (aNoteObject == currentNote) {
		
		[[textView textStorage] setAttributedString:[aNoteObject contentString]];
		[self postTextUpdate];
		[self updateWordCount];
	}
}

- (void)rowShouldUpdate:(NSInteger)affectedRow {
	NSRect rowRect = [notesTableView rectOfRow:affectedRow];
	NSRect visibleRect = [notesTableView visibleRect];
	
	if (NSContainsRect(visibleRect, rowRect) || NSIntersectsRect(visibleRect, rowRect)) {
		[notesTableView setNeedsDisplayInRect:rowRect];
	}
}

- (void)syncSessionsChangedVisibleStatus:(NSNotification*)aNotification {
	SyncSessionController *syncSessionController = [aNotification object];
	if ([syncSessionController hasErrors]) {
		[titleBarButton setStatusIconType:AlertIcon];
	} else if ([syncSessionController hasRunningSessions]) {
		[titleBarButton setStatusIconType:SynchronizingIcon];
	} else {
		[titleBarButton setStatusIconType: [[NSUserDefaults standardUserDefaults] boolForKey:@"ShowSyncMenu"] ? DownArrowIcon : NoIcon ];
	}	
}


- (IBAction)fixFileEncoding:(id)sender {
	if (currentNote) {
		[notationController synchronizeNoteChanges:nil];
		
		[[EncodingsManager sharedManager] showPanelForNote:currentNote];
	}
}

- (void)windowWillClose:(NSNotification *)aNotification {
    if ([prefsController quitWhenClosingWindow])
		[NSApp terminate:nil];
}

- (void)_finishSyncWait {
	//always post to next runloop to ensure that a sleep-delay response invocation, if one is also queued, runs before this one
	//if the app quits before the sleep-delay response posts, then obviously sleep will be delayed by quite a bit
	[self performSelector:@selector(syncWaitQuit:) withObject:nil afterDelay:0];
}

- (IBAction)syncWaitQuit:(id)sender {
	//need this variable to allow overriding the wait
	waitedForUncommittedChanges = YES;
	NSString *errMsg = [[notationController syncSessionController] changeCommittingErrorMessage];
	if ([errMsg length]) NSRunAlertPanel(NSLocalizedString(@"Changes could not be uploaded.", nil), errMsg, @"Quit", nil, nil);
	
	[NSApp terminate:nil];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
	//if a sync session is still running, then wait for it to finish before sending terminatereply
	//otherwise, if there are unsynced notes to send, then push them right now and wait until session is no longer running	
	//use waitForUncommitedChangesWithTarget:selector: and provide a callback to send NSTerminateNow
	
	InvocationRecorder *invRecorder = [InvocationRecorder invocationRecorder];
	[[invRecorder prepareWithInvocationTarget:self] _finishSyncWait];
	
	if (!waitedForUncommittedChanges &&
		[[notationController syncSessionController] waitForUncommitedChangesWithInvocation:[invRecorder invocation]]) {
		
		[[NSApp windows] makeObjectsPerformSelector:@selector(orderOut:) withObject:nil];
		[syncWaitPanel center];
		[syncWaitPanel makeKeyAndOrderFront:nil];
		[syncWaitSpinner startAnimation:nil];
		//use NSTerminateCancel instead of NSTerminateLater because we need the runloop functioning in order to receive start/stop sync notifications
		return NSTerminateCancel;
	}
	return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {	
	if (notationController) {
		//only save the state if the notation instance has actually loaded; i.e., don't save last-selected-note if we quit from a PW dialog
		BOOL wasAutomatic = NO;
		NSRange currentRange = [textView selectedRangeWasAutomatic:&wasAutomatic];
		if (!wasAutomatic) [currentNote setSelectedRange:currentRange];
		
		[currentNote updateContentCacheCStringIfNecessary];
		
		[prefsController setLastSearchString:[self fieldSearchString] selectedNote:currentNote 
					scrollOffsetForTableView:notesTableView sender:self];
		
		[prefsController saveCurrentBookmarksFromSender:self];
	}
	
	[[NSApp windows] makeObjectsPerformSelector:@selector(close)];
	[notationController stopFileNotifications];
	
	//wait for syncing to finish, showing a progress bar
	
    if ([notationController flushAllNoteChanges])
		[notationController closeJournal];
	else
		NSLog(@"Could not flush database, so not removing journal");
	
    [prefsController synchronize];
}

- (void)dealloc {
    [mainView release];
    [splitView release];
    [splitSubview release];
    [notesSubview release];
    [previewController release];
	[windowUndoManager release];
	[dividerShader release];
	[[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
	[self postTextUpdate];
	
	[super dealloc];
}

- (IBAction)showPreferencesWindow:(id)sender {
	[prefsWindowController showWindow:sender];
}

- (IBAction)toggleNVActivation:(id)sender {
	
	if ([NSApp isActive] && [window isMainWindow]) {
		
		SpaceSwitchingContext laterSpaceSwitchCtx;
		if (IsLeopardOrLater)
			CurrentContextForWindowNumber([window windowNumber], &laterSpaceSwitchCtx);
		
		if (!IsLeopardOrLater || !CompareContextsAndSwitch(&spaceSwitchCtx, &laterSpaceSwitchCtx)) {
			//hide only if we didn't need to or weren't able to switch spaces
			[NSApp hide:sender];
		}
		//clear the space-switch context that we just looked at, to ensure it's not reused inadvertently
		bzero(&spaceSwitchCtx, sizeof(SpaceSwitchingContext));
		return;
	}
	[self bringFocusToControlField:sender];
}

- (IBAction)bringFocusToControlField:(id)sender {
	//For ElasticThreads' fullscreen mode use this if/else otherwise uncomment the expand toolbar
	if ([notesSubview isCollapsed]) {
		[self toggleCollapse:self];
	}else {
		[self showDualFieldView];
        [[window contentView] setNeedsDisplay:YES];
	}
	//[self _expandToolbar];

	[field selectText:sender];
	
	if (![NSApp isActive]) {
		CurrentContextForWindowNumber([window windowNumber], &spaceSwitchCtx);
		[NSApp activateIgnoringOtherApps:YES];
	}
	if (![window isMainWindow]) [window makeKeyAndOrderFront:sender];
	
	[self setEmptyViewState:currentNote == nil];
}

- (NSWindow*)window {
	return window;
}

#pragma mark ElasticThreads methods
/*
- (RBSplitView *)sView{
	return splitView;
}*/

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex {

	NSUInteger rowInt =  rowIndex;
	if (rowInt==[notationController indexInFilteredListForNoteIdenticalTo:currentNote]) {
		[aCell setTextColor:[NSColor whiteColor]];
	}else {		
		[aCell setTextColor:foregrndColor];
	}
}

/*
- (void)focusOnCtrlFld:(id)sender {
	//[self _expandToolbar];
	//[self showDualFieldView];
	if ([notesSubview isCollapsed]) {
		[self toggleCollapse:self];		
	}
	[field selectText:sender];
	
	if (![NSApp isActive]) [NSApp activateIgnoringOtherApps:YES];
	if ((![window isMainWindow])&&(![[window contentView] isInFullScreenMode])) {
		[window makeKeyAndOrderFront:sender];
	}
	[self setEmptyViewState:currentNote == nil];
}*/

- (NSMenu *)statBarMenu{
	return statBarMenu;
}

- (BOOL)toggleAttachedWindow:(id)sender
{
	if (![window isKeyWindow]) {
	//	[self focusOnCtrlFld:self];
		[NSApp activateIgnoringOtherApps:YES];
	}else {
		[NSApp hide:sender];
	//	[statusItem popUpStatusItemMenu:statBarMenu];
	//	return YES;
	}
	return NO;
}

- (BOOL)toggleAttachedMenu:(id)sender
{
	/*if (![window isKeyWindow]) {
	 [self focusOnCtrlFld:self];
	 }*/	
	[statusItem popUpStatusItemMenu:statBarMenu];
	
	return YES;
}


- (NSArray *)commonLabels{
	NSCharacterSet *tagSeparators = [NSCharacterSet  characterSetWithCharactersInString:@", "];
	NSArray *retArray = [[[NSArray alloc]initWithObjects:@"",nil]retain];
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
	NSString *existTags;
	NSSet *tagsForNote;
	NSEnumerator *noteEnum = [[[notationController notesAtIndexes:indexes] objectEnumerator] retain];
	NoteObject *aNote;	
	NSMutableSet *commonTags = [[[NSMutableSet alloc]initWithCapacity:1] retain];
	NSArray *tagArray;
	aNote = [noteEnum nextObject];
	existTags = labelsOfNote(aNote);
	if (![existTags isEqualToString:@""]) {
		tagArray = [existTags componentsSeparatedByCharactersInSet:tagSeparators];
		[commonTags addObjectsFromArray:tagArray];
		
		while (((aNote = [noteEnum nextObject]))&&([commonTags count]>0)) {
			existTags = labelsOfNote(aNote);
			if (![existTags isEqualToString:@""]) {
				tagArray = [existTags componentsSeparatedByCharactersInSet:tagSeparators];
				@try {
					if ([tagArray count]>0) {
						tagsForNote =[NSSet setWithArray:tagArray];
						if ([commonTags intersectsSet:tagsForNote]) {
							[commonTags intersectSet:tagsForNote];
						}else {						
							[commonTags removeAllObjects];				
							break;
						}
						
					}else {				
						[commonTags removeAllObjects];				
						break;
					}
				}
				@catch (NSException * e) {
					NSLog(@"intersect EXCEPT: %@",[e description]);				
					[commonTags removeAllObjects];				
					break;					
				}				
			}else {						
				[commonTags removeAllObjects];				
				break;
			}			
		}
		if ([commonTags count]>0) {
			retArray = [commonTags allObjects];
		}
	}
	[noteEnum release];
	[commonTags release];
	
	//[retArray autorelease];
	return retArray;
}

- (IBAction)multiTag:(id)sender {
	NSCharacterSet *tagSeparators = [NSCharacterSet  characterSetWithCharactersInString:@", "];
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
	NSEnumerator *noteEnum = [[notationController notesAtIndexes:indexes] objectEnumerator];// retain];
	NoteObject *aNote;	
	NSString *existTags;
	NSMutableArray *theTags = [[[NSMutableArray alloc] init] autorelease];
	NSString *thisTag = [TagEditer newMultinoteLabels];
	NSEnumerator *tagEnum = [[thisTag componentsSeparatedByCharactersInSet:tagSeparators] objectEnumerator];
	[thisTag release];
	while ((thisTag = [tagEnum nextObject])) {
		if (([thisTag hasPrefix:@" "])||([thisTag hasSuffix:@" "])) {
			thisTag = [thisTag stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		}
		if ([thisTag hasPrefix:@","]) {
			thisTag = [thisTag substringFromIndex:1];
		}
		if ([thisTag hasSuffix:@","]) {
			thisTag = [thisTag substringToIndex:thisTag.length-1];
		}
		if (![thisTag isEqualToString:@""]) {
			[theTags addObject:thisTag];
		}		
	}
	if ([theTags count]<1) {
		[theTags addObject:@""];		
	}	
	while ((aNote = [noteEnum nextObject])){
		existTags = labelsOfNote(aNote);
		NSMutableArray *finalTags = [[[NSMutableArray alloc] init] autorelease];
		[finalTags addObjectsFromArray:theTags];
		tagEnum = [[existTags  componentsSeparatedByCharactersInSet:tagSeparators] objectEnumerator];		
		thisTag = nil;
		while ((thisTag = [tagEnum nextObject])) {
			if (([thisTag hasPrefix:@" "])||([thisTag hasSuffix:@" "])) {
				thisTag = [thisTag stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			}
			
			if ((![theTags containsObject:thisTag])&&(![cTags containsObject:thisTag])&&(![thisTag isEqualToString:@""])) {
				[finalTags addObject:thisTag];
			}					
		}
		NSString *newTagsString = [finalTags componentsJoinedByString:@" "];
		if ([newTagsString hasPrefix:@","]) {
			newTagsString = [newTagsString substringFromIndex:1];
		}
		if ([newTagsString hasSuffix:@","]) {
			newTagsString = [newTagsString substringToIndex:newTagsString.length-1];
		}
		[aNote setLabelString:newTagsString];
	}
	[TagEditer closeTP:self];
	[cTags release];
	[TagEditer release];
}

- (void)setDualFieldInToolbar {
	NSView *dualSV = [field superview];
	[dualFieldView removeFromSuperviewWithoutNeedingDisplay];
	[dualSV removeFromSuperviewWithoutNeedingDisplay];
	[dualFieldView release];
	dualFieldItem = [[NSToolbarItem alloc] initWithItemIdentifier:@"DualField"];
	[dualFieldItem setView:dualSV];
	[dualFieldItem setMaxSize:NSMakeSize(FLT_MAX, [dualSV frame].size.height)];
	[dualFieldItem setMinSize:NSMakeSize(50.0f, [dualSV frame].size.height)];
    [dualFieldItem setLabel:NSLocalizedString(@"Search or Create", @"placeholder text in search/create field")];
	
	toolbar = [[NSToolbar alloc] initWithIdentifier:@"NVToolbar"];
	[toolbar setAllowsUserCustomization:NO];
	[toolbar setAutosavesConfiguration:NO];
	[toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
	[toolbar setShowsBaselineSeparator:YES];
	[toolbar setVisible:![[NSUserDefaults standardUserDefaults] boolForKey:@"ToolbarHidden"]];
	[toolbar setDelegate:self];
	[window setToolbar:toolbar];
	
	[window setShowsToolbarButton:NO];
	titleBarButton = [[TitlebarButton alloc] initWithFrame:NSMakeRect(0, 0, 17.0, 17.0) pullsDown:YES];
	[titleBarButton addToWindow:window];
	
	[field setDelegate:self];
}

- (void)setDualFieldInView {
	NSView *dualSV = [field superview];
	BOOL dfIsVis = [toolbar isVisible];
	[dualSV removeFromSuperviewWithoutNeedingDisplay];
	NSView *wView = [window contentView];
	NSSize wSize = [wView frame].size;
	wSize.height = wSize.height - 38;
	[splitView setFrameSize:wSize];
	NSRect dfViewFrame = [splitView frame];
	dfViewFrame.size.height = 40;
	dfViewFrame.origin.y = [wView frame].origin.y+[splitView frame].size.height- 1;
	dualFieldView = [[[DFView alloc] initWithFrame:dfViewFrame] retain];	
	[wView addSubview:dualFieldView];
	NSRect dsvFrame = [dualSV frame];
	dsvFrame.origin.y +=4;
	dsvFrame.size.width = wSize.width * 0.986;
	dsvFrame.origin.x = (wSize.width *0.007);
	[dualSV setFrame:dsvFrame];
	[dualFieldView addSubview:dualSV];
	if (!dfIsVis) {
		[self hideDualFieldView];
	}
	[field setDelegate:self];
    
    [toolbar release];
    [titleBarButton release];
}

- (void)hideDualFieldView{
	if ([[window contentView] isInFullScreenMode]) {
		[dualFieldView setHidden:YES];
		NSSize wSize = [[window contentView] frame].size;
        
		[splitView setFrameSize:wSize];
		//[mainView setNeedsDisplay:YES];
	}else {
		[self _collapseToolbar];
	}
}

- (void)showDualFieldView{
	if ([[window contentView] isInFullScreenMode]) {
		NSSize wSize = [[window contentView] frame].size;
		wSize.height = wSize.height-38;
		[splitView setFrameSize:wSize];
		[dualFieldView setHidden:NO];
	}else {
		[self _expandToolbar];
	}
}

- (BOOL)dualFieldIsVisible{
    if ([[window contentView] isInFullScreenMode]) {
		return ![dualFieldView isHidden];
	}else {
        return [toolbar isVisible];
	}
}

- (IBAction)toggleCollapse:(id)sender{
	
	NSMenu *viewM = [[[NSApp mainMenu] itemWithTitle:@"View"] submenu];
	NSMenuItem *theItem = [viewM itemWithTitle:@"Expand Notes List"];
	if ([notesSubview isCollapsed]) {
		[[statBarMenu itemWithTitle:@"Expand Notes List"] setTitle:@"Collapse Notes List"];
		[theItem setTitle:@"Collapse Notes List"];
		[self showDualFieldView];
		[splitView setDivider: verticalDividerImg];//horiz ? nil : verticalDividerImg];
		
		BOOL horiz = [prefsController horizontalLayout];
		[splitView setDividerThickness: horiz ? 10.0 : 8.0];
		[notesSubview expand];	
		[splitView adjustSubviews];	
	}else {
		theItem = [viewM itemWithTitle:@"Collapse Notes List"];
		[theItem setTitle:@"Expand Notes List"];
		[[statBarMenu itemWithTitle:@"Collapse Notes List"] setTitle:@"Expand Notes List"];
		[self hideDualFieldView];
		
		[splitView setDividerThickness: 7.0];
		[notesSubview collapse];
		//	[splitView setDivider:nil];
		[splitView adjustSubviews];
		[window makeFirstResponder:textView];	
	}	
    [[window contentView] setNeedsDisplay:YES];
	[self setMaxNoteBodyWidth];
}


- (void)setMaxNoteBodyWidth{
	if ((![[window contentView] isInFullScreenMode])&&(![prefsController managesTextWidthInWindow])) {
		[textView setTextContainerInset:normalInset];
	}else{
		NSRect winRect = [window frame];
		float winHRatio = 0.93f;
		int kMargWidth = 3;
		if ([[window contentView] isInFullScreenMode]){
			winRect = [[window screen] frame];
			winHRatio = 0.85f;
			kMargWidth = [textView textContainerInset].width;	
		}
		int maxWidth = [prefsController maxNoteBodyWidth];	
		int kMargHt = 8;
		
		if ([splitView isVertical]) {
			if ((winRect.size.width - [notesSubview frame].size.width)>maxWidth) {
				kMargWidth = (winRect.size.width - [notesSubview frame].size.width - maxWidth)/2;
				kMargHt = (winRect.size.height-(winRect.size.height*winHRatio))/2;
			}		
		}else if (winRect.size.width>maxWidth) {
			kMargWidth = (winRect.size.width - maxWidth)/2;
			kMargHt = (winRect.size.height-(winRect.size.height*winHRatio))/2;
		}			
		if (kMargHt<8) {
			kMargHt = 8;
		}
		if (kMargWidth<3) {
			kMargWidth=3;
		}
		NSSize fullInset = NSMakeSize(kMargWidth,kMargHt);
		[textView setTextContainerInset:fullInset];
	}	
}


- (IBAction)toggleFullscreen:(id)sender
{		
	if(IsLeopardOrLater){
		@try {			
			NSResponder *currentResponder = [window firstResponder];
			NSDictionary* options;
			if (([[[NSUserDefaults standardUserDefaults] stringForKey:@"HideDockIcon"] isEqualToString:@"Hide Dock Icon"])&&(IsSnowLeopardOrLater)) {
				options = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:(NSApplicationPresentationAutoHideMenuBar | NSApplicationPresentationHideDock)],@"NSFullScreenModeApplicationPresentationOptions", nil];
			}else {
				options = [NSDictionary dictionaryWithObjectsAndKeys:nil];
			}
			
			if ([[window contentView] isInFullScreenMode]) {
				BOOL fIsHid = ![self dualFieldIsVisible]; 
				[self showDualFieldView];
				window = normalWindow;
                    [[window contentView] exitFullScreenModeWithOptions:options];                
                [window setBackgroundColor:backgrndColor];
				[self setDualFieldInToolbar];
				if (fIsHid) {
					[self hideDualFieldView];
                    
				}
				if ((!wasVert)&&([splitView isVertical])) {
					[self switchViewLayout:self];
				}
				[window makeKeyAndOrderFront:self];
                NSSize wSize = [[window contentView] frame].size;
				[splitView setFrameSize:wSize];
				
			}else {
				[[window contentView] enterFullScreenMode:[window screen]  withOptions:options];
				[self setDualFieldInView];
				if (![splitView isVertical]) {
					[self switchViewLayout:self];
					wasVert = NO;
				}else {
					wasVert = YES;
				}
				normalWindow = window;
				[normalWindow orderOut:self];
				window = [textView window];
                
                [window setBackgroundColor:backgrndColor];                
				[NSApp setDelegate:self];
				[notesTableView setDelegate:self];
				[window setDelegate:self];
				[field setDelegate:self];
				[textView setDelegate:self];
				[splitView setDelegate:self];
                NSSize wSize = [[window contentView] frame].size;
				wSize.height = [splitView frame].size.height;
				[splitView setFrameSize:wSize];
			}			
            
            [field setNextKeyView:textView];
            [textView setNextKeyView:field];
            [window setAutorecalculatesKeyViewLoop:NO];
			if ([[currentResponder description] rangeOfString:@"_NSFullScreenWindow"].length>0){
				currentResponder = textView;
			}
			if (([currentResponder isKindOfClass:[NSTextView class]])&&(![currentResponder isKindOfClass:[LinkingEditor class]])) {
				currentResponder = field;
			}
			[window setInitialFirstResponder:field];
			[window makeFirstResponder:currentResponder];
            
            [textView switchFindPanelDelegate];
			[textView setUsesFindPanel:YES];
            
            [self setMaxNoteBodyWidth];
			[splitView adjustSubviews];	
            
            [[window contentView] setNeedsDisplay:YES];
		}
		@catch (NSException * e) {
			NSLog(@"issues >%@<",[e name]);
		}
	}
}

- (IBAction)openFileInEditor:(id)sender { 
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
	NSString *path = nil;
	
	if ([indexes count] != 1 || !(path = [[notationController noteObjectAtFilteredIndex:[indexes lastIndex]] noteFilePath])) {
		NSBeep();
		return;
	}
	NSString *theApp = [prefsController textEditor];
	if (![[self getTxtAppList] containsObject:theApp]) {
		theApp = @"Default";
		[prefsController setTextEditor:@"Default"];
	}
	if ((![theApp isEqualToString:@"Default"])&&([[NSFileManager defaultManager] fileExistsAtPath:[[NSWorkspace sharedWorkspace] fullPathForApplication:theApp]])) {
		[[NSWorkspace sharedWorkspace] openFile:path withApplication:theApp];
	}else {				
		if (![theApp isEqualToString:@"Default"]) {
			[prefsController setTextEditor:@"Default"];
		}
		theApp = [(NSString *)LSCopyDefaultRoleHandlerForContentType((CFStringRef)noteFormat,kLSRolesEditor) autorelease];
		theApp = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier: theApp];
		theApp = [[NSFileManager defaultManager] displayNameAtPath: theApp];
		
		
		if ((!theApp)||([theApp isEqualToString:@"Safari"])) {
			theApp = @"TextEdit";
		}
		[[NSWorkspace sharedWorkspace] openFile:path withApplication:theApp];
	}

}

- (NSArray *)getTxtAppList{
	int format = [notationController currentNoteStorageFormat];
	if (format == 0) {
		noteFormat = @"database";
		[prefsController setTextEditor:nil];
		return nil;
	}else{
		if (format == 1) {
			noteFormat = [@"public.plain-text" retain];
			//
		}else if (format == 2) {
			noteFormat = [@"public.text" retain];
			//
		}else if (format == 3) {
			noteFormat = [@"public.html" retain];
			//
		}
		NSString *path = nil;
		NSMutableArray *retArray= [[[NSMutableArray alloc] initWithObjects:nil] autorelease];
		
		path = [[notationController noteObjectAtFilteredIndex:0] noteFilePath];
		CFURLRef myURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,(CFStringRef)path,kCFURLPOSIXPathStyle,false);

		NSArray *handlers = [(NSArray *)LSCopyApplicationURLsForURL(myURL,kLSRolesEditor) autorelease];
		CFRelease(myURL);
		if ([handlers count]>0) {
			for (NSString* fPath in handlers) {
				NSString* name = [[fPath lastPathComponent]stringByDeletingPathExtension];
				if ((![name hasPrefix:@"Adobe"])&&(![name isEqualToString:@"Dashcode"])&&(![retArray containsObject:name])&&(name)&&(![name isEqualToString:@"Notational Velocity"])) {
					[retArray addObject:name];
				}
			}	 	
		}
		handlers = [(NSArray *)LSCopyAllRoleHandlersForContentType((CFStringRef)noteFormat,kLSRolesEditor) autorelease];
		
		if ([handlers count]>0) {
			for (NSString* bundleIdentifier in handlers) {
				path = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier: bundleIdentifier];
				NSString* name = [[NSFileManager defaultManager] displayNameAtPath: path];
				if ((![name hasPrefix:@"Adobe"])&&(![name isEqualToString:@"Dashcode"])&&(![retArray containsObject:name])&&(name)&&(![name isEqualToString:@"Notational Velocity"])) {
					[retArray addObject:name];
				}
			}	 	
		}
		[retArray sortUsingSelector:@selector(caseInsensitiveCompare:)];
		NSString *defApp = [(NSString *)LSCopyDefaultRoleHandlerForContentType((CFStringRef)noteFormat,kLSRolesEditor) autorelease];
		defApp = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier: defApp];
		defApp = [[NSFileManager defaultManager] displayNameAtPath: defApp];
		
		if ((!defApp)||([defApp isEqualToString:@"Safari"])) {
			[retArray removeObjectAtIndex:[retArray indexOfObject:@"TextEdit"]];
			defApp = @"TextEdit";
		}
			defApp = [@"Default (" stringByAppendingString:defApp];
			defApp = [defApp stringByAppendingString:@")"];
		
		[retArray insertObject:defApp atIndex:0];
		return retArray;
		
	}
}

- (void)updateTextApp:(id)sender{
	[prefsWindowController updateAppList:self];
}

- (IBAction)setBWColorScheme:(id)sender{
	userScheme=0;
	[[NSUserDefaults standardUserDefaults] setInteger:userScheme forKey:@"ColorScheme"];
	[self setForegrndColor:[NSColor colorWithCalibratedRed:0.0f green:0.0f blue:0.0f alpha:1.0f]];
	[self setBackgrndColor:[NSColor colorWithCalibratedRed:1.0f green:1.0f blue:1.0f alpha:1.0f]];
	NSMenu *mainM = [NSApp mainMenu];
	NSMenu *viewM = [[mainM itemWithTitle:@"View"] submenu];
	mainM = [[viewM itemWithTitle:@"Color Schemes"] submenu];
	viewM = [[statBarMenu itemWithTitle:@"Color Schemes"] submenu];
	[[mainM itemAtIndex:0] setState:1];
	[[mainM itemAtIndex:1] setState:0];
	[[mainM itemAtIndex:2] setState:0];
	
	[[viewM  itemAtIndex:0] setState:1];
	[[viewM  itemAtIndex:1] setState:0];
	[[viewM  itemAtIndex:2] setState:0];
	[self updateColorScheme];
}

- (IBAction)setLCColorScheme:(id)sender{
	userScheme=1;
	[[NSUserDefaults standardUserDefaults] setInteger:userScheme forKey:@"ColorScheme"];
	[self setForegrndColor:[NSColor colorWithCalibratedRed:0.142f green:0.142f blue:0.142f alpha:1.0f]];
	[self setBackgrndColor:[NSColor colorWithCalibratedRed:0.874f green:0.874f blue:0.874f alpha:1.0f]];
	NSMenu *mainM = [NSApp mainMenu];
	NSMenu *viewM = [[mainM itemWithTitle:@"View"] submenu];
	mainM = [[viewM itemWithTitle:@"Color Schemes"] submenu];
	viewM = [[statBarMenu itemWithTitle:@"Color Schemes"] submenu];
	[[mainM itemAtIndex:0] setState:0];
	[[mainM itemAtIndex:1] setState:1];
	[[mainM itemAtIndex:2] setState:0];
	
	[[viewM  itemAtIndex:0] setState:0];
	[[viewM  itemAtIndex:1] setState:1];
	[[viewM  itemAtIndex:2] setState:0];
	[self updateColorScheme];
}

- (IBAction)setUserColorScheme:(id)sender{
	userScheme=2;
	[[NSUserDefaults standardUserDefaults] setInteger:userScheme forKey:@"ColorScheme"];
	[self setForegrndColor:[prefsController foregroundTextColor]];
	[self setBackgrndColor:[prefsController backgroundTextColor]];
	NSMenu *mainM = [NSApp mainMenu];
	NSMenu *viewM = [[mainM itemWithTitle:@"View"] submenu];
	mainM = [[viewM itemWithTitle:@"Color Schemes"] submenu];
	viewM = [[statBarMenu itemWithTitle:@"Color Schemes"] submenu];
	[[mainM itemAtIndex:0] setState:0];
	[[mainM itemAtIndex:1] setState:0];
	[[mainM itemAtIndex:2] setState:1];
	
	[[viewM  itemAtIndex:0] setState:0];
	[[viewM  itemAtIndex:1] setState:0];
	[[viewM  itemAtIndex:2] setState:1];
	//NSLog(@"foreground col is: %@",[foregrndColor description]);
	//NSLog(@"background col is: %@",[backgrndColor description]);
	[self updateColorScheme];
}

- (void)updateColorScheme{
	@try {		
        
        [mainView setBackgroundColor:backgrndColor];
        [window setBackgroundColor:backgrndColor];//[NSColor blueColor]
		[notesTableView setBackgroundColor:backgrndColor];
		[dividerShader updateColors:backgrndColor];
		[NotesTableHeaderCell setForegroundColor:foregrndColor];
		[dualFieldView setBackgroundColor:backgrndColor];
		//[editorStatusView setBackgroundColor:backgrndColor];
        //		[editorStatusView setNeedsDisplay:YES];
		//	[field setTextColor:foregrndColor];
		[textView updateTextColors];
		[notationController setForegroundTextColor:foregrndColor];
		
		if (currentNote) {
			[self contentsUpdatedForNote:currentNote];
		} 
	}
	@catch (NSException * e) {
		NSLog(@"setting SCheme EXception : %@",[e name]);
	}	
}

- (void)setBackgrndColor:(NSColor *)inColor{
	if (backgrndColor) {
		[backgrndColor release];
	}
	backgrndColor = inColor;
	[backgrndColor retain];
}

- (void)setForegrndColor:(NSColor *)inColor{
	if (foregrndColor) {
		[foregrndColor release];
	}
	foregrndColor = inColor;
	[foregrndColor retain];
}

- (NSColor *)backgrndColor{
	if (!backgrndColor) {
		NSColor *theColor = [NSColor redColor];
		if (!userScheme) {
			userScheme = [[NSUserDefaults standardUserDefaults] integerForKey:@"ColorScheme"];
		}
		if (userScheme==0) {
			theColor = [NSColor colorWithCalibratedRed:1.0f green:1.0f blue:1.0f alpha:1.0f];
		}else if (userScheme==1) {
			theColor = [NSColor colorWithCalibratedRed:0.874f green:0.874f blue:0.874f alpha:1.0f];
		}else if (userScheme==2) {
			NSData *theData = [[NSUserDefaults standardUserDefaults] dataForKey:@"BackgroundTextColor"];
			if (theData){
				theColor = (NSColor *)[NSUnarchiver unarchiveObjectWithData:theData];
			}else {
				theColor = [prefsController backgroundTextColor];
			}

		}	
		[self setBackgrndColor:theColor];
		return theColor;
	}else {
		return backgrndColor;
	}

}

- (NSColor *)foregrndColor{
	if (!foregrndColor) {
		NSColor *theColor = [NSColor blackColor];
		if (!userScheme) {
			userScheme = [[NSUserDefaults standardUserDefaults] integerForKey:@"ColorScheme"];
		}

		if (userScheme==0) {
			theColor = [NSColor colorWithCalibratedRed:0.0f green:0.0f blue:0.0f alpha:1.0f];
		}else if (userScheme==1) {
			theColor = [NSColor colorWithCalibratedRed:0.142f green:0.142f blue:0.142f alpha:1.0f];
		}else if (userScheme==2) {
			
			NSData *theData = [[NSUserDefaults standardUserDefaults] dataForKey:@"ForegroundTextColor"];
			if (theData){
				theColor = (NSColor *)[NSUnarchiver unarchiveObjectWithData:theData];
			}else {
				theColor = [prefsController foregroundTextColor];
			}			
		}	
		[self setForegrndColor:theColor];
		return theColor;
	}else {
		return foregrndColor;
	}

}

- (void)firstWordCount{
	NSTextStorage *noteStorage = [textView textStorage];
	int theCount = [[noteStorage words] count];
	if (theCount > 0) {
		[wordCounter setStringValue:[[NSString stringWithFormat:@"%d", theCount] stringByAppendingString:@" words"]];
	}else {
		[wordCounter setStringValue:@""];
	}


}

- (void)updateWordCount{
	if (![prefsController showWordCount]) {
		NSTextStorage *noteStorage = [textView textStorage];
		int theCount = [[noteStorage words] count];
		if (theCount > 0) {
			[wordCounter setStringValue:[[NSString stringWithFormat:@"%d", theCount] stringByAppendingString:@" words"]];
		}else {
			[wordCounter setStringValue:@""];
		}
	}
}

- (void)popWordCount:(BOOL)showIt{
	if (showIt) {
		if (([wordCounter isHidden])&&([prefsController showWordCount])) {
			[self firstWordCount];
			[wordCounter setHidden:NO];
		}
	}else {		
		if ((![wordCounter isHidden])&&([prefsController showWordCount])) {
			[wordCounter setHidden:YES];
			[wordCounter setStringValue:@""];
		}
	}
}

- (IBAction)toggleWordCount:(id)sender{
	if (ModFlagger==1) {
		if ((![wordCounter isHidden])&&([prefsController showWordCount])) {
			[wordCounter setHidden:YES];
			[wordCounter setStringValue:@""];
		}
	}else {
		if ([prefsController showWordCount]) {
			[self firstWordCount];
			[wordCounter setHidden:NO];
		}else {				
			[wordCounter setHidden:YES];
			[wordCounter setStringValue:@""];
		}
		if (![[sender className] isEqualToString:@"NSMenuItem"]) {
			[prefsController setShowWordCount:![prefsController showWordCount]];
			[prefsController synchronize];
		}
	}
}

- (void)flagsChanged:(NSEvent *)theEvent{
	if (ModFlagger>=0) {				
		if (([theEvent keyCode]==58)||([theEvent keyCode]==61)) {
			if (([theEvent modifierFlags]==524576)||([theEvent modifierFlags]==524608)) { //option down
				modifierTimer = [[NSTimer scheduledTimerWithTimeInterval:0.65
																  target:self
																selector:@selector(updateModifier:)
																userInfo:@"option"
																 repeats:NO] retain];
			}else if ([theEvent modifierFlags]==256) { //option up	
				
				if (modifierTimer) {
					if ([modifierTimer isValid]) {	
						[modifierTimer invalidate];
					}else {					
						[self performSelector:@selector(popWordCount:) withObject:NO afterDelay:0.35];
					}
					modifierTimer = nil;
					[modifierTimer release];
				}		
				ModFlagger = 0;
				
			}
		}else if (([theEvent keyCode]==59)||([theEvent keyCode]==62)) {
			if (([theEvent modifierFlags]==262401)||([theEvent modifierFlags]==270592))  { //control down
				modifierTimer = [[NSTimer scheduledTimerWithTimeInterval:0.70
																  target:self
																selector:@selector(updateModifier:)
																userInfo:@"control"
																 repeats:NO] retain];
				
			}else if ([theEvent modifierFlags]==256) { //control up		
				
				if (modifierTimer) {
					if ([modifierTimer isValid]) {	
						[modifierTimer invalidate];				
					}else {					
						[self performSelector:@selector(popPreview:) withObject:NO afterDelay:0.46];
					}		
					modifierTimer = nil;	
					[modifierTimer release];
				}		
				ModFlagger = 0;
			}
		}else if ([theEvent modifierFlags]==256) {	
			ModFlagger = 0;
			if (modifierTimer) {
				if ([modifierTimer isValid]) {	
					[modifierTimer invalidate];				
				}		
				modifierTimer = nil;	
				[modifierTimer release];
			}
			
		}else {
			ModFlagger = -1;
			if (modifierTimer) {
				if ([modifierTimer isValid]) {	
					[modifierTimer invalidate];				
				}		
				modifierTimer = nil;	
				[modifierTimer release];
			}
			NSTimer *disTimer = [NSTimer scheduledTimerWithTimeInterval:0.2f
																 target:self
															   selector:@selector(disableKeyMasks:)
															   userInfo:@"commandorshift"
																repeats:NO];
		}
	}	
}

- (void)updateModifier:(NSTimer*)theTimer{
	if ([theTimer isValid]) {
		if ([[theTimer userInfo] isEqualToString:@"option"]) {
			[self popWordCount:YES];
			ModFlagger = 1;
		}else if ([[theTimer userInfo] isEqualToString:@"control"]) {
			[self popPreview:YES];
			ModFlagger = 2;
		}		
		[theTimer invalidate];
	}
}

- (void)disableKeyMasks:(NSTimer *)aTimer{
	ModFlagger = 0;
	[aTimer invalidate];
	
}

- (void)resetModTimers{
	if (ModFlagger==1) {
		[self performSelector:@selector(popWordCount:) withObject:NO afterDelay:0.35];
	}else if (ModFlagger==2) {
		[self performSelector:@selector(popPreview:) withObject:NO afterDelay:0.46];
	}
	ModFlagger = 0;	
}


#pragma mark Preview-related and to be extracted into separate files
- (void)popPreview:(BOOL)showIt{
	if ([previewToggler state]==0) {
		if (showIt) {
			if (![previewController previewIsVisible]) {
				[self togglePreview:self];
			}
		}else {		
			if ([previewController previewIsVisible]) {
				[self togglePreview:self];
			}
		}
	}
}


- (IBAction)togglePreview:(id)sender
{
	BOOL doIt = (currentNote != nil);
	if ([previewController previewIsVisible]) {
		doIt = YES;
	}
	if ([[sender className] isEqualToString:@"NSMenuItem"]) {				
			[sender setState:![sender state]];		
	}
	if (doIt) {
		[previewController togglePreview:self];
	}
}

- (IBAction)toggleSourceView:(id)sender
{
	[previewController switchTabs:self];
}

- (IBAction)savePreview:(id)sender
{
	if (![[previewController window] isVisible]) {
        [previewController togglePreview:self];
	}
	[previewController saveHTML:self];
}

- (IBAction)sharePreview:(id)sender
{
	[previewController shareAsk:self];
}

- (void)postTextUpdate
{
	
    [[NSNotificationCenter defaultCenter] postNotificationName:NSTextViewChangedNotification object:self];
}

- (IBAction)selectPreviewMode:(id)sender
{
    NSMenuItem *previewItem = sender;
    currentPreviewMode = [previewItem tag];
    
    // update user defaults
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:currentPreviewMode]
                                              forKey:kDefaultMarkupPreviewMode];
    
    [self postTextUpdate];
}

@end
