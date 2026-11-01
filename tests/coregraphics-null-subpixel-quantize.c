/* Rung 4: Chess supplies NULL to this entry point on Stage41c3.
 * GUESS (rung 6): treating that input as a silent no-op is conservative;
 * the native harness does not establish macOS behavior.
 */
#include <stdbool.h>
#include <stdio.h>

#ifdef NATIVE_FUNCTIONS
#include NATIVE_FUNCTIONS
#else
#include <CoreGraphics/CGContext.h>
#endif

int main(void)
{
    CGContextSetShouldSubpixelQuantizeFonts(NULL, false);
    CGContextSetShouldSubpixelQuantizeFonts(NULL, true);

#ifdef NATIVE_FUNCTIONS
    if (stateAccesses != 0) {
        fputs("FAIL: NULL context reached the graphics state\n", stderr);
        return 1;
    }
    struct NativeState state = {false};
    struct NativeContext context = {&state};
    CGContextSetShouldSubpixelQuantizeFonts(&context, true);
    if (!state._shouldSubpixelQuantizeFonts || stateAccesses != 1)
        return 1;
    CGContextSetShouldSubpixelQuantizeFonts(&context, false);
    if (state._shouldSubpixelQuantizeFonts || stateAccesses != 2)
        return 1;
#endif

    puts("PASS: NULL subpixel quantization calls returned");
    return 0;
}
