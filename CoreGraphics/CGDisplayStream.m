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

#import <CoreGraphics/CGDisplayStream.h>

const CFStringRef kCGDisplayStreamShowCursor = CFSTR("kCGDisplayStreamShowCursor");

// GUESS: opaque key bytes are undocumented; match the existing ShowCursor
// token convention. Stream creation fails, so no backend interprets these keys.
const CFStringRef kCGDisplayStreamColorSpace = CFSTR("kCGDisplayStreamColorSpace");
const CFStringRef kCGDisplayStreamDestinationRect = CFSTR("kCGDisplayStreamDestinationRect");
const CFStringRef kCGDisplayStreamMinimumFrameTime = CFSTR("kCGDisplayStreamMinimumFrameTime");
const CFStringRef kCGDisplayStreamPreserveAspectRatio = CFSTR("kCGDisplayStreamPreserveAspectRatio");
CGDisplayStreamRef CGDisplayStreamCreate(CGDirectDisplayID display, size_t width,
    size_t height, int32_t pixelFormat, CFDictionaryRef properties,
    CGDisplayStreamFrameAvailableHandler handler) { return NULL; }
CFRunLoopSourceRef CGDisplayStreamGetRunLoopSource(CGDisplayStreamRef stream) { return NULL; }
CGError CGDisplayStreamStart(CGDisplayStreamRef stream)
{ return stream ? kCGErrorNotImplemented : kCGErrorIllegalArgument; }
CGError CGDisplayStreamStop(CGDisplayStreamRef stream)
{ return stream ? kCGErrorNotImplemented : kCGErrorIllegalArgument; }
const CGRect *CGDisplayStreamUpdateGetRects(CGDisplayStreamUpdateRef update,
    CGDisplayStreamUpdateRectType type, size_t *count)
{
    if (count) *count = 0;
    return NULL;
}
