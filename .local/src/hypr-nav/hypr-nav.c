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
 * Usage: hypr-nav <l|d|u|r> [--from-vim]
 */

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define BUF_SZ 512

/* ── Utilities ──────────────────────────────────────────────────────── */

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

/* Read PPID from /proc/<pid>/stat (no fork, fast) */
static long get_ppid(long pid)
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

/* ── Direction mapping ──────────────────────────────────────────────── */

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

/* ── Hyprland ───────────────────────────────────────────────────────── */

typedef struct {
    long pid;
    char class[128];
} WinInfo;

static WinInfo get_active_window(void)
{
    WinInfo w = { 0 };
    FILE *fp = popen("hyprctl activewindow -j 2>/dev/null", "r");
    if (!fp) return w;
    char json[4096];
    size_t n = fread(json, 1, sizeof(json) - 1, fp);
    pclose(fp);
    json[n] = '\0';

    /* Extract "pid": NUMBER */
    char *p = strstr(json, "\"pid\"");
    if (p && (p = strchr(p, ':')))
        w.pid = atol(p + 1);

    /* Extract "class": "STRING" */
    p = strstr(json, "\"class\"");
    if (p && (p = strchr(p, ':')) && (p = strchr(p, '"'))) {
        p++;
        char *end = strchr(p, '"');
        if (end) {
            size_t len = end - p;
            if (len >= sizeof(w.class)) len = sizeof(w.class) - 1;
            memcpy(w.class, p, len);
            w.class[len] = '\0';
        }
    }
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
    char cmd[64];
    snprintf(cmd, sizeof(cmd), "hyprctl dispatch movefocus %c", d);
    system(cmd);
}

/* ── tmux ───────────────────────────────────────────────────────────── */

typedef struct {
    char pane_id[32];   /* e.g. %5  */
    char window_id[32]; /* e.g. @3  */
    int  found;
} TmuxClient;

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
        if (!strstr(line, "focused"))
            continue;

        char flags[64], pid[32], wid[32];
        long cpid;
        if (sscanf(line, "%63s %ld %31s %31s", flags, &cpid, pid, wid) == 4
            && is_ancestor_of(win_pid, cpid)) {
            strncpy(tc.pane_id, pid, sizeof(tc.pane_id) - 1);
            strncpy(tc.window_id, wid, sizeof(tc.window_id) - 1);
            tc.found = 1;
            break;
        }
    }
    pclose(fp);
    return tc;
}

static int is_vim_in_pane(const char *pane_id)
{
    char cmd[BUF_SZ], buf[128];
    snprintf(cmd, sizeof(cmd),
             "tmux display-message -t '%s' -p '#{pane_current_command}'", pane_id);
    if (cmd_out(cmd, buf, sizeof(buf)) != 0) return 0;
    for (char *p = buf; *p; p++) *p = tolower(*p);
    return strstr(buf, "vim") != NULL || strstr(buf, "view") != NULL;
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

    /* Attempt the move */
    if (pane_id)
        snprintf(cmd, sizeof(cmd), "tmux select-pane -t '%s' %s", pane_id, flag);
    else
        snprintf(cmd, sizeof(cmd), "tmux select-pane %s", flag);
    system(cmd);

    /* Query the now-active pane via window ID (works even from a subprocess) */
    PanePos after = get_pane_pos(window_id);

    /* Same pane — single pane or no neighbor in that direction */
    if (strcmp(before.id, after.id) == 0)
        return 0;

    /* Verify we actually moved in the expected direction, not wrapped */
    int ok = 0;
    if (strcmp(flag, "-L") == 0)      ok = (after.x < before.x);
    else if (strcmp(flag, "-R") == 0) ok = (after.x > before.x);
    else if (strcmp(flag, "-U") == 0) ok = (after.y < before.y);
    else if (strcmp(flag, "-D") == 0) ok = (after.y > before.y);

    if (!ok) {
        /* Wrapped around — undo by selecting the original pane */
        snprintf(cmd, sizeof(cmd), "tmux select-pane -t '%s'", before.id);
        system(cmd);
        return 0;
    }

    return 1;
}

static void tmux_send(const char *pane_id, const char *keys)
{
    char cmd[BUF_SZ];
    if (pane_id)
        snprintf(cmd, sizeof(cmd), "tmux send-keys -t '%s' '%s'", pane_id, keys);
    else
        snprintf(cmd, sizeof(cmd), "tmux send-keys '%s'", keys);
    system(cmd);
}

/* ── Main ───────────────────────────────────────────────────────────── */

int main(int argc, char *argv[])
{
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <l|d|u|r> [--from-vim]\n", argv[0]);
        return 1;
    }

    const Dir *d = dir_lookup(argv[1][0]);
    if (!d) {
        fprintf(stderr, "Invalid direction: %s (expected l, d, u, r)\n", argv[1]);
        return 1;
    }

    int from_vim = argc >= 3 && strcmp(argv[2], "--from-vim") == 0;

    if (from_vim) {
        /* Vim already at its edge – try tmux pane, then Hyprland */
        if (!tmux_nav(NULL, NULL, d->tflag))
            hypr_move(d->key);
        return 0;
    }

    /* Called from Hyprland */
    WinInfo win = get_active_window();
    if (win.pid <= 0 || !is_terminal(win.class)) {
        hypr_move(d->key);
        return 0;
    }

    TmuxClient tc = find_tmux_client(win.pid);
    if (!tc.found) {
        hypr_move(d->key);
        return 0;
    }

    if (is_vim_in_pane(tc.pane_id)) {
        /* Let vim handle it – vim calls back with --from-vim at its edge */
        tmux_send(tc.pane_id, d->vkey);
    } else {
        /* Navigate tmux, fall back to Hyprland */
        if (!tmux_nav(tc.pane_id, tc.window_id, d->tflag))
            hypr_move(d->key);
    }

    return 0;
}
