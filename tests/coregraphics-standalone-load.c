/* Our full-framework load regression. Link only libSystem, run one path per
 * fresh process; no preloaded HIServices or ApplicationServices may mask a bind.
 * SPEC.md Round 3: the CPS public-sibling bridge must preserve the status and
 * caller storage. This observes our staged builds, never Apple implementation. */
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct { uint32_t highLongOfPSN, lowLongOfPSN; } Serial;
typedef int16_t (*Current)(Serial *);
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL %d: %s\n", __LINE__, #x); return 1; } } while (0)
int main(int argc, char **argv) {
    setbuf(stdout, NULL);
    printf("LOAD entered main, pointer bits=%u\n", (unsigned)(8 * sizeof(void *)));
    CHECK(argc == 2);
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        const char *name = _dyld_get_image_name(i);
        CHECK(name != NULL);
        CHECK(strstr(name, "/HIServices.framework/") == NULL);
        CHECK(strstr(name, "/CoreGraphics.framework/") == NULL);
        CHECK(strstr(name, "/libswiftCoreGraphicsImports.dylib") == NULL);
    }
    printf("LOAD before dlopen: %s\n", argv[1]);
    void *image = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!image) fprintf(stderr, "load failure: %s\n", dlerror());
    CHECK(image != NULL);
    puts("LOAD requested image opened");
    void *core = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW | RTLD_LOCAL);
    CHECK(core != NULL);
    Current cps = (Current)dlsym(core, "CPSGetCurrentProcess");
    CHECK(cps != NULL);
    puts("LOAD CPS symbol resolved; before null call");
    CHECK(cps(NULL) == -50);
    puts("LOAD null call passed; before identity call");
    struct { uint32_t before; Serial psn; uint32_t after; } out = {0x12345678, {3,4}, 0x87654321};
    int16_t status = cps(&out.psn);
    printf("LOAD identity returned status=%d\n", (int)status);
    void *publicImage = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_NOW | RTLD_LOCAL);
    CHECK(publicImage != NULL);
    Current publicCurrent = (Current)dlsym(publicImage, "GetCurrentProcess");
    CHECK(publicCurrent != NULL);
    puts("LOAD public sibling resolved; before public identity call");
    Serial actual;
    CHECK(publicCurrent(&actual) == status);
    if (status == 0) CHECK(out.psn.highLongOfPSN == actual.highLongOfPSN && out.psn.lowLongOfPSN == actual.lowLongOfPSN);
    else CHECK(out.psn.highLongOfPSN == 3 && out.psn.lowLongOfPSN == 4);
    CHECK(out.before == 0x12345678 && out.after == 0x87654321);
    puts("LOAD bridge contract passed; before closing images");
    CHECK(dlclose(publicImage) == 0);
    CHECK(dlclose(core) == 0);
    CHECK(dlclose(image) == 0);
    printf("PASS standalone load and CPS sibling contract: %s\n", argv[1]);
    return 0;
}
