/*------------------------------------------------------------------------
 *
 * Derivative of the OpenVG 1.0.1 Reference Implementation
 * -------------------------------------
 *
 * Copyright (c) 2007 The Khronos Group Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and /or associated documentation files
 * (the "Materials "), to deal in the Materials without restriction,
 * including without limitation the rights to use, copy, modify, merge,
 * publish, distribute, sublicense, and/or sell copies of the Materials,
 * and to permit persons to whom the Materials are furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Materials.
 *
 * THE MATERIALS ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
 * DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
 * OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE MATERIALS OR
 * THE USE OR OTHER DEALINGS IN THE MATERIALS.
 *
 *-------------------------------------------------------------------*/
#import <Onyx2D/O2Paint.h>

@implementation O2Paint

O2PaintRef O2PaintInitWithTransform(O2PaintRef self,
                                    O2AffineTransform transform)
{
    self->m_surfaceToPaintMatrix = transform;
    self->isOpaque = FALSE;
    return self;
}

O2PaintRef O2PaintRetain(O2PaintRef self) {
    return (self != NULL) ? (O2PaintRef) CFRetain(self) : NULL;
}

void O2PaintRelease(O2PaintRef self) {
    if (self != NULL)
        CFRelease(self);
}

@end

@interface O2Paint_alpha : O2Paint {
  @public
    O2Paint *_paint;
    O2Float _alpha;
}
- initWithPaint: (O2Paint *) paint alpha: (O2Float) alpha;
@end

@implementation O2Paint_alpha

static int alpha_argb8u_PRE(O2Paint *paint, int x, int y,
                           O2argb8u *span, int length) {
    O2Paint_alpha *self = (O2Paint_alpha *)paint;
    int chunk = O2PaintReadSpan_argb8u_PRE(self->_paint, x, y, span, length);
    for (int i = 0; i < chunk; i++) {
        span[i].r = O2ByteFromFloat(span[i].r / 255.0 * self->_alpha);
        span[i].g = O2ByteFromFloat(span[i].g / 255.0 * self->_alpha);
        span[i].b = O2ByteFromFloat(span[i].b / 255.0 * self->_alpha);
        span[i].a = O2ByteFromFloat(span[i].a / 255.0 * self->_alpha);
    }
    return chunk;
}

static int alpha_largb32f_PRE(O2Paint *paint, int x, int y,
                             O2argb32f *span, int length) {
    O2Paint_alpha *self = (O2Paint_alpha *)paint;
    int chunk = O2PaintReadSpan_largb32f_PRE(self->_paint, x, y, span, length);
    for (int i = 0; i < chunk; i++)
        span[i] = O2argb32fMultiplyByFloat(span[i], self->_alpha);
    return chunk;
}

- initWithPaint: (O2Paint *) paint alpha: (O2Float) alpha {
    O2PaintInitWithTransform(self, O2AffineTransformIdentity);
    _paint = O2PaintRetain(paint);
    _alpha = alpha;
    _paint_largb8u_PRE = paint->_paint_largb8u_PRE != NULL ? alpha_argb8u_PRE : NULL;
    _paint_largb32f_PRE = alpha_largb32f_PRE;
    return self;
}

- (void) dealloc {
    O2PaintRelease(_paint);
    [super dealloc];
}

@end

O2PaintRef O2PaintCreateWithAlpha(O2PaintRef paint, O2Float alpha) {
    // Same range rule as O2GStateSetAlpha: clamp to [0, 1], NaN is 0.
    if (!(alpha > 0))
        alpha = 0;
    else if (alpha > 1)
        alpha = 1;
    if (alpha == 1)
        return O2PaintRetain(paint);
    return [[O2Paint_alpha alloc] initWithPaint: paint alpha: alpha];
}
