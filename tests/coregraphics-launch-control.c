/* Trivial launch control: no framework, loader API, or CPS references. */
#include <stdio.h>

int main(void) {
    printf("PASS trivial launch, pointer bits=%u\n", (unsigned)(8 * sizeof(void *)));
    return 0;
}
