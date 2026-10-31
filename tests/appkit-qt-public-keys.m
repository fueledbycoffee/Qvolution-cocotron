#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        const char *names[] = {
            "NSImageHintInterpolation",
            "NSImageHintUserInterfaceLayoutDirection",
            "NSAccessibilityLanguageAttribute",
            "NSAccessibilitySwitchSubrole"
        };
        NSString *expected[] = { nil, nil, @"AXLanguage", @"AXSwitch" };
        unsigned failures = 0;
        for (unsigned index = 0; index < sizeof(names) / sizeof(names[0]); ++index) {
            NSString *const *symbol = dlsym(RTLD_DEFAULT, names[index]);
            if (symbol == NULL || ![*symbol isKindOfClass: [NSString class]] ||
                [*symbol length] == 0) {
                fprintf(stderr, "FAIL: missing NSString export %s\n", names[index]);
                ++failures;
                continue;
            }
            if (expected[index] != nil && ![*symbol isEqualToString: expected[index]]) {
                fprintf(stderr, "FAIL: accessibility wire value %s\n", names[index]);
                ++failures;
            }
            NSString *copy = [*symbol copy];
            NSDictionary *dictionary = [NSDictionary dictionaryWithObject: @1 forKey: *symbol];
            if (![[dictionary objectForKey: copy] isEqual: @1]) {
                fprintf(stderr, "FAIL: dictionary key identity %s\n", names[index]);
                ++failures;
            }
            [copy release];
        }
        if (failures != 0)
            return 1;
        puts("PASS: public Qt image and accessibility NSString keys resolve");
    }
    return 0;
}
