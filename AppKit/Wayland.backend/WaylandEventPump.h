/* Copyright (c) 2026 Darling contributors. SPDX-License-Identifier: MIT */
#ifndef WAYLAND_EVENT_PUMP_H
#define WAYLAND_EVENT_PUMP_H
#include "WaylandLibrary.h"
#include "WaylandProtocol.h"
#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <unistd.h>
#include <stdio.h>
#include <time.h>

/* Only xdg_wm_base is dispatched here. Application proxies stay on the default
 * queue, including objects constructed from xdg_wm_base through a wrapper. */
typedef struct {
    struct WaylandLibrary *library;
    struct wl_display *display;
    struct wl_event_queue *queue;
    pthread_t thread;
    int stop[2], error;
    bool started, boundaries;
    int boundaryFD;
    unsigned pendingPongs;
    unsigned long reads, pingEvents, wakes;
    double oldestPing;
    void (*wake)(void *);
    void *info;
} WaylandEventPump;

static double WaylandBoundaryMilliseconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

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
        if (pump->boundaries) {
            double received = WaylandBoundaryMilliseconds();
            if (!pump->pendingPongs++) pump->oldestPing = received;
            dprintf(pump->boundaryFD,
                    "QV_WAYLAND ping_received pid=%d serial=%u monotonic_ms=%.3f\n",
                    getpid(), args[0].u, received);
        }
        union wl_argument pong[] = {{.u = args[0].u}};
        pump->library->wl_proxy_marshal_array_flags(proxy, WP_WM_BASE_PONG,
                NULL, pump->library->wl_proxy_get_version(proxy), 0, pong);
    }
    return 0;
}

static int WaylandPumpFlush(WaylandEventPump *pump) {
    struct WaylandLibrary *wl = pump->library;
    if (wl->wl_display_flush(pump->display) >= 0) {
        if (pump->boundaries && pump->pendingPongs) {
            dprintf(pump->boundaryFD,
                    "QV_WAYLAND pong_sent pid=%d count=%u max_latency_ms=%.3f\n",
                    getpid(), pump->pendingPongs,
                    WaylandBoundaryMilliseconds() - pump->oldestPing);
            pump->pendingPongs = 0;
        }
        return 0;
    }
    // Linux libwayland sets native errno, not Darwin's errno (EAGAIN is 35).
    // /usr/include/asm-generic/errno-base.h defines Linux EAGAIN as 11.
    return wl->native_errno() == 11 ? 1 : -1;
}

static int WaylandPumpDispatch(WaylandEventPump *pump) {
    int count = pump->library->wl_display_dispatch_queue_pending(pump->display, pump->queue);
    if (count > 0) pump->pingEvents += count;
    if (pump->boundaries)
        dprintf(pump->boundaryFD,
                "QV_WAYLAND dispatch pid=%d display=%p queue=ping queue_id=%p mode=worker count=%d total=%lu error=%d\n",
                getpid(), pump->display, pump->queue, count, pump->pingEvents,
                pump->library->wl_display_get_error(pump->display));
    return count;
}

static void *WaylandPumpRun(void *data) {
    WaylandEventPump *pump = data;
    struct WaylandLibrary *wl = pump->library;
    for (;;) {
        while (wl->wl_display_prepare_read_queue(pump->display, pump->queue) != 0) {
            if (WaylandPumpDispatch(pump) < 0)
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
        if (pump->boundaries)
            dprintf(pump->boundaryFD,
                    "QV_WAYLAND fd_ready pid=%d display=%p queue=ping mode=worker fd=%d result=%d revents=%d stop=%d\n",
                    getpid(), pump->display, fds[0].fd, result,
                    fds[0].revents, fds[1].revents);
        if (result < 0 || fds[1].revents || !(fds[0].revents & POLLIN)) {
            wl->wl_display_cancel_read(pump->display);
            if (fds[1].revents) return NULL;
            if (result < 0 && errno != EINTR) goto failed;
            if (fds[0].revents & (POLLERR | POLLHUP | POLLNVAL)) goto failed;
            continue;
        }
        if (wl->wl_display_read_events(pump->display) < 0) goto failed;
        ++pump->reads;
        if (WaylandPumpDispatch(pump) < 0)
            goto failed;
        // The default queue may now contain input even though the fd is empty.
        ++pump->wakes;
        if (pump->boundaries)
            dprintf(pump->boundaryFD,
                    "QV_WAYLAND read_events pid=%d display=%p queue=all mode=worker reads=%lu wakes=%lu\n",
                    getpid(), pump->display, pump->reads, pump->wakes);
        pump->wake(pump->info);
    }
failed:
    if (pump->boundaries)
        dprintf(pump->boundaryFD,
                "QV_WAYLAND pump_failed pid=%d display=%p queue=ping mode=worker error=%d native_errno=%d\n",
                getpid(), pump->display, wl->wl_display_get_error(pump->display), wl->native_errno());
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
