/* Launch/load controls for OUR stage images. No CPS contract is required of
 * the unmodified stage. Run in a fresh process before replacing either image. */
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    setbuf(stdout, NULL);
    printf("CONTROL entered main, pointer bits=%u\n", (unsigned)(8 * sizeof(void *)));
    if (argc != 2) return 64;
    if (!strcmp(argv[1], "--trivial")) {
        puts("PASS trivial launch");
        return 0;
    }
    printf("CONTROL before dlopen: %s\n", argv[1]);
    void *image = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!image) {
        fprintf(stderr, "FAIL control dlopen: %s\n", dlerror());
        return 1;
    }
    puts("CONTROL dlopen returned");
    if (dlclose(image)) return 1;
    puts("PASS load-only control");
    return 0;
}
