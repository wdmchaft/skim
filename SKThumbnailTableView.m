//
//  SKThumbnailTableView.m
//  Skim
//
//  Created by Christiaan Hofman on 2/25/07.
/*
 This software is Copyright (c) 2007-2009
 Christiaan Hofman. All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:

 - Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

 - Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in
    the documentation and/or other materials provided with the
    distribution.

 - Neither the name of Christiaan Hofman nor the names of any
    contributors may be used to endorse or promote products derived
    from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "SKThumbnailTableView.h"
#import "SKRuntime.h"
#import "SKTypeSelectHelper.h"
#import "NSColor_SKExtensions.h"

#define SKScrollerWillScrollNotification @"SKScrollerWillScrollNotification"
#define SKScrollerDidScrollNotification @"SKScrollerDidScrollNotification"

@interface NSScroller (SKExtensions)
@end

@implementation NSScroller (SKExtensions)

static void (*original_trackKnob)(id, SEL, id) = NULL;

- (void)replacement_trackKnob:(NSEvent *)theEvent {
    [[NSNotificationCenter defaultCenter] postNotificationName:SKScrollerWillScrollNotification object:self];
    original_trackKnob(self, _cmd, theEvent);
    [[NSNotificationCenter defaultCenter] postNotificationName:SKScrollerDidScrollNotification object:self];
}

+ (void)load {
    original_trackKnob = (void (*)(id, SEL, id))SKReplaceInstanceMethodImplementationFromSelector(self, @selector(trackKnob:), @selector(replacement_trackKnob:));
}

@end

@implementation SKThumbnailTableView

- (id)initWithFrame:(NSRect)frameRect {
    if (self = [super initWithFrame:frameRect]) {
        if ([self respondsToSelector:@selector(setSelectionHighlightStyle:)])
            [self setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleSourceList];
        else
            [self setBackgroundColor:[NSColor tableBackgroundColor]];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)coder {
    if (self = [super initWithCoder:coder]) {
        if ([self respondsToSelector:@selector(setSelectionHighlightStyle:)])
            [self setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleSourceList];
        else
            [self setBackgroundColor:[NSColor tableBackgroundColor]];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)highlightSelectionInClipRect:(NSRect)clipRect {
    NSColor *color;
    int row;
    NSRect rect;
    
    if ([self respondsToSelector:@selector(setSelectionHighlightStyle:)]) {
        if ([[self window] isKeyWindow] && [[self window] firstResponder] == self)
            color = [NSColor colorWithCalibratedRed:0.296719 green:0.489387 blue:0.823514 alpha:1.0];
        else if ([[self window] isKeyWindow])
            color = [NSColor colorWithCalibratedRed:0.659915 green:0.709033 blue:0.788708 alpha:1.0];
        else
            color = [NSColor colorWithCalibratedRed:0.496086 green:0.496086 blue:0.496086 alpha:1.0];
    } else {
        if ([[self window] isKeyWindow] && [[self window] firstResponder] == self)
            color = [NSColor alternateSelectedControlColor];
        else
            color = [NSColor secondarySelectedTableColor];
    }
    
    [NSGraphicsContext saveGraphicsState];
    
    if ([[self delegate] respondsToSelector:@selector(tableViewHighlightedRows:)]) {
        
        NSMutableIndexSet *rowIndexes = [[[self selectedRowIndexes] mutableCopy] autorelease];
        NSArray *rows = [[self delegate] tableViewHighlightedRows:self];
        int i, count = MIN((int)[rows count], 5);
        
        for (i = 0; i < count; i++) {
            row = [[rows objectAtIndex:i] intValue];
            rect = [self rectOfRow:row];
            if (NSIntersectsRect(rect, clipRect) && [rowIndexes containsIndex:row] == NO) {
                [[color colorWithAlphaComponent:0.5 - 0.1 * i] setFill];
                [NSBezierPath fillRect:rect];
            }
            [rowIndexes addIndex:row];
        }
    }
    
    [NSGraphicsContext restoreGraphicsState];
    
    [super highlightSelectionInClipRect:clipRect];
}

- (void)selectRowIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extendSelection {
    [super selectRowIndexes:indexes byExtendingSelection:extendSelection];
    [self setNeedsDisplay:YES];
}

- (void)deselectRow:(int)row {
    [super deselectRow:row];
    [self setNeedsDisplay:YES];
}

- (BOOL)isScrolling { return isScrolling; }

- (void)handleScrollerWillScroll:(NSNotification *)note {
    isScrolling = YES;
}

- (void)handleScrollerDidScroll:(NSNotification *)note {
    isScrolling = NO;
    [self setNeedsDisplayInRect:[self visibleRect]];
}

- (void)awakeFromNib {
    NSScroller *scroller = [[self enclosingScrollView] verticalScroller];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleScrollerWillScroll:)
                                                 name:SKScrollerWillScrollNotification object:scroller];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleScrollerDidScroll:)
                                                 name:SKScrollerDidScrollNotification object:scroller];
}

- (void)setFrame:(NSRect)frameRect {
    [super setFrame:frameRect];
    [self noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [self numberOfRows])]];
}

- (void)setFrameSize:(NSSize)frameSize {
    [super setFrameSize:frameSize];
    [self noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [self numberOfRows])]];
}

- (void)mouseDown:(NSEvent *)theEvent {
    if (([theEvent modifierFlags] & NSCommandKeyMask) && [[self delegate] respondsToSelector:@selector(tableView:commandSelectRow:)]) {
        int row = [self rowAtPoint:[self convertPoint:[theEvent locationInWindow] fromView:nil]];
        if (row != -1 && [[self delegate] tableView:self commandSelectRow:row])
            return;
    }
    [super mouseDown:theEvent];
}

@end
