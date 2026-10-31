/* Copyright (c) 2026 Qvolution contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/NSAccessibilityCustomAction.h>
#import <objc/runtime.h>

@implementation NSAccessibilityCustomAction

@synthesize name = _name;
@synthesize handler = _handler;
@synthesize selector = _selector;

- (instancetype)initWithName:(NSString *)name handler:(BOOL (^)(void))handler {
    self = [super init];
    if (self != nil) {
        @try {
            _name = [name copy];
            _handler = [handler copy];
        } @catch (id exception) {
            [self release];
            @throw;
        }
    }
    return self;
}

- (instancetype)initWithName:(NSString *)name
                      target:(id<NSObject>)target selector:(SEL)selector {
    self = [super init];
    if (self != nil) {
        @try {
            _name = [name copy];
            objc_storeWeak(&_target, target);
            _selector = selector;
        } @catch (id exception) {
            [self release];
            @throw;
        }
    }
    return self;
}

- (id<NSObject>)target {
    return objc_loadWeak(&_target);
}

- (void)setTarget:(id<NSObject>)target {
    objc_storeWeak(&_target, target);
}

- (void)dealloc {
    objc_storeWeak(&_target, nil);
    [_name release];
    [_handler release];
    [super dealloc];
}

@end
