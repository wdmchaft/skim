//
//  PDFAnnotation_SKExtensions.m
//  Skim
//
//  Created by Christiaan Hofman on 4/1/08.
/*
 This software is Copyright (c) 2008-2010
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

#import "PDFAnnotation_SKExtensions.h"
#import "PDFAnnotationCircle_SKExtensions.h"
#import "PDFAnnotationSquare_SKExtensions.h"
#import "PDFAnnotationLine_SKExtensions.h"
#import "PDFAnnotationMarkup_SKExtensions.h"
#import "PDFAnnotationFreeText_SKExtensions.h"
#import "PDFAnnotationText_SKExtensions.h"
#import "PDFAnnotationInk_SKExtensions.h"
#import <SkimNotes/SkimNotes.h>
#import "SKNPDFAnnotationNote_SKExtensions.h"
#import "PDFBorder_SKExtensions.h"
#import "SKStringConstants.h"
#import "SKFDFParser.h"
#import "PDFPage_SKExtensions.h"
#import "PDFSelection_SKExtensions.h"
#import "SKPDFView.h"
#import "NSGeometry_SKExtensions.h"
#import "NSData_SKExtensions.h"
#import "NSString_SKExtensions.h"
#import "NSBezierPath_SKExtensions.h"
#import "SKVersionNumber.h"

#define SKUseUserNameKey @"SKUseUserName"
#define SKUserNameKey @"SKUserName"


FourCharCode SKScriptingBorderStyleFromBorderStyle(PDFBorderStyle borderStyle) {
    switch (borderStyle) {
        case kPDFBorderStyleSolid: return SKScriptingBorderStyleSolid;
        case kPDFBorderStyleDashed: return SKScriptingBorderStyleDashed;
        case kPDFBorderStyleBeveled: return SKScriptingBorderStyleBeveled;
        case kPDFBorderStyleInset: return SKScriptingBorderStyleInset;
        case kPDFBorderStyleUnderline: return SKScriptingBorderStyleUnderline;
        default: return SKScriptingBorderStyleSolid;
    }
}

PDFBorderStyle SKBorderStyleFromScriptingBorderStyle(FourCharCode borderStyle) {
    switch (borderStyle) {
        case SKScriptingBorderStyleSolid: return kPDFBorderStyleSolid;
        case SKScriptingBorderStyleDashed: return kPDFBorderStyleDashed;
        case SKScriptingBorderStyleBeveled: return kPDFBorderStyleBeveled;
        case SKScriptingBorderStyleInset: return kPDFBorderStyleInset;
        case SKScriptingBorderStyleUnderline: return kPDFBorderStyleUnderline;
        default: return kPDFBorderStyleSolid;
    }
}


NSString *SKPDFAnnotationScriptingNoteTypeKey = @"scriptingNoteType";
NSString *SKPDFAnnotationScriptingBorderStyleKey = @"scriptingBorderStyle";
NSString *SKPDFAnnotationScriptingColorKey = @"scriptingColor";
NSString *SKPDFAnnotationScriptingModificationDateKey = @"scriptingModificationDate";
NSString *SKPDFAnnotationScriptingUserNameKey = @"scriptingUserName";

BOOL SKPDFAnnotationLeaksBorder = NO;

enum {
    SKPDFAnnotationScriptingNoteClassCode = 'Note'
};

@implementation PDFAnnotation (SKExtensions)

+ (void)checkPDFKit {
    // Some PDFAnnotation subclasses over-retain the initial PDFBorder ivar, at least on PDFKit version 2.5 (MacOSX 10.6.0-2) and 2.5.1 (MacOSX 10.6.3-4)
    SKVersionNumber *PDFKitVersion = [[[SKVersionNumber alloc] initWithVersionString:[[NSBundle bundleForClass:self] objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey]] autorelease];
    SKVersionNumber *minVersion = [[[SKVersionNumber alloc] initWithVersionString:@"2.5"] autorelease];
    SKVersionNumber *maxVersion = [[[SKVersionNumber alloc] initWithVersionString:@"2.5.1"] autorelease];
    if ([PDFKitVersion compare:minVersion] != NSOrderedAscending && [PDFKitVersion compare:maxVersion] != NSOrderedDescending)
        SKPDFAnnotationLeaksBorder = YES;
}

- (NSString *)fdfString {
    NSMutableString *fdfString = [NSMutableString string];
    NSRect bounds = [self bounds];
    CGFloat r, g, b, a = 0.0;
    PDFBorder *border = [self border];
    NSString *contents = [self contents];
    NSDate *modDate = [self modificationDate];
    NSString *userName = [self userName];
    [[self color] getRed:&r green:&g blue:&b alpha:&a];
    [fdfString appendFDFName:SKFDFTypeKey];
    [fdfString appendFDFName:SKFDFAnnotation];
    [fdfString appendFDFName:SKFDFAnnotationTypeKey];
    [fdfString appendFormat:@"/%@", [[self type] isEqualToString:SKNNoteString] ? SKNTextString : [self type]];
    [fdfString appendFDFName:SKFDFAnnotationBoundsKey];
    [fdfString appendFormat:@"[%f %f %f %f]", NSMinX(bounds), NSMinY(bounds), NSMaxX(bounds), NSMaxY(bounds)];
    [fdfString appendFDFName:SKFDFAnnotationPageIndexKey];
    [fdfString appendFormat:@" %lu", (unsigned long)[self pageIndex]];
    [fdfString appendFDFName:SKFDFAnnotationFlagsKey];
    [fdfString appendString:@" 4"];
    if (a > 0.0) {
        [fdfString appendFDFName:SKFDFAnnotationColorKey];
        [fdfString appendFormat:@"[%f %f %f]", r, g, b];
    }
    [fdfString appendFDFName:SKFDFAnnotationBorderStylesKey];
    [fdfString appendString:@"<<"];
    if (border) {
        [fdfString appendFDFName:SKFDFAnnotationLineWidthKey];
        [fdfString appendFormat:@" %f", [border lineWidth]];
        [fdfString appendFDFName:SKFDFAnnotationBorderStyleKey];
        [fdfString appendFDFName:SKFDFBorderStyleFromPDFBorderStyle([border style])];
        [fdfString appendFDFName:SKFDFAnnotationDashPatternKey];
        [fdfString appendFormat:@"[%@]", [[[border dashPattern] valueForKey:@"stringValue"] componentsJoinedByString:@" "]];
    } else {
        [fdfString appendFDFName:SKFDFAnnotationLineWidthKey];
        [fdfString appendString:@" 0.0"];
    }
    [fdfString appendString:@">>"];
    [fdfString appendFDFName:SKFDFAnnotationContentsKey];
    [fdfString appendString:@"("];
    if (contents)
        [fdfString appendString:[[contents lossyISOLatin1String] stringByEscapingParenthesis]];
    [fdfString appendString:@")"];
    if (modDate) {
        [fdfString appendFDFName:SKFDFAnnotationModificationDateKey];
        [fdfString appendFormat:@"(%@)", SKFDFStringFromDate(modDate)];
    }
    if (userName) {
        [fdfString appendFDFName:SKFDFAnnotationUserNameKey];
        [fdfString appendFormat:@"(%@)", [[userName lossyISOLatin1String] stringByEscapingParenthesis]];
    }
    return fdfString;
}

- (PDFDestination *)destination{
    NSRect bounds = [self bounds];
    NSPoint point = SKTopLeftPoint(bounds);
    return [[[PDFDestination alloc] initWithPage:[self page] atPoint:point] autorelease];
}

- (NSUInteger)pageIndex {
    PDFPage *page = [self page];
    return page ? [page pageIndex] : NSNotFound;
}

- (PDFBorderStyle)borderStyle {
    return [[self border] style];
}

- (void)setBorderStyle:(PDFBorderStyle)style {
    if ([self isEditable]) {
        PDFBorder *border = [[self border] copyWithZone:[self zone]];
        if (border == nil && style)
            border = [[PDFBorder allocWithZone:[self zone]] init];
        [border setStyle:style];
        [self setBorder:border];
        [border release];
    }
}

- (CGFloat)lineWidth {
    return [[self border] lineWidth];
}

- (void)setLineWidth:(CGFloat)width {
    if ([self isEditable]) {
        PDFBorder *border = nil;
        if (width > 0.0) {
            border = [[self border] copyWithZone:[self zone]];
            if (border == nil)
                border = [[PDFBorder allocWithZone:[self zone]] init];
            [border setLineWidth:width];
        } 
        [self setBorder:border];
        [border release];
    }
}

- (NSArray *)dashPattern {
    return [[self border] dashPattern];
}

- (void)setDashPattern:(NSArray *)pattern {
    if ([self isEditable]) {
        PDFBorder *border = [[self border] copyWithZone:[self zone]];
        if (border == nil && [pattern count])
            border = [[PDFBorder allocWithZone:[self zone]] init];
        [border setDashPattern:pattern];
        [self setBorder:border];
        [border release];
    }
}

- (PDFTextAnnotationIconType)iconType { return kPDFTextAnnotationIconNote; }

- (NSImage *)image { return nil; }

- (NSAttributedString *)text { return nil; }

- (NSArray *)texts { return nil; }

- (NSColor *)interiorColor { return nil; }

- (BOOL)isMarkup { return NO; }

- (BOOL)isLink { return NO; }

- (BOOL)isResizable { return NO; }

- (BOOL)isMovable { return NO; }

- (BOOL)isEditable { return [self isSkimNote] && [[self page] isNotesPage] == NO; }

- (BOOL)hasBorder { return [self isSkimNote]; }

- (BOOL)isConvertibleAnnotation { return NO; }

- (BOOL)hitTest:(NSPoint)point {
    NSRect bounds = [self bounds];
    if ([self isResizable])
        bounds = NSInsetRect(bounds, -4.0, -4.0);
    return [self shouldDisplay] ? NSPointInRect(point, bounds) : NO;
}

- (NSRect)displayRectForBounds:(NSRect)bounds {
    if ([self isResizable])
        bounds = NSInsetRect(bounds, -4.0, -4.0);
    return bounds;
}

- (void)registerUserName {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:SKUseUserNameKey]) {
        NSString *userName = [[NSUserDefaults standardUserDefaults] stringForKey:SKUserNameKey];
        [self setUserName:[userName length] ? userName : NSFullUserName()];
    }
    if ([[NSUserDefaults standardUserDefaults] boolForKey:SKDisableModificationDateKey] == NO)
        [self setModificationDate:[NSDate date]];
}

- (NSSet *)keysForValuesToObserveForUndo {
    static NSSet *keys = nil;
    if (keys == nil)
        keys = [[NSSet alloc] initWithObjects:SKNPDFAnnotationBoundsKey, SKNPDFAnnotationStringKey, SKNPDFAnnotationColorKey, SKNPDFAnnotationBorderKey, SKNPDFAnnotationModificationDateKey, SKNPDFAnnotationUserNameKey, nil];
    return keys;
}

#pragma mark Scripting support

- (NSScriptObjectSpecifier *)objectSpecifier {
	NSUInteger idx = [[[self page] notes] indexOfObjectIdenticalTo:self];
    if (idx != NSNotFound) {
        NSScriptObjectSpecifier *containerRef = [[self page] objectSpecifier];
        return [[[NSIndexSpecifier allocWithZone:[self zone]] initWithContainerClassDescription:[containerRef keyClassDescription] containerSpecifier:containerRef key:@"notes" index:idx] autorelease];
    } else {
        return nil;
    }
}

// to support the 'duplicate' command
- (id)copyWithZone:(NSZone *)zone {
    PDFAnnotation *copy = nil;
    if ([self isMovable]) { // we don't want to duplicate markup
        copy = [[PDFAnnotation allocWithZone:zone] initSkimNoteWithProperties:[self SkimNoteProperties]];
        [copy registerUserName];
    }
    return copy;
}

// overridden by subclasses to add or remove custom scripting keys relevant for the class, subclasses should call super first
+ (NSSet *)customScriptingKeys {
    static NSSet *customScriptingKeys = nil;
    if (customScriptingKeys == nil)
        customScriptingKeys = [[NSSet alloc] initWithObjects:SKNPDFAnnotationLineWidthKey, SKPDFAnnotationScriptingBorderStyleKey, SKNPDFAnnotationDashPatternKey, SKPDFAnnotationScriptingModificationDateKey, SKPDFAnnotationScriptingUserNameKey, nil];
    return customScriptingKeys;
}

- (NSDictionary *)scriptingProperties {
    static NSSet *allCustomScriptingKeys = nil;
    if (allCustomScriptingKeys == nil) {
        NSMutableSet *customScriptingKeys = [NSMutableSet set];
        [customScriptingKeys unionSet:[PDFAnnotationCircle customScriptingKeys]];
        [customScriptingKeys unionSet:[PDFAnnotationSquare customScriptingKeys]];
        [customScriptingKeys unionSet:[PDFAnnotationFreeText customScriptingKeys]];
        [customScriptingKeys unionSet:[SKNPDFAnnotationNote customScriptingKeys]];
        [customScriptingKeys unionSet:[PDFAnnotationMarkup customScriptingKeys]];
        [customScriptingKeys unionSet:[PDFAnnotationLine customScriptingKeys]];
        [customScriptingKeys unionSet:[PDFAnnotationInk customScriptingKeys]];
        allCustomScriptingKeys = [customScriptingKeys copy];
    }
    // remove all custom properties that are not valid for this class
    NSMutableDictionary *properties = [[[super scriptingProperties] mutableCopy] autorelease];
    NSMutableSet *customKeys = [allCustomScriptingKeys mutableCopy];
    [properties removeObjectsForKeys:[customKeys allObjects]];
    [customKeys release];
    return properties;
}

- (void)setScriptingProperties:(NSDictionary *)properties {
    [super setScriptingProperties:properties];
    // set the borderStyle afterwards, as this may have been changed when setting the dash pattern
    id style = [properties objectForKey:SKPDFAnnotationScriptingBorderStyleKey];
    if ([style respondsToSelector:@selector(integerValue)] && [properties objectForKey:SKNPDFAnnotationDashPatternKey])
        [self setScriptingBorderStyle:[style integerValue]];
}

- (FourCharCode)scriptingNoteType {
    return 0;
}

- (NSColor *)scriptingColor {
    return [self color];
}

- (void)setScriptingColor:(NSColor *)newColor {
    if ([self isEditable]) {
        [self setColor:newColor];
    }
}

- (PDFPage *)scriptingPage {
    return [self page];
}

- (NSDate *)scriptingModificationDate {
    return [self modificationDate];
}

- (void)setScriptingModificationDate:(NSDate *)date {
    if ([self isEditable]) {
        [self setModificationDate:date];
    }
}

- (NSString *)scriptingUserName {
    return [self userName];
}

- (void)setScriptingUserName:(NSString *)name {
    if ([self isEditable]) {
        [self setUserName:name];
    }
}

- (FourCharCode)scriptingIconType {
    return SKScriptingTextAnnotationIconNote;
}

- (id)textContents;
{
    return [[[NSTextStorage alloc] initWithString:[self string] ?: @""] autorelease];
}

- (void)setTextContents:(id)text;
{
    if ([self isEditable]) {
        [self setString:[text string]];
    }
}

- (id)coerceValueForTextContents:(id)value {
    return [[NSScriptCoercionHandler sharedCoercionHandler] coerceValue:value toClass:[NSTextStorage class]];
}

- (id)richText {
    return nil;
}

- (void)setBoundsAsQDRect:(NSData *)inQDBoundsAsData {
    if ([self isMovable] && [self isEditable]) {
        NSRect newBounds = [inQDBoundsAsData rectValueAsQDRect];
        if ([self isResizable] == NO) {
            newBounds.size = [self bounds].size;
        } else {
            if (NSWidth(newBounds) < 0.0)
                newBounds.size.width = 0.0;
            if (NSHeight(newBounds) < 0.0)
                newBounds.size.height = 0.0;
        }
        [self setBounds:newBounds];
    }

}

- (NSData *)boundsAsQDRect {
    return [NSData dataWithRectAsQDRect:[self bounds]];
}

- (NSColor *)scriptingInteriorColor {
    return nil;
}

- (NSString *)fontName {
    return nil;
}

- (CGFloat)fontSize {
    return 0;
}

- (NSColor *)scriptingFontColor {
    return nil;
}

- (FourCharCode)scriptingAlignment {
    return SKScriptingAlignmentLeft;
}

- (FourCharCode)scriptingBorderStyle {
    return SKScriptingBorderStyleFromBorderStyle([self borderStyle]);
}

- (void)setScriptingBorderStyle:(NSInteger)borderStyle {
    if ([self isEditable]) {
        [self setBorderStyle:SKBorderStyleFromScriptingBorderStyle(borderStyle)];
    }
}

- (NSData *)startPointAsQDPoint {
    return nil;
}

- (NSData *)endPointAsQDPoint {
    return nil;
}

- (FourCharCode)scriptingStartLineStyle {
    return SKScriptingLineStyleNone;
}

- (FourCharCode)scriptingEndLineStyle {
    return SKScriptingLineStyleNone;
}

- (id)selectionSpecifier {
    return nil;
}

- (NSArray *)scriptingPointLists {
    return nil;
}

#pragma mark Accessibility

- (NSArray *)accessibilityAttributeNames {
    static NSArray *attributes = nil;
    if (attributes == nil) {
        attributes = [[NSArray alloc] initWithObjects:
            NSAccessibilityRoleAttribute,
            NSAccessibilityRoleDescriptionAttribute,
            NSAccessibilityTitleAttribute,
            NSAccessibilityValueAttribute,
            NSAccessibilityParentAttribute,
            NSAccessibilityWindowAttribute,
            NSAccessibilityTopLevelUIElementAttribute,
            NSAccessibilityFocusedAttribute,
            NSAccessibilityEnabledAttribute,
            NSAccessibilityPositionAttribute,
            NSAccessibilitySizeAttribute,
            nil];
    }
    return attributes;
}

- (id)accessibilityRoleAttribute {
    return NSAccessibilityUnknownRole;
}

- (id)accessibilityRoleDescriptionAttribute {
    return NSAccessibilityRoleDescription([self accessibilityRoleAttribute], nil);
}

- (id)accessibilityTitleAttribute {
    return [[self type] typeName];
}

- (id)accessibilityValueAttribute {
    return [self contents];
}

- (id)accessibilityEnabledAttribute {
    return [NSNumber numberWithBool:NO];
}

- (BOOL)accessibilityIsIgnored {
    return [self shouldDisplay] == NO;
}

@end
