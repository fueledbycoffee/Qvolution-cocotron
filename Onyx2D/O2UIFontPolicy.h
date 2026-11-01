/* Qvolution UI policy. Public portal Settings/fontconfig contracts; no vendor assets. */
#ifndef O2_UI_FONT_POLICY_H
#define O2_UI_FONT_POLICY_H
#include <fontconfig/fontconfig.h>
#include <dbus/dbus.h>
#include <ctype.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <time.h>

static int O2UIFontStyleWord(const char *word) {
    static const char *styles[] = {"thin", "ultralight", "extralight", "light",
        "semilight", "demilight", "book", "regular", "normal", "roman", "medium",
        "semibold", "demibold", "bold", "ultrabold", "extrabold", "heavy", "black",
        "ultrablack", "extrablack", "italic", "oblique", "ultracondensed",
        "extracondensed", "condensed", "semicondensed", "semiexpanded", "expanded",
        "extraexpanded", "ultraexpanded", "smallcaps", "allsmallcaps", "petitecaps",
        "allpetitecaps", "unicase", "titlecaps", "notrotated", "south", "upsidedown",
        "north", "rotatedleft", "east", "rotatedright", "west", "withcolor", "withoutcolor"};
    char normalized[64]; size_t length = 0;
    for (; *word; ++word) {
        if (*word == '-') continue;
        if (length + 1 >= sizeof(normalized)) return 0;
        normalized[length++] = tolower((unsigned char)*word);
    }
    normalized[length] = 0;
    for (size_t i = 0; i < sizeof(styles) / sizeof(styles[0]); ++i)
        if (!strcmp(normalized, styles[i])) return 1;
    return 0;
}

/* Pango description suffixes are styles followed by an optional point/px size.
 * A trailing comma explicitly separates a family ending in a style word. */
static char *O2UIFontFamilyFromDescription(const char *description) {
    if (!description || !description[0] || strlen(description) > 4096) return NULL;
    char *family = strdup(description);
    if (!family) return NULL;
    size_t length = strlen(family);
    while (length && isspace((unsigned char)family[length - 1])) family[--length] = 0;
    /* Ignore variation/feature suffixes, whose geometry is not a UI setting. */
    for (;;) {
        char *word = family + strlen(family);
        while (word > family && !isspace((unsigned char)word[-1])) --word;
        if (*word != '@' && *word != '#') break;
        *word = 0;
        length = strlen(family);
        while (length && isspace((unsigned char)family[length - 1])) family[--length] = 0;
    }
    char *word = family + strlen(family);
    while (word > family && !isspace((unsigned char)word[-1])) --word;
    char *end;
    double size = strtod(word, &end);
    if (end != word && size >= 0 && (!*end || !strcmp(end, "px"))) *word = 0;
    for (;;) {
        length = strlen(family);
        while (length && isspace((unsigned char)family[length - 1])) family[--length] = 0;
        if (length && family[length - 1] == ',') { family[length - 1] = 0; break; }
        word = family + length;
        while (word > family && !isspace((unsigned char)word[-1])) --word;
        if (!O2UIFontStyleWord(word)) break;
        *word = 0;
    }
    char *first = family;
    while (isspace((unsigned char)*first)) ++first;
    memmove(family, first, strlen(first) + 1);
    if (!family[0]) { free(family); return NULL; }
    return family;
}

static char *O2UIFontDescriptionFromReply(DBusMessage *reply) {
    char *description = NULL;
    DBusMessageIter value;
    if (reply && dbus_message_has_signature(reply, "v") && dbus_message_iter_init(reply, &value)) {
        /* Read historically wraps the value in another variant. Accept either. */
        for (int depth = 0; depth < 2 &&
                dbus_message_iter_get_arg_type(&value) == DBUS_TYPE_VARIANT; ++depth) {
            DBusMessageIter nested;
            dbus_message_iter_recurse(&value, &nested);
            value = nested;
        }
        if (dbus_message_iter_get_arg_type(&value) == DBUS_TYPE_STRING) {
            const char *text;
            dbus_message_iter_get_basic(&value, &text);
            if (text && strlen(text) <= 4096) description = strdup(text);
        }
    }
    return description;
}

/* libdbus waits 25 s by default for a reply; a bus that accepts but never
 * answers must not hold up font initialization that long. */
#define O2UI_FONT_BUS_TIMEOUT_MS 250

/* Session bus from DBUS_SESSION_BUS_ADDRESS only. dbus_bus_get falls back to
 * autolaunch (spawning dbus-launch when DISPLAY is set) without an address,
 * and registers with an unbounded Hello; this does neither. */
static DBusConnection *O2UIFontOpenSessionBus(int timeout) {
    const char *address = getenv("DBUS_SESSION_BUS_ADDRESS");
    if (!address || !address[0]) return NULL;
    DBusError error;
    dbus_error_init(&error);
    DBusConnection *bus = dbus_connection_open_private(address, &error);
    if (!bus) { dbus_error_free(&error); return NULL; }
    dbus_connection_set_exit_on_disconnect(bus, FALSE);
    /* send_with_reply_and_block applies no timeout while the connection is
     * still authenticating, so authenticate under the bound first. */
    struct timespec start;
    clock_gettime(CLOCK_MONOTONIC, &start);
    for (;;) {
        if (dbus_connection_get_is_authenticated(bus) || !dbus_connection_get_is_connected(bus)) break;
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        long spent = (now.tv_sec - start.tv_sec) * 1000 + (now.tv_nsec - start.tv_nsec) / 1000000;
        if (spent >= timeout) break;
        dbus_connection_read_write(bus, (int)(timeout - spent));
    }
    if (!dbus_connection_get_is_authenticated(bus)) {
        dbus_error_free(&error);
        dbus_connection_close(bus);
        dbus_connection_unref(bus);
        return NULL;
    }
    DBusMessage *hello = dbus_message_new_method_call(DBUS_SERVICE_DBUS, DBUS_PATH_DBUS,
        DBUS_INTERFACE_DBUS, "Hello");
    DBusMessage *reply = hello ? dbus_connection_send_with_reply_and_block(bus, hello, timeout, &error) : NULL;
    if (hello) dbus_message_unref(hello);
    dbus_error_free(&error);
    DBusMessageIter value;
    const char *name = NULL;
    if (reply && dbus_message_has_signature(reply, "s") && dbus_message_iter_init(reply, &value))
        dbus_message_iter_get_basic(&value, &name);
    int registered = name && dbus_bus_set_unique_name(bus, name);
    if (reply) dbus_message_unref(reply);
    if (registered) return bus;
    dbus_connection_close(bus);
    dbus_connection_unref(bus);
    return NULL;
}

/* Never activate the portal service just to read a font name. */
static DBusMessage *O2UIFontPortalReadRequest(void) {
    DBusMessage *request = dbus_message_new_method_call("org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop", "org.freedesktop.portal.Settings", "Read");
    if (!request) return NULL;
    DBusMessageIter args;
    const char *space = "org.gnome.desktop.interface", *key = "font-name";
    dbus_message_iter_init_append(request, &args);
    if (!dbus_message_iter_append_basic(&args, DBUS_TYPE_STRING, &space) ||
        !dbus_message_iter_append_basic(&args, DBUS_TYPE_STRING, &key)) {
        dbus_message_unref(request);
        return NULL;
    }
    dbus_message_set_auto_start(request, FALSE);
    return request;
}

static char *O2UIFontPortalDescription(void) {
    DBusConnection *bus = O2UIFontOpenSessionBus(O2UI_FONT_BUS_TIMEOUT_MS);
    if (!bus) return NULL;
    DBusError error;
    dbus_error_init(&error);
    DBusMessage *request = O2UIFontPortalReadRequest(), *reply = NULL;
    if (request) {
        reply = dbus_connection_send_with_reply_and_block(bus, request, O2UI_FONT_BUS_TIMEOUT_MS, &error);
        dbus_message_unref(request);
    }
    char *description = O2UIFontDescriptionFromReply(reply);
    if (reply) dbus_message_unref(reply);
    dbus_error_free(&error);
    dbus_connection_close(bus);
    dbus_connection_unref(bus);
    return description;
}

static int O2UIFontPatternHasFamily(FcPattern *pattern, const char *family) {
    FcChar8 *actual;
    for (int i = 0; FcPatternGetString(pattern, FC_FAMILY, i, &actual) == FcResultMatch; ++i)
        if (!strcmp((const char *)actual, family)) return 1;
    return 0;
}

static int O2UIFontFamilyInstalled(FcConfig *config, const char *family) {
    FcPattern *query = FcPatternCreate();
    if (!query) return 0;
    FcPatternAddString(query, FC_FAMILY, (const FcChar8 *)family);
    FcConfigSubstitute(config, query, FcMatchPattern);
    FcDefaultSubstitute(query);
    FcResult result;
    FcPattern *match = FcFontMatch(config, query, &result);
    FcPatternDestroy(query);
    int exact = match && O2UIFontPatternHasFamily(match, family);
    if (match) FcPatternDestroy(match);
    return exact;
}

static char *O2UIFontChooseFamily(FcConfig *config, const char *description, int fixed) {
    char *configured = fixed ? NULL : O2UIFontFamilyFromDescription(description);
    /* Future runtime-font hook: add licensed assets with FcConfigAppFontAddDir
     * before selection ONLY after user approval. P2 never downloads/vendors Inter. */
    const char *choices[] = {configured, "Inter", "Adwaita Sans", "Cantarell", "Noto Sans"};
    char *chosen = NULL;
    if (configured) {
        char *cursor = configured;
        while (*cursor) {
            char *comma = strchr(cursor, ',');
            if (comma) *comma = 0;
            while (isspace((unsigned char)*cursor)) ++cursor;
            size_t n = strlen(cursor);
            while (n && isspace((unsigned char)cursor[n - 1])) cursor[--n] = 0;
            if (*cursor && O2UIFontFamilyInstalled(config, cursor)) { chosen = strdup(cursor); break; }
            if (!comma) break;
            cursor = comma + 1;
        }
    }
    if (fixed) {
        if (O2UIFontFamilyInstalled(config, "DejaVu Sans Mono")) chosen = strdup("DejaVu Sans Mono");
    } else if (!chosen) {
        for (size_t i = 1; i < sizeof(choices) / sizeof(choices[0]); ++i)
            if (choices[i] && O2UIFontFamilyInstalled(config, choices[i])) {
                chosen = strdup(choices[i]); break;
            }
    }
    free(configured);
    return chosen ? chosen : strdup(fixed ? "monospace" : "sans-serif");
}

static char *O2UIFontXMLEscape(const char *text) {
    size_t length = strlen(text);
    if (length > 4096) return NULL;
    char *result = malloc(length * 6 + 1), *p = result;
    if (!result) return NULL;
    for (; *text; ++text) {
        const char *entity = NULL;
        switch (*text) {
        case '&': entity = "&amp;"; break;
        case '<': entity = "&lt;"; break;
        case '>': entity = "&gt;"; break;
        case '"': entity = "&quot;"; break;
        case '\'': entity = "&apos;"; break;
        }
        if (entity) { size_t n = strlen(entity); memcpy(p, entity, n); p += n; }
        else *p++ = *text;
    }
    *p = 0;
    return result;
}

static int O2UIFontIsAlias(const char *name) {
    const char *aliases[] = {".AppleSystemUIFont", "Helvetica Neue", "Helvetica",
        "Lucida Grande", "San Francisco", "Menlo", "Monaco"};
    for (size_t i = 0; i < sizeof(aliases) / sizeof(aliases[0]); ++i)
        if (!strcmp(name, aliases[i])) return 1;
    return 0;
}

static int O2UIFontInstallAliases(FcConfig *config, const char *family, int fixed) {
    static const char *ui[] = {".AppleSystemUIFont", "Helvetica Neue", "Helvetica",
        "Lucida Grande", "San Francisco"};
    static const char *mono[] = {"Menlo", "Monaco"};
    const char **names = fixed ? mono : ui;
    size_t count = fixed ? sizeof(mono) / sizeof(mono[0]) : sizeof(ui) / sizeof(ui[0]);
    char *escaped = O2UIFontXMLEscape(family);
    if (!escaped) return 0;
    int success = 1;
    for (size_t i = 0; i < count; ++i) {
        size_t capacity = strlen(escaped) + strlen(names[i]) + 180;
        char *xml = malloc(capacity);
        if (!xml) { success = 0; break; }
        snprintf(xml, capacity, "<fontconfig><alias binding=\"strong\"><family>%s</family>"
            "<prefer><family>%s</family></prefer></alias></fontconfig>", names[i], escaped);
        success = FcConfigParseAndLoadFromMemory(config, (const FcChar8 *)xml, FcTrue) && success;
        free(xml);
    }
    free(escaped);
    return success;
}
#endif
