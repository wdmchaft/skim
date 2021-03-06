//
//  SKConversionProgressController.m
//  Skim
//
//  Created by Adam Maxwell on 12/6/06.
/*
 This software is Copyright (c) 2006-2010
 Adam Maxwell. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 
 - Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 
 - Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in
 the documentation and/or other materials provided with the
 distribution.
 
 - Neither the name of Adam Maxwell nor the names of any
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

#import "SKConversionProgressController.h"
#import "NSString_SKExtensions.h"
#import "NSURL_SKExtensions.h"
#import "NSTask_SKExtensions.h"
#import "NSFileManager_SKExtensions.h"
#import "NSInvocation_SKExtensions.h"
#import "SKDocumentController.h"
#import <libkern/OSAtomic.h>
#import "NSGeometry_SKExtensions.h"
#import "NSDocument_SKExtensions.h"

#define PROVIDER_KEY    @"provider"
#define CONSUMER_KEY    @"consumer"
#define INPUTFILE_KEY   @"inputFile"
#define PDFDATA_KEY     @"pdfData"
#define TOOLPATH_KEY    @"toolPath"

#define SKDviConversionCommandKey @"SKDviConversionCommand"
#define SKXdvConversionCommandKey @"SKXdvConversionCommand"

#define MIN_BUTTON_WIDTH 90.0

enum {
    SKConversionSucceeded = 0,
    SKConversionFailed = 1
};

@interface SKConversionProgressController (Private)
+ (NSString *)dviToolPath;
+ (NSString *)xdvToolPath;
- (NSData *)PDFDataWithPostScriptData:(NSData *)psData error:(NSError **)outError;
- (NSData *)PDFDataWithDVIFile:(NSString *)dviFile toolPath:(NSString *)toolPath fileType:(NSString *)aFileType error:(NSError **)outError;
- (void)conversionCompleted:(BOOL)didComplete;
- (void)conversionStarted;
- (void)converterWasStopped;
- (void)setButtonTitle:(NSString *)title action:(SEL)action;
@end

#pragma mark Callbacks

static void PSConverterBeginDocumentCallback(void *info)
{
    id delegate = (id)info;
    if ([delegate respondsToSelector:@selector(conversionStarted)])
        [delegate performSelectorOnMainThread:@selector(conversionStarted) withObject:nil waitUntilDone:NO];
}

static void PSConverterEndDocumentCallback(void *info, bool success)
{
    id delegate = (id)info;
    if ([delegate respondsToSelector:@selector(conversionCompleted:)]) {
        BOOL val = (success == true);
        NSInvocation *invocation = [NSInvocation invocationWithTarget:delegate selector:@selector(conversionCompleted:) argument:&val];
        [invocation performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:NO];
    }
}

CGPSConverterCallbacks SKPSConverterCallbacks = { 
    0, 
    PSConverterBeginDocumentCallback, 
    PSConverterEndDocumentCallback, 
    NULL, // haven't seen this called in my testing
    NULL, 
    NULL, 
    NULL, // messages are usually not useful
    NULL 
};

#pragma mark -

@implementation SKConversionProgressController

@synthesize cancelButton, progressBar, textField;

+ (NSData *)PDFDataWithPostScriptData:(NSData *)psData error:(NSError **)outError {
    return [[[[self alloc] init] autorelease] PDFDataWithPostScriptData:psData error:outError];
}

+ (NSData *)PDFDataWithDVIFile:(NSString *)dviFile error:(NSError **)outError {
    NSString *dviToolPath = [self dviToolPath];
    if (dviToolPath)
        return [[[[self alloc] init] autorelease] PDFDataWithDVIFile:dviFile toolPath:dviToolPath fileType:SKDVIDocumentType error:outError];
    else
        NSBeep();
    return nil;
}

+ (NSData *)PDFDataWithXDVFile:(NSString *)xdvFile error:(NSError **)outError {
    NSString *xdvToolPath = [self xdvToolPath];
    if (xdvToolPath)
        return [[[[self alloc] init] autorelease] PDFDataWithDVIFile:xdvFile toolPath:xdvToolPath fileType:SKXDVDocumentType error:outError];
    else
        NSBeep();
    return nil;
}

- (void)dealloc {
    SKCFDESTROY(converter);
    SKCFDESTROY(cancelButton);
    SKCFDESTROY(progressBar);
    SKCFDESTROY(textField);
    [super dealloc];
}

- (void)awakeFromNib {
    [[self window] setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
    [progressBar setUsesThreadedAnimation:YES];
    [self setButtonTitle:NSLocalizedString(@"Cancel", @"Button title") action:@selector(cancel:)];
    [[self window] setTitle:[NSString stringWithFormat:NSLocalizedString(@"Converting %@", @"PS conversion progress message"), [[NSDocumentController sharedDocumentController] displayNameForType:fileType]]];
}

- (NSString *)windowNibName { return @"ConversionProgressWindow"; }

- (IBAction)close:(id)sender { [self close]; }

- (IBAction)cancel:(id)sender {
    OSMemoryBarrier();
    if (cancelled == 1) {
        [self converterWasStopped];
    } else {
        OSAtomicCompareAndSwap32Barrier(0, 1, (int32_t *)&cancelled);
        if (convertingPS)
            CGPSConverterAbort(converter);
    }
}

- (NSInteger)runModalSelector:(SEL)selector withObject:(NSDictionary *)info {
    
    NSModalSession session = [NSApp beginModalSessionForWindow:[self window]];
    BOOL didDetach = NO;
    NSInteger rv = 0;
    
    while (YES) {
        
        // we run this inside the modal session since the thread could end before runModalForWindow starts
        if (NO == didDetach) {
            [NSThread detachNewThreadSelector:selector toTarget:self withObject:info];
            didDetach = YES;
        }
        
        rv = [NSApp runModalSession:session];
        if (rv != NSRunContinuesResponse)
            break;
    }
    
    [NSApp endModalSession:session];
    
    // close the window when finished
    [self close];
    
    return rv;
}
 
- (void)stopModalOnMainThread:(BOOL)success {
    NSInteger val = (success ? SKConversionSucceeded : SKConversionFailed);
    NSInvocation *invocation = [NSInvocation invocationWithTarget:NSApp selector:@selector(stopModalWithCode:) argument:&val];
    [invocation performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:NO];
}

- (void)converterWasStopped {
    NSBeep();
    [textField setStringValue:NSLocalizedString(@"Converter already stopped.", @"PS conversion progress message")];
    [self setButtonTitle:NSLocalizedString(@"Close", @"Button title") action:@selector(close:)];
}

- (void)conversionCompleted:(BOOL)didComplete;
{
    [textField setStringValue:NSLocalizedString(@"File successfully converted!", @"PS conversion progress message")];
    [progressBar stopAnimation:nil];
    [self setButtonTitle:NSLocalizedString(@"Close", @"Button title") action:@selector(close:)];
}

- (void)conversionStarted;
{
    [progressBar startAnimation:nil];
    [textField setStringValue:[[[self window] title] stringByAppendingEllipsis]];
}

- (void)setButtonTitle:(NSString *)title action:(SEL)action {
    [cancelButton setTitle:title];
    [cancelButton setAction:action];
    SKAutoSizeButtons([NSArray arrayWithObjects:cancelButton, nil], YES);
}

- (BOOL)shouldKeepRunning {
    OSMemoryBarrier();
    return cancelled == 0;
}

#pragma mark PostScript

- (void)doPSConversionWithInfo:(NSDictionary *)info {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    CGDataProviderRef provider = (void *)[info objectForKey:PROVIDER_KEY];
    CGDataConsumerRef consumer = (void *)[info objectForKey:CONSUMER_KEY];
    Boolean success = CGPSConverterConvert(converter, provider, consumer, NULL);
    
    [self stopModalOnMainThread:success];
    
    [pool release];
}    

- (NSData *)PDFDataWithPostScriptData:(NSData *)psData error:(NSError **)outError {
    NSAssert(NULL == converter, @"attempted to reenter SKConversionProgressController, but this is not supported");
    
    fileType = SKPostScriptDocumentType;
    
    convertingPS = 1;
    cancelled = 0;
    
    // pass self as info
    converter = CGPSConverterCreate((void *)self, &SKPSConverterCallbacks, NULL);
    NSAssert(converter != NULL, @"unable to create PS converter");
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)psData);
    
    CFMutableDataRef pdfData = CFDataCreateMutable(CFGetAllocator((CFDataRef)psData), 0);
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData(pdfData);
    
    NSDictionary *dictionary = [NSDictionary dictionaryWithObjectsAndKeys:(id)provider, PROVIDER_KEY, (id)consumer, CONSUMER_KEY, nil];
    
    NSInteger rv = [self runModalSelector:@selector(doPSConversionWithInfo:) withObject:dictionary];
    
    CGDataProviderRelease(provider);
    CGDataConsumerRelease(consumer);
    
    if (rv != SKConversionSucceeded) {
        SKCFDESTROY(pdfData);
        if (outError) {
            if ([self shouldKeepRunning])
                *outError = [NSError errorWithDomain:SKDocumentErrorDomain code:SKReadFileError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Unable to load file", @"Error description"), NSLocalizedDescriptionKey, nil]];
            else
                *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
        }
    }
    
    return [(id)pdfData autorelease];
}

#pragma mark DVI and XDV

+ (NSString *)newToolPath:(NSString *)commandPath supportedTools:(NSArray *)supportedTools {
    NSString *commandName = [commandPath lastPathComponent];
    NSArray *paths = [NSArray arrayWithObjects:@"/usr/texbin", @"/sw/bin", @"/opt/local/bin", @"/usr/local/bin", nil];
    NSInteger i = 0, iMax = [paths count];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSEnumerator *toolEnum = [supportedTools objectEnumerator];
    
    NSAssert1(commandName == nil || [supportedTools containsObject:commandName], @"converter %@ is not supported", commandName);
    if (commandName == nil || [supportedTools containsObject:commandName] == NO)
        commandName = [toolEnum nextObject];
    do {
        i = 0;
        while ([fm isExecutableFileAtPath:commandPath] == NO) {
            if (i >= iMax) {
                commandPath = nil;
                break;
            }
            commandPath = [[paths objectAtIndex:i++] stringByAppendingPathComponent:commandName];
        }
    } while (commandPath == nil && (commandName = [toolEnum nextObject]));
    
    return [commandPath retain];
}

+ (NSString *)dviToolPath {
    static NSString *dviToolPath = nil;
    if (dviToolPath == nil) {
        NSString *commandPath = [[NSUserDefaults standardUserDefaults] stringForKey:SKDviConversionCommandKey];
        NSArray *supportedTools = [NSArray arrayWithObjects:@"dvipdfmx", @"dvipdfm", @"dvipdf", @"dvips", nil];
        dviToolPath = [self newToolPath:commandPath supportedTools:supportedTools];
    }
    return dviToolPath;
}

+ (NSString *)xdvToolPath {
    static NSString *xdvToolPath = nil;
    if (xdvToolPath == nil) {
        NSString *commandPath = [[NSUserDefaults standardUserDefaults] stringForKey:SKXdvConversionCommandKey];
        NSArray *supportedTools = [NSArray arrayWithObjects:@"xdvipdfmx", @"xdv2pdf", nil];
        xdvToolPath = [self newToolPath:commandPath supportedTools:supportedTools];
    }
    return xdvToolPath;
}

- (void)doDVIConversionWithInfo:(NSDictionary *)info {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSString *dviFile = [info objectForKey:INPUTFILE_KEY];
    NSString *commandPath = [info objectForKey:TOOLPATH_KEY];
    NSString *commandName = [commandPath lastPathComponent];
    NSString *tmpDir = SKUniqueTemporaryDirectory();
    BOOL outputPS = [commandName isEqualToString:@"dvips"];
    NSString *outFile = [tmpDir stringByAppendingPathComponent:[dviFile lastPathComponentReplacingPathExtension:outputPS ? @"ps" : @"pdf"]];
    NSArray *arguments = [commandName isEqualToString:@"dvipdf"] ? [NSArray arrayWithObjects:dviFile, outFile, nil] : [NSArray arrayWithObjects:@"-o", outFile, dviFile, nil];
    BOOL success = NO;
    
    NSInvocation *invocation;
    NSFileManager *fm = [[[NSFileManager alloc] init] autorelease];
    
    if ([self shouldKeepRunning] && [fm fileExistsAtPath:dviFile]) {
        NSTask *task = [NSTask launchedTaskWithLaunchPath:commandPath arguments:arguments currentDirectoryPath:[dviFile stringByDeletingLastPathComponent]];
        if (task) {
            invocation = [NSInvocation invocationWithTarget:self selector:@selector(conversionStarted)];
            [invocation performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:NO];
        
            while ([task isRunning] && [self shouldKeepRunning])
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
            if ([task isRunning])
                [task terminate];
            else if ([self shouldKeepRunning])
                success = ([task terminationStatus] == 0);
        }
    }
    
    NSData *outData = success ? [NSData dataWithContentsOfFile:outFile] : nil;
    NSMutableData *pdfData = [info objectForKey:PDFDATA_KEY];
    
    if (outputPS && success) {
        NSAssert(NULL != converter, @"PS converter was not created");
        
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)outData);
        CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((CFMutableDataRef)pdfData);
        
        NSDictionary *dictionary = [NSDictionary dictionaryWithObjectsAndKeys:(id)provider, PROVIDER_KEY, (id)consumer, CONSUMER_KEY, nil];
        
        OSAtomicCompareAndSwap32Barrier(0, 1, (int32_t *)&convertingPS);
        
        [self doPSConversionWithInfo:dictionary];
        
        CGDataProviderRelease(provider);
        CGDataConsumerRelease(consumer);
    } else {
        if (success)
            [pdfData setData:outData];
        
        invocation = [NSInvocation invocationWithTarget:self selector:@selector(conversionCompleted:) argument:&success];
        [invocation performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:NO];
        
        [self stopModalOnMainThread:success];
    }
    
    [fm removeItemAtPath:tmpDir error:NULL];
    
    [pool release];
}

- (NSData *)PDFDataWithDVIFile:(NSString *)dviFile toolPath:(NSString *)toolPath fileType:(NSString *)aFileType error:(NSError **)outError {
    NSAssert(NULL == converter, @"attempted to reenter SKConversionProgressController, but this is not supported");
    
    NSMutableData *pdfData = nil;
    
    fileType = aFileType;
    convertingPS = 0;
    cancelled = 0;
    pdfData = [[NSMutableData alloc] init];
    
    if ([[toolPath lastPathComponent] isEqualToString:@"dvips"]) {
        // create this on the main thread for thread safety, as we may access this ivar from cancel:
        converter = CGPSConverterCreate((void *)self, &SKPSConverterCallbacks, NULL);
        NSAssert(converter != NULL, @"unable to create PS converter");
    }
    
    NSDictionary *dictionary = [NSDictionary dictionaryWithObjectsAndKeys:dviFile, INPUTFILE_KEY, pdfData, PDFDATA_KEY, toolPath, TOOLPATH_KEY, nil];
    
    NSInteger rv = [self runModalSelector:@selector(doDVIConversionWithInfo:) withObject:dictionary];
    
    if (rv != SKConversionSucceeded) {
        SKDESTROY(pdfData);
        if (outError) {
            if ([self shouldKeepRunning])
                *outError = [NSError errorWithDomain:SKDocumentErrorDomain code:SKReadFileError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Unable to load file", @"Error description"), NSLocalizedDescriptionKey, nil]];
            else
                *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
        }
    }
    
    return [pdfData autorelease];
}

@end
