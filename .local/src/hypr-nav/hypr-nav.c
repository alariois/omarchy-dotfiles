/*
 * hypr-nav - Smart navigation across Hyprland windows, tmux panes, and vim splits
 *
 * When called from Hyprland (default):
 *   - Terminal with tmux + vim: sends Alt+key to vim (vim handles edge → --from-vim)
 *   - Terminal with tmux, no vim: navigates tmux panes, falls back to Hyprland
 *   - No tmux / not a terminal: Hyprland movefocus
 *
 * When called from vim (--from-vim):
 *   - Tries tmux pane navigation, falls back to Hyprland movefocus
 *
 * Usage: hypr-nav <l|d|u|r> [--from-vim] [--verbose]
 */

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define BUF_SZ 512

/* ── Debug ─────────────────────────────────────────────────────────── */

static int verbose = 0;

#define dbg(...) do { if (verbose) fprintf(stderr, "[hypr-nav] " __VA_ARGS__); } while(0)

/* ── Utilities ─────────────────────────────────────────────────────── */

static int cmd_out(const char *cmd, char *buf, size_t sz)
{
    FILE *fp = popen(cmd, "r");
    if (!fp) {
        buf[0] = '\0';
        return -1;
    }
    buf[0] = '\0';
    if (!fgets(buf, sz, fp)) buf[0] = '\0';
    int st = pclose(fp);
    char *nl = strchr(buf, '\n');
    if (nl) *nl = '\0';
    return WIFEXITED(st) ? WEXITSTATUS(st) : -1;
}

/* ── Process tree ──────────────────────────────────────────────────── */

/* Read PPID from /proc/<pid>/stat (no fork, fast) */
static long get_ppid_proc(long pid)
{
    char path[64];
    snprintf(path, sizeof(path), "/proc/%ld/stat", pid);
    FILE *fp = fopen(path, "r");
    if (!fp) return -1;
    char buf[512];
    if (!fgets(buf, sizeof(buf), fp)) { fclose(fp); return -1; }
    fclose(fp);
    /* Format: pid (comm) state ppid ... – comm may contain parens */
    char *cp = strrchr(buf, ')');
    if (!cp) return -1;
    long ppid;
    if (sscanf(cp + 2, "%*c %ld", &ppid) != 1) return -1;
    return ppid;
}

/* Function pointer for get_ppid — swappable for testing */
typedef long (*ppid_fn_t)(long pid);

#ifndef TESTING
static
#endif
ppid_fn_t ppid_fn = get_ppid_proc;

static long get_ppid(long pid) { return ppid_fn(pid); }

static int is_ancestor_of(long ancestor, long pid)
{
    long p = pid;
    for (int i = 0; p > 1 && i < 64; i++) {
        if (p == ancestor) return 1;
        long pp = get_ppid(p);
        if (pp <= 0 || pp == p) break;
        p = pp;
    }
    return 0;
}

/* ── Direction mapping ─────────────────────────────────────────────── */

typedef struct {
    char key;           /* l, d, u, r           */
    const char *tflag;  /* tmux: -L, -D, -U, -R */
    const char *vkey;   /* Alt key: M-h … M-l   */
} Dir;

static const Dir dirs[] = {
    { 'l', "-L", "M-h" },
    { 'd', "-D", "M-j" },
    { 'u', "-U", "M-k" },
    { 'r', "-R", "M-l" },
};

static const Dir *dir_lookup(char c)
{
    for (int i = 0; i < 4; i++)
        if (dirs[i].key == c) return &dirs[i];
    return NULL;
}

/* ── Hyprland ──────────────────────────────────────────────────────── */

typedef struct {
    long pid;
    char class[128];
} WinInfo;

/* Parse hyprctl activewindow JSON into WinInfo (pure function, no I/O) */
static int parse_active_window(const char *json, WinInfo *w)
{
    w->pid = 0;
    w->class[0] = '\0';

    if (!json || !*json) return -1;

    /* Extract "pid": NUMBER */
    const char *p = strstr(json, "\"pid\"");
    if (p && (p = strchr(p, ':')))
        w->pid = atol(p + 1);

    /* Extract "class": "STRING" — match first "class" key */
    p = strstr(json, "\"class\"");
    if (p && (p = strchr(p, ':')) && (p = strchr(p, '"'))) {
        p++;
        const char *end = strchr(p, '"');
        if (end) {
            size_t len = (size_t)(end - p);
            if (len >= sizeof(w->class)) len = sizeof(w->class) - 1;
            memcpy(w->class, p, len);
            w->class[len] = '\0';
        }
    }
    return 0;
}

static WinInfo get_active_window(void)
{
    WinInfo w = { 0 };
    FILE *fp = popen("hyprctl activewindow -j 2>/dev/null", "r");
    if (!fp) return w;
    char json[4096];
    size_t n = fread(json, 1, sizeof(json) - 1, fp);
    pclose(fp);
    json[n] = '\0';
    parse_active_window(json, &w);
    return w;
}

static int is_terminal(const char *class)
{
    static const char *terms[] = {
        "ghostty", "kitty", "alacritty", "foot", "wezterm", "erminal", NULL
    };
    char lower[128];
    strncpy(lower, class, sizeof(lower) - 1);
    lower[sizeof(lower) - 1] = '\0';
    for (char *c = lower; *c; c++) *c = tolower(*c);
    for (const char **t = terms; *t; t++)
        if (strstr(lower, *t)) return 1;
    return 0;
}

static void hypr_move(char d)
{
    dbg("fallback: hyprctl dispatch movefocus %c\n", d);
    char cmd[64];
    snprintf(cmd, sizeof(cmd), "hyprctl dispatch movefocus %c", d);
    system(cmd);
}

/* ── tmux ──────────────────────────────────────────────────────────── */

typedef struct {
    char pane_id[32];   /* e.g. %5  */
    char window_id[32]; /* e.g. @3  */
    int  found;
} TmuxClient;

/*
 * Parse a single line from `tmux list-clients -F '#{client_flags} ...'`
 * Returns 1 if the line has the "focused" flag and all fields parsed, 0 otherwise.
 */
static int parse_tmux_client_line(const char *line, char *pane_id, size_t pane_sz,
                                  char *window_id, size_t win_sz, long *cpid)
{
    if (!strstr(line, "focused"))
        return 0;

    char flags[64];
    char pid_buf[32], wid_buf[32];
    if (sscanf(line, "%63s %ld %31s %31s", flags, cpid, pid_buf, wid_buf) != 4)
        return 0;

    strncpy(pane_id, pid_buf, pane_sz - 1);
    pane_id[pane_sz - 1] = '\0';
    strncpy(window_id, wid_buf, win_sz - 1);
    window_id[win_sz - 1] = '\0';
    return 1;
}

/*
 * Find the tmux client in the focused terminal window.
 *
 * Multi-window terminals (e.g. Ghostty) share a single PID across all
 * windows, so PID ancestry alone can't distinguish them.  Instead we
 * rely on tmux's focus tracking (requires `set -g focus-events on`):
 * only the client whose terminal window currently has Wayland keyboard
 * focus carries the "focused" flag.  We additionally verify that the
 * client is a descendant of win_pid to avoid cross-terminal-app matches.
 */
static TmuxClient find_tmux_client(long win_pid)
{
    TmuxClient tc = { .found = 0 };
    FILE *fp = popen(
        "tmux list-clients "
        "-F '#{client_flags} #{client_pid} #{pane_id} #{window_id}' 2>/dev/null",
        "r");
    if (!fp) return tc;

    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        long cpid;
        char pane_id[32], window_id[32];

        if (parse_tmux_client_line(line, pane_id, sizeof(pane_id),
                                   window_id, sizeof(window_id), &cpid)
            && is_ancestor_of(win_pid, cpid)) {
            strncpy(tc.pane_id, pane_id, sizeof(tc.pane_id) - 1);
            strncpy(tc.window_id, window_id, sizeof(tc.window_id) - 1);
            tc.found = 1;
            dbg("tmux client found: pane=%s window=%s cpid=%ld\n",
                tc.pane_id, tc.window_id, cpid);
            break;
        }
    }
    pclose(fp);
    if (!tc.found) dbg("no tmux client found for win_pid=%ld\n", win_pid);
    return tc;
}

static int is_vim_in_pane(const char *pane_id)
{
    char cmd[BUF_SZ], buf[128];
    snprintf(cmd, sizeof(cmd),
             "tmux display-message -t '%s' -p '#{pane_current_command}'", pane_id);
    if (cmd_out(cmd, buf, sizeof(buf)) != 0) return 0;
    for (char *p = buf; *p; p++) *p = tolower(*p);
    int result = strstr(buf, "vim") != NULL || strstr(buf, "view") != NULL;
    dbg("pane %s command='%s' is_vim=%d\n", pane_id, buf, result);
    return result;
}

typedef struct { int x, y; char id[32]; } PanePos;

/* Query a pane's position and ID */
static PanePos get_pane_pos(const char *target)
{
    PanePos pp = { 0 };
    char cmd[BUF_SZ], buf[128];
    if (target)
        snprintf(cmd, sizeof(cmd),
                 "tmux display-message -t '%s' -p '#{pane_id} #{pane_left} #{pane_top}'",
                 target);
    else
        snprintf(cmd, sizeof(cmd),
                 "tmux display-message -p '#{pane_id} #{pane_left} #{pane_top}'");
    cmd_out(cmd, buf, sizeof(buf));
    sscanf(buf, "%31s %d %d", pp.id, &pp.x, &pp.y);
    return pp;
}

/*
 * Check if a pane move was in the expected direction (not a wrap-around).
 * Pure function, no I/O.
 */
static int is_valid_move(const char *flag, int bx, int by, int ax, int ay)
{
    if (strcmp(flag, "-L") == 0) return ax < bx;
    if (strcmp(flag, "-R") == 0) return ax > bx;
    if (strcmp(flag, "-U") == 0) return ay < by;
    if (strcmp(flag, "-D") == 0) return ay > by;
    return 0;
}

/*
 * Try to move to an adjacent tmux pane.
 * Returns 1 if we moved in the correct direction, 0 if at edge.
 * Detects and undoes wrap-around (tmux select-pane wraps by default).
 */
static int tmux_nav(const char *pane_id, const char *window_id, const char *flag)
{
    char cmd[BUF_SZ];
    char win_id_buf[32];

    /* If no window_id provided (--from-vim path), resolve it now */
    if (!window_id) {
        cmd_out("tmux display-message -p '#{window_id}'", win_id_buf, sizeof(win_id_buf));
        window_id = win_id_buf;
    }

    /* Get current pane position (use explicit pane target or default) */
    PanePos before = get_pane_pos(pane_id);
    dbg("tmux_nav: before pane=%s pos=(%d,%d) flag=%s\n",
        before.id, before.x, before.y, flag);

    /* Attempt the move */
    if (pane_id)
        snprintf(cmd, sizeof(cmd), "tmux select-pane -t '%s' %s", pane_id, flag);
    else
        snprintf(cmd, sizeof(cmd), "tmux select-pane %s", flag);
    system(cmd);

    /* Query the now-active pane via window ID (works even from a subprocess) */
    PanePos after = get_pane_pos(window_id);
    dbg("tmux_nav: after pane=%s pos=(%d,%d)\n", after.id, after.x, after.y);

    /* Same pane — single pane or no neighbor in that direction */
    if (strcmp(before.id, after.id) == 0) {
        dbg("tmux_nav: same pane, at edge\n");
        return 0;
    }

    /* Verify we actually moved in the expected direction, not wrapped */
    if (!is_valid_move(flag, before.x, before.y, after.x, after.y)) {
        dbg("tmux_nav: wrapped around, undoing\n");
        snprintf(cmd, sizeof(cmd), "tmux select-pane -t '%s'", before.id);
        system(cmd);
        return 0;
    }

    dbg("tmux_nav: moved to pane %s\n", after.id);
    return 1;
}

static void tmux_send(const char *pane_id, const char *keys)
{
    char cmd[BUF_SZ];
    if (pane_id)
        snprintf(cmd, sizeof(cmd), "tmux send-keys -t '%s' '%s'", pane_id, keys);
    else
        snprintf(cmd, sizeof(cmd), "tmux send-keys '%s'", keys);
    dbg("sending keys '%s' to pane %s\n", keys, pane_id ? pane_id : "(default)");
    system(cmd);
}

/* ── Main ──────────────────────────────────────────────────────────── */

#ifdef TESTING
int hypr_nav_main(int argc, char *argv[])
#else
int main(int argc, char *argv[])
#endif
{
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <l|d|u|r> [--from-vim] [--verbose]\n", argv[0]);
        return 1;
    }

    /* Check for --verbose anywhere in args */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--verbose") == 0 || strcmp(argv[i], "--debug") == 0)
            verbose = 1;
    }

    const Dir *d = dir_lookup(argv[1][0]);
    if (!d) {
        fprintf(stderr, "Invalid direction: %s (expected l, d, u, r)\n", argv[1]);
        return 1;
    }

    int from_vim = 0;
    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "--from-vim") == 0)
            from_vim = 1;
    }

    dbg("direction=%c tflag=%s vkey=%s from_vim=%d\n",
        d->key, d->tflag, d->vkey, from_vim);

    if (from_vim) {
        /* Vim already at its edge – try tmux pane, then Hyprland */
        dbg("from-vim: trying tmux nav\n");
        if (!tmux_nav(NULL, NULL, d->tflag))
            hypr_move(d->key);
        return 0;
    }

    /* Called from Hyprland */
    WinInfo win = get_active_window();
    dbg("active window: pid=%ld class='%s'\n", win.pid, win.class);

    if (win.pid <= 0 || !is_terminal(win.class)) {
        dbg("not a terminal, direct movefocus\n");
        hypr_move(d->key);
        return 0;
    }

    TmuxClient tc = find_tmux_client(win.pid);
    if (!tc.found) {
        dbg("no tmux client, direct movefocus\n");
        hypr_move(d->key);
        return 0;
    }

    if (is_vim_in_pane(tc.pane_id)) {
        /* Let vim handle it – vim calls back with --from-vim at its edge */
        dbg("vim detected, sending %s to vim\n", d->vkey);
        tmux_send(tc.pane_id, d->vkey);
    } else {
        /* Navigate tmux, fall back to Hyprland */
        dbg("no vim, trying tmux nav\n");
        if (!tmux_nav(tc.pane_id, tc.window_id, d->tflag))
            hypr_move(d->key);
    }

    return 0;
}
