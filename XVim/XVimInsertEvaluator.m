//
//  XVimInsertEvaluator.m
//  XVim
//
//  Created by Shuichiro Suzuki on 3/1/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "XVimInsertEvaluator.h"
#import "XVimSourceView.h"
#import "XVimSourceView+Vim.h"
#import "XVimSourceView+Xcode.h"
#import "XVimWindow.h"
#import "XVim.h"
#import "Logger.h"
#import "XVimKeyStroke.h"
#import "XVimKeymapProvider.h"
#import "XVimVisualEvaluator.h"
#import "XVimDeleteEvaluator.h"
#import "XVimMark.h"
#import "XVimMarks.h"
#import "XVimNormalEvaluator.h"

@interface XVimInsertEvaluator()
@property (nonatomic) NSRange startRange;
@property (nonatomic) BOOL movementKeyPressed;
@property (nonatomic, strong) NSString *lastInsertedText;
@property (nonatomic, readonly, strong) NSArray *cancelKeys;
@property (nonatomic, readonly, strong) NSArray *movementKeys;
@property (nonatomic) BOOL enoughBufferForReplace;
@end

@implementation XVimInsertEvaluator{
    BOOL _insertedEventsAbort;
    NSMutableArray* _insertedEvents;
    BOOL _oneCharMode;
}

@synthesize startRange = _startRange;
@synthesize cancelKeys = _cancelKeys;
@synthesize movementKeys = _movementKeys;
@synthesize lastInsertedText = _lastInsertedText;
@synthesize movementKeyPressed = _movementKeyPressed;
@synthesize enoughBufferForReplace = _enoughBufferForReplace;


- (id)initWithWindow:(XVimWindow *)window{
    return [self initWithWindow:window oneCharMode:NO];
}

- (id)initWithWindow:(XVimWindow*)window oneCharMode:(BOOL)oneCharMode{
    self = [super initWithWindow:window];
    if (self) {
        _lastInsertedText = [@"" retain];
        _oneCharMode = oneCharMode;
        _movementKeyPressed = NO;
        _insertedEventsAbort = NO;
        _enoughBufferForReplace = YES;
        _cancelKeys = [[NSArray alloc] initWithObjects:
                       [NSValue valueWithPointer:@selector(ESC:)],
                       [NSValue valueWithPointer:@selector(C_LSQUAREBRACKET:)],
                       [NSValue valueWithPointer:@selector(C_c:)],
                       nil];
        _movementKeys = [[NSArray alloc] initWithObjects:
                         [NSValue valueWithPointer:@selector(Up:)],
                         [NSValue valueWithPointer:@selector(Down:)],
                         [NSValue valueWithPointer:@selector(Left:)],
                         [NSValue valueWithPointer:@selector(Right:)],
                         nil];
    }
    return self;
}

- (void)dealloc
{
    [_lastInsertedText release];
    [_cancelKeys release];
    [_movementKeys release];
    [super dealloc];
}

- (NSString*)modeString{
	return @"-- INSERT --";
}
- (XVIM_MODE)mode{
    return MODE_INSERT;
}

- (void)becameHandler{
    [super becameHandler];
    self.startRange = [[self sourceView] selectedRange];
    [self.sourceView insert];
}

- (XVimEvaluator*)handleMouseEvent:(NSEvent*)event{
	NSRange range = [[self sourceView] selectedRange];
	return range.length == 0 ? self : [[[XVimVisualEvaluator alloc] initWithWindow:self.window mode:MODE_CHARACTER withRange:range] autorelease];
}

- (float)insertionPointHeightRatio{
    if(_oneCharMode){
        return 0.25;
    }
    return 1.0;
}

- (float)insertionPointWidthRatio{
    if(_oneCharMode){
        return 1.0;
    }
    return 0.15;
}

- (float)insertionPointAlphaRatio{
    if(_oneCharMode){
        return 0.5;
    }
    return 1.0;
}

- (NSRange)restrictSelectedRange:(NSRange)range{
	return range;
}

- (XVimKeymap*)selectKeymapWithProvider:(id<XVimKeymapProvider>)keymapProvider{
	return [keymapProvider keymapForMode:MODE_INSERT];
}

- (NSString*)getInsertedText{
    XVimSourceView* view = [self sourceView];
    NSUInteger startLoc = self.startRange.location;
    NSUInteger endLoc = [view selectedRange].location;
    NSRange textRange = NSMakeRange(NSNotFound, 0);
    
    if( [[view string] length] == 0 ){
        return @"";
    }
    // If some text are deleted while editing startLoc could be out of range of the view's string.
    if( ( startLoc >= [[view string] length] ) ){
        startLoc = [[view string] length] - 1;
    }
    
    // Is this really what we want to do?
    // This means just moving cursor forward or backward and escape from insert mode generates the inserted test this method return.
    //    -> The answer is 'OK'. see onMovementKeyPressed: method how it treats the inserted text.
    if (endLoc > startLoc ){
        textRange = NSMakeRange(startLoc, endLoc - startLoc);
    }else{
        textRange = NSMakeRange(endLoc , startLoc - endLoc);
    }
    
    NSString *text = [[view string] substringWithRange:textRange];
    return text;
    
}

/*
- (void)recordTextIntoRegister:(XVimRegister*)xregister{
    NSString *text = [self getInsertedText];
    if (text.length > 0){
        [xregister appendText:text];
    }
}
 */

- (void)onMovementKeyPressed{
    // TODO: we also have to handle when cursor is movieng by mouse clicking.
    //       it should have the same effect on movementKeyPressed property.
    _insertedEventsAbort = YES;
    if (!self.movementKeyPressed){
        self.movementKeyPressed = YES;
        
        // Store off any needed text
        self.lastInsertedText = [self getInsertedText];
        //[self recordTextIntoRegister:[XVim instance].recordingRegister];
    }
    
    // Store off the new start range
    self.startRange = [[self sourceView] selectedRange];
}

- (void)didEndHandler{
    [super didEndHandler];
	XVimSourceView *sourceView = [self sourceView];
	
    if( !_insertedEventsAbort && !_oneCharMode ){
        NSString *text = [self getInsertedText];
        for( int i = 0 ; i < [self numericArg]-1; i++ ){
            [sourceView insertText:text];
        }
    }
    
    // Store off any needed text
    XVim *xvim = [XVim instance];
    [xvim fixRepeatCommand];
    if( _oneCharMode ){

    }else if (!self.movementKeyPressed){
        //[self recordTextIntoRegister:xvim.recordingRegister];
        //[self recordTextIntoRegister:xvim.repeatRegister];
    }else if(self.lastInsertedText.length > 0){
        //[xvim.repeatRegister appendText:self.lastInsertedText];
    }
    [sourceView hideCompletions];
	
    NSUInteger pos = self.sourceView.insertionPoint;
    XVimMark* mark = XVimMakeMark([self.sourceView lineNumber:pos], [self.sourceView columnNumber:pos], self.sourceView.documentURL.path);
    [[XVim instance].marks setMark:mark forName:@"^"];
    mark = XVimMakeMark([self.sourceView lineNumber:pos], [self.sourceView columnNumber:pos], self.sourceView.documentURL.path);
    [[XVim instance].marks setMark:mark forName:@"."];
}

- (BOOL)windowShouldReceive:(SEL)keySelector {
  BOOL b = YES ^ ([NSStringFromSelector(keySelector) isEqualToString:@"C_e:"] ||
                  [NSStringFromSelector(keySelector) isEqualToString:@"C_y:"]);
  return b;
}

- (XVimEvaluator*)eval:(XVimKeyStroke*)keyStroke{
    XVimEvaluator *nextEvaluator = self;
    SEL keySelector = [keyStroke selectorForInstance:self];
    if (keySelector){
        nextEvaluator = [self performSelector:keySelector];
    }else if(self.movementKeyPressed){
        // Flag movement key as not pressed until the next movement key is pressed
        self.movementKeyPressed = NO;
        
        // Store off the new start range
        self.startRange = [[self sourceView] selectedRange];
    }
    
    if (nextEvaluator == self && nil == keySelector){
        NSEvent *event = [keyStroke toEventwithWindowNumber:0 context:nil];
        if (_oneCharMode) {
            // check buffer limit
            XVimSourceView *view = [self sourceView];
            NSUInteger loc = [view selectedRange].location;
            if( [[view string] length] < loc + [self numericArg] ){
                _enoughBufferForReplace = FALSE;
            } else {
                // r command effect is in one line.
                for( NSUInteger i = loc; i <= loc + [self numericArg]-1; ++i ){
                    unichar uc = [[view string] characterAtIndex:i];
                    if( [[NSCharacterSet newlineCharacterSet] characterIsMember:uc] ){
                        _enoughBufferForReplace = FALSE;
                    }
                }
            }
            if( _enoughBufferForReplace ){
                NSRange save = [[self sourceView] selectedRange];
                for (NSUInteger i = 0; i < [self numericArg]; ++i) {
                    [[self sourceView] deleteForward];
                    [[self sourceView] passThroughKeyDown:event];
                    
                    save.location += 1;
                    [[self sourceView] setSelectedRange:save];
                }
                save.location -= 1;
                [[self sourceView] setSelectedRange:save];
            }
            nextEvaluator = nil;
        } else if ([self windowShouldReceive:keySelector]) {
            // Here we pass the key input to original text view.
            // The input coming to this method is already handled by "Input Method"
            // and the input maight be non ascii like 'あ'
            if( keyStroke.modifier == 0 && isPrintable(keyStroke.character)){
                [self.sourceView.view insertText:keyStroke.xvimString];
            }else{
                [[[self sourceView] view] interpretKeyEvents:[NSArray arrayWithObject:event]];
            }
        }
    }
    return nextEvaluator;
}

- (XVimEvaluator*)C_o{
    self.onChildCompleteHandler = @selector(onC_oComplete:);
    return [[[XVimNormalEvaluator alloc] initWithWindow:self.window] autorelease];
}

- (XVimEvaluator*)onC_oComplete:(XVimEvaluator*)childEvaluator{
    self.onChildCompleteHandler = nil;
    return self;
}

- (XVimEvaluator*)ESC{
    [[self sourceView] escapeFromInsert];
    return nil;
}

- (XVimEvaluator*)C_LSQUAREBRACKET{
    return [self ESC];
}

- (XVimEvaluator*)C_c{
    return [self ESC];
}

- (void)C_yC_eHelper:(BOOL)handlingC_y {
    NSUInteger currentCursorIndex = [[self sourceView] selectedRange].location;
    NSUInteger currentColumnIndex = [[self sourceView] columnNumber:currentCursorIndex];
    NSUInteger newCharIndex;
    if (handlingC_y) {
        newCharIndex = [[self  sourceView] prevLine:currentCursorIndex column:currentColumnIndex count:[self numericArg] option:MOTION_OPTION_NONE];
    } else {
        newCharIndex = [[self sourceView] nextLine:currentCursorIndex column:currentColumnIndex count:[self numericArg] option:MOTION_OPTION_NONE];
    }
    NSUInteger newColumnIndex = [[self sourceView] columnNumber:newCharIndex];
    NSLog(@"Old column: %ld\tNew column: %ld", currentColumnIndex, newColumnIndex);
    if (currentColumnIndex == newColumnIndex) {
        unichar u = [[[self sourceView] string] characterAtIndex:newCharIndex];
        NSString *charToInsert = [NSString stringWithFormat:@"%c", u];
        [[self sourceView] insertText:charToInsert];
    }
}

- (XVimEvaluator*)C_y{
    [self C_yC_eHelper:YES];
    return self;
}

- (XVimEvaluator*)C_e{
    [self C_yC_eHelper:NO];
    return self;
}

- (XVimEvaluator*)C_w{
    XVimMotion* m = XVIM_MAKE_MOTION(MOTION_WORD_BACKWARD, CHARACTERWISE_EXCLUSIVE, MOTION_OPTION_NONE, 1);
    [[self sourceView] delete:m];
    return self;
}

- (XVimRegisterOperation)shouldRecordEvent:(XVimKeyStroke*)keyStroke inRegister:(XVimRegister*)xregister{
    // Do not record key strokes for insert. Instead we will directly append the inserted text into the register.
    /*
    NSValue *keySelector = [NSValue valueWithPointer:[keyStroke selectorForInstance:self]];
    if ([self.cancelKeys containsObject:keySelector]){
        return REGISTER_APPEND;
    }else if (xregister.isReadOnly == NO && ([self.movementKeys containsObject:keySelector] || _oneCharMode)){
        return REGISTER_APPEND;
    }else if (xregister.isRepeat && _oneCharMode){
        return REGISTER_APPEND;
    }
     */
    
    return REGISTER_IGNORE;
}

@end
