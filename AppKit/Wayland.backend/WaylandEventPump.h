/* Copyright (c) 2026 Darling contributors. SPDX-License-Identifier: MIT */
#ifndef WAYLAND_EVENT_PUMP_H
#define WAYLAND_EVENT_PUMP_H
#include "WaylandLibrary.h"
#include "WaylandProtocol.h"
#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <unistd.h>

/* Only xdg_wm_base is dispatched here. Application proxies stay on the default
 * queue, including objects constructed from xdg_wm_base through a wrapper. */
typedef struct {
    struct WaylandLibrary *library;
    struct wl_display *display;
    struct wl_event_queue *queue;
    pthread_t thread;
    int stop[2], error;
    bool started;
    void (*wake)(void *);
    void *info;
} WaylandEventPump;

static struct wl_proxy *WaylandMainQueueObject(struct WaylandLibrary *wl,
        struct wl_proxy *proxy, uint32_t opcode,
        const struct wl_interface *interface, union wl_argument *args) {
    struct wl_proxy *wrapper = wl->wl_proxy_create_wrapper(proxy);
    if (!wrapper) return NULL;
    wl->wl_proxy_set_queue(wrapper, NULL);
    struct wl_proxy *created = wl->wl_proxy_marshal_array_flags(wrapper, opcode,
            interface, wl->wl_proxy_get_version(proxy), 0, args);
    wl->wl_proxy_wrapper_destroy(wrapper);
    return created;
}

static int WaylandPingDispatch(const void *implementation, void *proxy,
        uint32_t opcode, const struct wl_message *message, union wl_argument *args) {
    WaylandEventPump *pump = ((struct WaylandLibrary *)implementation)->wl_proxy_get_user_data(proxy);
    if (opcode == WP_WM_BASE_EV_PING) {
        union wl_argument pong[] = {{.u = args[0].u}};
        pump->library->wl_proxy_marshal_array_flags(proxy, WP_WM_BASE_PONG,
                NULL, pump->library->wl_proxy_get_version(proxy), 0, pong);
    }
    return 0;
}

static int WaylandPumpFlush(WaylandEventPump *pump) {
    struct WaylandLibrary *wl = pump->library;
    if (wl->wl_display_flush(pump->display) >= 0) return 0;
    // Linux libwayland sets native errno, not Darwin's errno (EAGAIN is 35).
    // /usr/include/asm-generic/errno-base.h defines Linux EAGAIN as 11.
    return wl->native_errno() == 11 ? 1 : -1;
}

static void *WaylandPumpRun(void *data) {
    WaylandEventPump *pump = data;
    struct WaylandLibrary *wl = pump->library;
    for (;;) {
        while (wl->wl_display_prepare_read_queue(pump->display, pump->queue) != 0) {
            if (wl->wl_display_dispatch_queue_pending(pump->display, pump->queue) < 0)
                goto failed;
        }
        int flush = WaylandPumpFlush(pump);
        if (flush < 0) {
            wl->wl_display_cancel_read(pump->display);
            goto failed;
        }
        struct pollfd fds[] = {
            {.fd = wl->wl_display_get_fd(pump->display),
             .events = POLLIN | (flush ? POLLOUT : 0)},
            {.fd = pump->stop[0], .events = POLLIN}
        };
        int result = poll(fds, 2, -1);
        if (result < 0 || fds[1].revents || !(fds[0].revents & POLLIN)) {
            wl->wl_display_cancel_read(pump->display);
            if (fds[1].revents) return NULL;
            if (result < 0 && errno != EINTR) goto failed;
            if (fds[0].revents & (POLLERR | POLLHUP | POLLNVAL)) goto failed;
            continue;
        }
        if (wl->wl_display_read_events(pump->display) < 0) goto failed;
        if (wl->wl_display_dispatch_queue_pending(pump->display, pump->queue) < 0)
            goto failed;
        // The default queue may now contain input even though the fd is empty.
        pump->wake(pump->info);
    }
failed:
    __atomic_store_n(&pump->error, 1, __ATOMIC_RELEASE);
    pump->wake(pump->info);
    return NULL;
}

static bool WaylandPumpStart(WaylandEventPump *pump) {
    if (pipe(pump->stop) != 0) return false;
    if (pthread_create(&pump->thread, NULL, WaylandPumpRun, pump) != 0) {
        close(pump->stop[0]); close(pump->stop[1]);
        return false;
    }
    pump->started = true;
    return true;
}

static void WaylandPumpStop(WaylandEventPump *pump) {
    if (!pump->started) return;
    char stop = 1;
    while (write(pump->stop[1], &stop, 1) < 0 && errno == EINTR) {}
    pthread_join(pump->thread, NULL);
    close(pump->stop[0]); close(pump->stop[1]);
    pump->started = false;
}
#endif
