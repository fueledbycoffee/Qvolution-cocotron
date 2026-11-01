#ifndef CGDISPLAYSTREAM_H
#define CGDISPLAYSTREAM_H

/*
 This file is part of Darling.

 Copyright (C) 2025 Darling Developers

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <CoreGraphics/CoreGraphicsExport.h>
#include <CoreFoundation/CoreFoundation.h>

COREGRAPHICS_EXPORT const CFStringRef kCGDisplayStreamShowCursor;

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGDirectDisplay.h>
typedef struct __CGDisplayStream *CGDisplayStreamRef;
typedef struct __CGDisplayStreamUpdate *CGDisplayStreamUpdateRef;
typedef int32_t CGDisplayStreamUpdateRectType;
// ABI-compatible pointer argument; the unsupported backend never invokes it.
#ifdef __BLOCKS__
typedef void (^CGDisplayStreamFrameAvailableHandler)(int32_t, uint64_t, void *, CGDisplayStreamUpdateRef);
#else
typedef void *CGDisplayStreamFrameAvailableHandler;
#endif
COREGRAPHICS_EXPORT const CFStringRef kCGDisplayStreamColorSpace;
COREGRAPHICS_EXPORT const CFStringRef kCGDisplayStreamDestinationRect;
COREGRAPHICS_EXPORT const CFStringRef kCGDisplayStreamMinimumFrameTime;
COREGRAPHICS_EXPORT const CFStringRef kCGDisplayStreamPreserveAspectRatio;
COREGRAPHICS_EXPORT CGDisplayStreamRef CGDisplayStreamCreate(CGDirectDisplayID display, size_t width, size_t height, int32_t pixelFormat, CFDictionaryRef properties, CGDisplayStreamFrameAvailableHandler handler);
COREGRAPHICS_EXPORT CFRunLoopSourceRef CGDisplayStreamGetRunLoopSource(CGDisplayStreamRef stream);
COREGRAPHICS_EXPORT CGError CGDisplayStreamStart(CGDisplayStreamRef stream);
COREGRAPHICS_EXPORT CGError CGDisplayStreamStop(CGDisplayStreamRef stream);
COREGRAPHICS_EXPORT const CGRect *CGDisplayStreamUpdateGetRects(CGDisplayStreamUpdateRef update, CGDisplayStreamUpdateRectType type, size_t *count);

#endif /* CGDISPLAYSTREAM_H */
