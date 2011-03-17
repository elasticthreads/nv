//
//  DFView.m
//  Notation
//
//  Created by ElasticThreads on 2/15/11.
//

#import "DFView.h"
#import "AppController.h"


@implementation DFView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (void)dealloc{
	[vColor release];
	[super dealloc];
}

- (void)drawRect:(NSRect)rect {    
	NSRect bounds = [self bounds];
    bounds.origin.x -=2.0f;
    bounds.size.width +=4.0f;
	if (!vColor) {
        [self setBackgroundColor:[[NSApp delegate] backgrndColor]];
	}
	[vColor set];
    //NSRectFill(bounds);	
    NSFrameRect(bounds);
}

- (void)setBackgroundColor:(NSColor *)inColor{
    if (vColor) {
        [vColor release];
    }
    CGFloat fWhite;
	
	fWhite = [[inColor colorUsingColorSpaceName:NSCalibratedWhiteColorSpace] whiteComponent];
	if (fWhite < 0.75f) {
		if (fWhite<0.25f) {
			fWhite += 0.22f;
		}else {
			fWhite += 0.16f;
		}		
	}else {
		fWhite -= 0.20f;
	}	
	vColor = [NSColor colorWithCalibratedWhite:fWhite alpha:1.0f];
	[vColor retain];
}

@end
