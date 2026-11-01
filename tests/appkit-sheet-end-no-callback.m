// Ending a sheet whose didEnd callback is absent.
//
// -[NSApplication beginSheet:modalForWindow:modalDelegate:didEndSelector:contextInfo:]
// documents the delegate and the selector as optional: with a nil delegate or
// a NULL selector the sheet simply ends and nothing is sent. The fixture ends
// sheets begun with each combination and checks that no exception is raised,
// that the sheet is detached and hidden, and that a callback that is present is
// still delivered with the sheet, the return code and the context info.
#import <AppKit/AppKit.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int checks;
static int failures;

#define CHECK(condition, ...)                                                  \
    do {                                                                       \
        checks++;                                                              \
        if (!(condition)) {                                                    \
            failures++;                                                        \
            printf("FAIL line %d: ", __LINE__);                                \
            printf(__VA_ARGS__);                                               \
            printf("\n");                                                      \
        }                                                                      \
    } while (0)

@interface Recorder : NSObject {
  @public
    int calls;
    NSWindow *sheet;
    NSInteger code;
    void *info;
}
- (void) sheetDidEnd: (NSWindow *) endedSheet
          returnCode: (NSInteger) returnCode
         contextInfo: (void *) contextInfo;
@end

@implementation Recorder
- (void) sheetDidEnd: (NSWindow *) endedSheet
          returnCode: (NSInteger) returnCode
         contextInfo: (void *) contextInfo
{
    calls++;
    sheet = endedSheet;
    code = returnCode;
    info = contextInfo;
}
@end

static NSWindow *newWindow(void) {
    NSWindow *window = [[NSWindow alloc]
            initWithContentRect: NSMakeRect(0, 0, 300, 200)
                      styleMask: NSTitledWindowMask
                        backing: NSBackingStoreBuffered
                          defer: NO];
    [window orderFront: nil];
    return window;
}

static NSWindow *newSheet(void) {
    return [[NSPanel alloc] initWithContentRect: NSMakeRect(0, 0, 200, 80)
                                      styleMask: NSTitledWindowMask
                                        backing: NSBackingStoreBuffered
                                          defer: NO];
}

// Ends |sheet| with -[NSApplication endSheet:returnCode:] and reports whether it raised.
static BOOL endRaised(NSWindow *sheet, NSInteger returnCode, const char *label) {
    @try {
        [NSApp endSheet: sheet returnCode: returnCode];
    } @catch (NSException *exception) {
        printf("  %s raised %s: %s\n", label, [[exception name] UTF8String],
               [[exception reason] UTF8String]);
        return YES;
    }
    return NO;
}

// One attached sheet ended with the given delegate and selector.
static void attachedCase(const char *label, id delegate, SEL selector, void *info) {
    NSWindow *parent = newWindow();
    NSWindow *sheet = newSheet();
    [NSApp beginSheet: sheet
            modalForWindow: parent
             modalDelegate: delegate
            didEndSelector: selector
               contextInfo: info];
    CHECK([parent attachedSheet] == sheet, "%s: sheet not attached after begin", label);
    CHECK(!endRaised(sheet, 5, label), "%s: endSheet:returnCode: raised", label);
    CHECK([parent attachedSheet] == nil, "%s: sheet still attached after end", label);
    CHECK(![sheet isVisible], "%s: sheet still visible after end", label);
    [parent close];
}

static void stopAfterModalSession(void) {
    [NSApp postEvent: [NSEvent otherEventWithType: NSApplicationDefined location: NSZeroPoint
                                     modifierFlags: 0 timestamp: 0 windowNumber: 0
                                           context: nil subtype: 0 data1: 0 data2: 0]
             atStart: YES];
}

@interface ModalStopper : NSObject {
  @public
    BOOL abort;
}
@end
@implementation ModalStopper
- (void) fire: (NSTimer *) timer {
    if (abort)
        [NSApp abortModal];
    else
        [NSApp stopModal];
    stopAfterModalSession();
}
@end

static const char *volatile stalledMessage;
static void stalled(int signal) {
    write(STDERR_FILENO, stalledMessage, strlen(stalledMessage));
    _exit(1);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        signal(SIGALRM, stalled);
        stalledMessage = "FAIL: sheet-end fixture stalled\n";
        alarm(60);

        Recorder *recorder = [[Recorder alloc] init];
        SEL didEnd = @selector(sheetDidEnd:returnCode:contextInfo:);

        // nil delegate, NULL selector: the case in the bug report.
        attachedCase("nil delegate, NULL selector", nil, NULL, NULL);
        // nil delegate with a selector, and a delegate with no selector.
        attachedCase("nil delegate, selector", nil, didEnd, NULL);
        attachedCase("delegate, NULL selector", recorder, NULL, NULL);
        CHECK(recorder->calls == 0, "delegate with a NULL selector was called %d times", recorder->calls);

        // A callback that is present is still delivered exactly once.
        {
            int token = 0;
            NSWindow *parent = newWindow();
            NSWindow *sheet = newSheet();
            [NSApp beginSheet: sheet
                    modalForWindow: parent
                     modalDelegate: recorder
                    didEndSelector: didEnd
                       contextInfo: &token];
            CHECK(!endRaised(sheet, 7, "delegate, selector"), "delegate, selector: endSheet:returnCode: raised");
            CHECK(recorder->calls == 1, "delegate, selector: %d calls, expected 1", recorder->calls);
            CHECK(recorder->sheet == sheet, "delegate, selector: wrong sheet");
            CHECK(recorder->code == 7, "delegate, selector: return code %ld, expected 7", (long) recorder->code);
            CHECK(recorder->info == &token, "delegate, selector: wrong context info");
            CHECK([parent attachedSheet] == nil && ![sheet isVisible], "delegate, selector: sheet not closed");
            [parent close];
        }

        // -endSheet: without a return code takes the same path.
        {
            NSWindow *parent = newWindow();
            NSWindow *sheet = newSheet();
            [NSApp beginSheet: sheet modalForWindow: parent modalDelegate: nil didEndSelector: NULL contextInfo: NULL];
            BOOL raised = NO;
            @try {
                [NSApp endSheet: sheet];
            } @catch (NSException *exception) {
                raised = YES;
                printf("  endSheet: raised %s: %s\n", [[exception name] UTF8String], [[exception reason] UTF8String]);
            }
            CHECK(!raised, "-endSheet: raised");
            CHECK([parent attachedSheet] == nil && ![sheet isVisible], "-endSheet: sheet not closed");
            [parent close];
        }

        // A sheet with no parent window is ended through the other branch.
        {
            NSWindow *sheet = newSheet();
            [NSApp beginSheet: sheet modalForWindow: nil modalDelegate: nil didEndSelector: NULL contextInfo: NULL];
            CHECK(!endRaised(sheet, 0, "no parent window"), "no parent window: endSheet:returnCode: raised");
            CHECK(![sheet isVisible], "no parent window: sheet still visible");
            [sheet close];
        }

        // -[NSWindow beginSheet:completionHandler:] with and without a handler.
        {
            NSWindow *parent = newWindow();
            NSWindow *sheet = newSheet();
            [parent beginSheet: sheet completionHandler: nil];
            BOOL raised = NO;
            @try {
                [parent endSheet: sheet returnCode: 3];
            } @catch (NSException *exception) {
                raised = YES;
                printf("  nil completion handler raised %s\n", [[exception name] UTF8String]);
            }
            CHECK(!raised, "completion handler nil: endSheet:returnCode: raised");
            CHECK([parent attachedSheet] == nil && ![sheet isVisible], "completion handler nil: sheet not closed");

            __block NSInteger received = -1;
            [parent beginSheet: sheet completionHandler: ^(NSInteger code) { received = code; }];
            [parent endSheet: sheet returnCode: 4];
            CHECK(received == 4, "completion handler got %ld, expected 4", (long) received);
            CHECK([parent attachedSheet] == nil && ![sheet isVisible], "completion handler: sheet not closed");
            [parent close];
        }

        // NSAlert as a sheet, with no delegate and no selector.
        {
            NSWindow *parent = newWindow();
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText: @"No callback"];
            [alert beginSheetModalForWindow: parent modalDelegate: nil didEndSelector: NULL contextInfo: NULL];
            NSWindow *sheet = [parent attachedSheet];
            CHECK(sheet != nil, "alert: no attached sheet");
            CHECK(!endRaised(sheet, NSAlertFirstButtonReturn, "alert"), "alert: endSheet:returnCode: raised");
            CHECK([parent attachedSheet] == nil, "alert: sheet still attached");
            [parent close];
        }

        // NSSavePanel as a sheet with a nil completion handler.
        {
            NSWindow *parent = newWindow();
            NSSavePanel *panel = [NSSavePanel savePanel];
            [panel beginSheetModalForWindow: parent completionHandler: nil];
            CHECK([parent attachedSheet] == panel, "save panel: not attached");
            CHECK(!endRaised(panel, NSFileHandlingPanelCancelButton, "save panel"), "save panel: endSheet:returnCode: raised");
            CHECK([parent attachedSheet] == nil, "save panel: sheet still attached");
            [parent close];
        }

        // Modal sessions: ending one with no session running is silent, and
        // stop and abort return their codes.
        {
            BOOL raised = NO;
            @try {
                [NSApp stopModal];
                [NSApp abortModal];
            } @catch (NSException *exception) {
                raised = YES;
            }
            CHECK(!raised, "stopModal/abortModal with no session raised");

            for (int pass = 0; pass < 2; pass++) {
                ModalStopper *stopper = [[ModalStopper alloc] init];
                stopper->abort = pass == 1;
                NSWindow *window = newWindow();
                NSTimer *timer = [NSTimer timerWithTimeInterval: 0.2 target: stopper selector: @selector(fire:)
                                                       userInfo: nil repeats: NO];
                [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSModalPanelRunLoopMode];
                NSInteger result = [NSApp runModalForWindow: window];
                NSInteger expected = pass == 1 ? NSRunAbortedResponse : NSRunStoppedResponse;
                CHECK(result == expected, "runModalForWindow pass %d returned %ld, expected %ld", pass, (long) result, (long) expected);
                [window close];
            }
        }

        alarm(0);
        printf("RESULT sheet-end failures=%d checks=%d\n", failures, checks);
        return failures == 0 ? 0 : 1;
    }
}
