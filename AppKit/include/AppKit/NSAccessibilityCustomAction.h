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

#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSAccessibilityCustomAction : NSObject {
@private
    NSString *_name;
    BOOL (^_handler)(void);
    id _target;
    SEL _selector;
}

- (instancetype)initWithName:(NSString *)name
                     handler:(BOOL (^ _Nullable)(void))handler;
- (instancetype)initWithName:(NSString *)name
                      target:(id<NSObject>)target selector:(SEL)selector;

@property(copy) NSString *name;
@property(copy, nullable) BOOL (^handler)(void);
@property(weak, nullable) id<NSObject> target;
@property(nullable) SEL selector;

@end

NS_ASSUME_NONNULL_END
