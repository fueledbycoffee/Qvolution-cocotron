#include "../Onyx2D/O2UIFontPolicy.h"
#include <assert.h>
#include <pango/pango.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>

static void parsed(const char *input, const char *expected) {
    char *family = O2UIFontFamilyFromDescription(input);
    assert(family && !strcmp(family, expected));
    PangoFontDescription *pango=pango_font_description_from_string(input);
    assert(!strcmp(pango_font_description_get_family(pango),family));
    pango_font_description_free(pango); free(family);
}
static void choice(FcConfig *config, const char *description, int mono, const char *expected) {
    char *family = O2UIFontChooseFamily(config, description, mono);
    assert(family && !strcmp(family, expected)); free(family);
}
static void addFamily(FcConfig *config, const char *family) {
    /* Synthetic catalog names, never a downloaded/renamed font file. */
    FcPattern *pattern = FcPatternCreate(); assert(pattern);
    assert(FcPatternAddString(pattern, FC_FAMILY, (const FcChar8 *)family));
    assert(FcPatternAddString(pattern, FC_FILE,
        (const FcChar8 *)"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"));
    assert(FcPatternAddInteger(pattern, FC_INDEX, 0));
    assert(FcPatternAddInteger(pattern, FC_WEIGHT, FC_WEIGHT_REGULAR));
    assert(FcFontSetAdd(FcConfigGetFonts(config, FcSetApplication), pattern));
}
static void fakePortal(int ready, const char *text, int nested, int malformed, int persistent) {
    DBusError error; dbus_error_init(&error);
    DBusConnection *bus = dbus_bus_get_private(DBUS_BUS_SESSION, &error); assert(bus);
    dbus_connection_set_exit_on_disconnect(bus,FALSE);
    assert(dbus_bus_request_name(bus, "org.freedesktop.portal.Desktop", 0, &error) == DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER);
    assert(write(ready, "x", 1) == 1); close(ready);
    for (;;) {
        DBusMessage *request = dbus_connection_pop_message(bus);
        if (!request) {
            if (!dbus_connection_read_write(bus, 1000)) break;
            continue;
        }
        if (dbus_message_is_method_call(request, "org.freedesktop.portal.Settings", "Read")) {
            assert(dbus_message_has_path(request, "/org/freedesktop/portal/desktop"));
            assert(dbus_message_has_destination(request, "org.freedesktop.portal.Desktop"));
            assert(dbus_message_has_signature(request, "ss"));
            DBusMessageIter args; const char *space, *key;
            assert(dbus_message_iter_init(request, &args));
            dbus_message_iter_get_basic(&args, &space); assert(!strcmp(space,"org.gnome.desktop.interface"));
            assert(dbus_message_iter_next(&args)); dbus_message_iter_get_basic(&args, &key); assert(!strcmp(key,"font-name"));
            DBusMessage *reply = dbus_message_new_method_return(request);
            DBusMessageIter root, outer, inner;
            dbus_message_iter_init_append(reply, &root);
            dbus_message_iter_open_container(&root, DBUS_TYPE_VARIANT, nested ? "v" : malformed ? "u" : "s", &outer);
            DBusMessageIter *value = &outer;
            if (nested) { dbus_message_iter_open_container(&outer, DBUS_TYPE_VARIANT, malformed ? "u" : "s", &inner); value = &inner; }
            dbus_uint32_t number = 12;
            dbus_message_iter_append_basic(value, malformed ? DBUS_TYPE_UINT32 : DBUS_TYPE_STRING,
                malformed ? (const void *)&number : (const void *)&text);
            if (nested) dbus_message_iter_close_container(&outer, &inner);
            dbus_message_iter_close_container(&root, &outer);
            dbus_connection_send(bus, reply, NULL); dbus_connection_flush(bus);
            dbus_message_unref(reply); dbus_message_unref(request);
            if (!persistent) break;
            continue;
        }
        dbus_message_unref(request);
    }
    dbus_connection_close(bus); dbus_connection_unref(bus); dbus_error_free(&error); _exit(0);
}
static void portalCase(int nested, int malformed) {
    int pipefd[2]; assert(pipe(pipefd) == 0);
    pid_t child = fork(); assert(child >= 0);
    if (!child) { close(pipefd[0]); fakePortal(pipefd[1], "Inter Bold 11", nested, malformed, 0); }
    close(pipefd[1]); char byte; assert(read(pipefd[0], &byte, 1) == 1); close(pipefd[0]);
    char *description = O2UIFontPortalDescription();
    if (malformed) assert(!description); else assert(description && !strcmp(description, "Inter Bold 11"));
    free(description); int status; assert(waitpid(child, &status, 0) == child && status == 0);
}
static void replyCase(int nested, int malformed) {
    DBusMessage *reply=dbus_message_new(DBUS_MESSAGE_TYPE_METHOD_RETURN);
    DBusMessageIter root, outer, inner;
    dbus_message_iter_init_append(reply,&root);
    dbus_message_iter_open_container(&root,DBUS_TYPE_VARIANT,nested?"v":malformed?"u":"s",&outer);
    DBusMessageIter *value=&outer;
    if(nested){dbus_message_iter_open_container(&outer,DBUS_TYPE_VARIANT,malformed?"u":"s",&inner);value=&inner;}
    const char *text="Inter 11"; dbus_uint32_t number=11;
    dbus_message_iter_append_basic(value,malformed?DBUS_TYPE_UINT32:DBUS_TYPE_STRING,malformed?(const void *)&number:(const void *)&text);
    if(nested)dbus_message_iter_close_container(&outer,&inner);
    dbus_message_iter_close_container(&root,&outer);
    char *description=O2UIFontDescriptionFromReply(reply);
    assert(malformed?!description:description&&!strcmp(description,text));
    free(description);dbus_message_unref(reply);
}
static double elapsed(struct timespec start) {
    struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
    return (now.tv_sec - start.tv_sec) + (now.tv_nsec - start.tv_nsec) / 1e9;
}
/* The bus guard: no address means no autolaunch attempt, and a bus that
 * accepts the connection but never answers costs at most the short bound. */
static void busGuardCases(void) {
    DBusMessage *request = O2UIFontPortalReadRequest();
    assert(request && !dbus_message_get_auto_start(request) && dbus_message_has_signature(request, "ss"));
    dbus_message_unref(request);
    char *saved = getenv("DBUS_SESSION_BUS_ADDRESS") ? strdup(getenv("DBUS_SESSION_BUS_ADDRESS")) : NULL;
    unsetenv("DBUS_SESSION_BUS_ADDRESS");
    struct timespec start; clock_gettime(CLOCK_MONOTONIC, &start);
    assert(!O2UIFontOpenSessionBus(O2UI_FONT_BUS_TIMEOUT_MS) && !O2UIFontPortalDescription());
    assert(elapsed(start) < 1);
    char directory[] = "/tmp/qv-silent-bus-XXXXXX"; assert(mkdtemp(directory));
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    snprintf(address.sun_path, sizeof(address.sun_path), "%s/bus", directory);
    int listener = socket(AF_UNIX, SOCK_STREAM, 0);
    if (listener < 0 || bind(listener, (struct sockaddr *)&address, sizeof(address)) || listen(listener, 4)) {
        puts("SKIP silent bus: Unix sockets unavailable here");
    } else {
        char bus[200]; snprintf(bus, sizeof(bus), "unix:path=%s", address.sun_path);
        setenv("DBUS_SESSION_BUS_ADDRESS", bus, 1);
        clock_gettime(CLOCK_MONOTONIC, &start);
        assert(!O2UIFontPortalDescription());
        double seconds = elapsed(start);
        printf("silent-bus seconds=%.3f\n", seconds);
        assert(seconds < 2);
    }
    if (listener >= 0) close(listener);
    unlink(address.sun_path); rmdir(directory);
    if (saved) { setenv("DBUS_SESSION_BUS_ADDRESS", saved, 1); free(saved); }
    else unsetenv("DBUS_SESSION_BUS_ADDRESS");
}
int main(int argc, char **argv) {
    if (argc==4 && !strcmp(argv[1],"--serve")) {
        int ready=open(argv[3],O_WRONLY|O_CREAT|O_EXCL,0600);assert(ready>=0);
        fakePortal(ready,argv[2],1,0,1);
    }
    busGuardCases();
    parsed("Inter 11", "Inter"); parsed("  Noto Sans Bold Italic 11.5  ", "Noto Sans");
    parsed("DejaVu Sans Semi-Bold Condensed 14px", "DejaVu Sans"); parsed("Example Book, 11", "Example Book");
    parsed("Font 42 Family Regular 13", "Font 42 Family"); assert(!O2UIFontFamilyFromDescription(NULL));
    parsed("Cantarell Italic Light 15 @wght=200 #tnum=1", "Cantarell");
    parsed("Noto Sans Ultra-Light Semi-Condensed South 11", "Noto Sans");
    parsed("Noto Sans\tBold\t11", "Noto Sans");
    FcConfig *config = FcConfigCreate(); assert(config);
    assert(FcConfigAppFontAddFile(config, (const FcChar8 *)"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"));
    choice(config, "Missing Family 11", 0, "sans-serif");
    assert(!O2UIFontFamilyInstalled(config, "Inter"));
    addFamily(config,"Noto Sans"); choice(config, NULL, 0, "Noto Sans");
    addFamily(config,"Cantarell"); choice(config, NULL, 0, "Cantarell");
    addFamily(config,"Adwaita Sans"); choice(config, NULL, 0, "Adwaita Sans");
    addFamily(config,"Inter"); choice(config, NULL, 0, "Inter");
    choice(config, "Missing, Cantarell Bold 99", 0, "Cantarell");
    choice(config, "Cantarell Bold 99", 0, "Cantarell"); choice(config, "Absent 11", 0, "Inter");
    choice(config, NULL, 1, "monospace"); addFamily(config,"DejaVu Sans Mono");
    choice(config, "Inter 11", 1, "DejaVu Sans Mono");
    assert(O2UIFontInstallAliases(config,"Inter",0)); assert(O2UIFontInstallAliases(config,"DejaVu Sans Mono",1));
    const char *aliases[]={".AppleSystemUIFont","Helvetica Neue","Helvetica","Lucida Grande","San Francisco","Menlo","Monaco"};
    for (unsigned i=0;i<7;++i) {
        assert(O2UIFontIsAlias(aliases[i]));
        FcPattern *q=FcPatternCreate(); FcPatternAddString(q,FC_FAMILY,(const FcChar8 *)aliases[i]);
        FcConfigSubstitute(config,q,FcMatchPattern); FcDefaultSubstitute(q); FcResult result;
        FcPattern *m=FcFontMatch(config,q,&result); assert(m && O2UIFontPatternHasFamily(m,i<5?"Inter":"DejaVu Sans Mono"));
        FcPatternDestroy(m); FcPatternDestroy(q);
    }
    assert(!O2UIFontIsAlias("Noto Sans"));
    char *escaped=O2UIFontXMLEscape("A & <B> \"C\" 'D'"); assert(!strcmp(escaped,"A &amp; &lt;B&gt; &quot;C&quot; &apos;D&apos;")); free(escaped);
    assert(O2UIFontInstallAliases(config,"A & <B>",0)); FcConfigDestroy(config);
    replyCase(0,0); replyCase(1,0); replyCase(0,1); replyCase(1,1);
    if (argc > 1) { portalCase(0,0); portalCase(1,0); portalCase(1,1); }
    else puts("SKIP live fake portal: use --portal on a host permitting Unix sockets");
    /* Host fonts only; fontconfig/FreeType use the same production family policy. */
    config=FcInitLoadConfigAndFonts(); assert(config);
    char *family=O2UIFontChooseFamily(config,NULL,0); printf("host-ui-family=%s\n",family);
    FcPattern *q=FcPatternCreate(); FcPatternAddString(q,FC_FAMILY,(const FcChar8 *)family);
    FcConfigSubstitute(config,q,FcMatchPattern); FcDefaultSubstitute(q); FcResult result;
    FcPattern *m=FcFontMatch(config,q,&result); assert(m); FcChar8 *file; int index=0;
    assert(FcPatternGetString(m,FC_FILE,0,&file)==FcResultMatch); FcPatternGetInteger(m,FC_INDEX,0,&index);
    FT_Library library; FT_Face face; assert(!FT_Init_FreeType(&library)); assert(!FT_New_Face(library,(const char *)file,index,&face));
    for(int scale=1;scale<=2;++scale) {
        assert(!FT_Set_Pixel_Sizes(face,0,13*scale)); assert(!FT_Load_Char(face,'H',FT_LOAD_RENDER));
        double height=face->glyph->bitmap.rows/(double)scale;
        printf("H-raster scale=%d height=%.1f\n",scale,height); assert(height>=8 && height<=10);
    }
    FT_Done_Face(face); FT_Done_FreeType(library); FcPatternDestroy(m); FcPatternDestroy(q); free(family); FcConfigDestroy(config);
    puts("PASS production policy: bus guard (no autolaunch, no autostart, bounded silent bus), portal variants/types, exact families, fallback order, aliases, XML, host H cap pixels (native; no AppKit acceptance)");
    return 0;
}
