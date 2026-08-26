/*
 * Unit tests for hypr-nav
 *
 * Includes hypr-nav.c directly to test static functions.
 * Build: gcc -Wall -Wextra -g -DTESTING -o test_hypr_nav test_hypr_nav.c
 * Run:   ./test_hypr_nav
 */

#define TESTING 1
#include "hypr-nav.c"

#include <assert.h>

/* ── Test framework ────────────────────────────────────────────────── */

static int tests_run = 0;
static int tests_passed = 0;

#define RUN(fn) do { \
    printf("  %-55s", #fn); \
    fflush(stdout); \
    fn(); \
    tests_passed++; \
    tests_run++; \
    printf("PASS\n"); \
} while(0)

/* ── Mock process tree for is_ancestor_of ──────────────────────────── */

static struct { long pid; long ppid; } mock_tree[128];
static int mock_tree_sz = 0;

static long mock_get_ppid(long pid)
{
    for (int i = 0; i < mock_tree_sz; i++)
        if (mock_tree[i].pid == pid) return mock_tree[i].ppid;
    return -1;
}

static void mock_tree_clear(void)
{
    mock_tree_sz = 0;
}

static void mock_tree_add(long pid, long ppid)
{
    assert(mock_tree_sz < 128);
    mock_tree[mock_tree_sz].pid = pid;
    mock_tree[mock_tree_sz].ppid = ppid;
    mock_tree_sz++;
}

/* ── dir_lookup tests ──────────────────────────────────────────────── */

static void test_dir_lookup_left(void)
{
    const Dir *d = dir_lookup('l');
    assert(d != NULL);
    assert(d->key == 'l');
    assert(strcmp(d->tflag, "-L") == 0);
    assert(strcmp(d->vkey, "M-h") == 0);
    assert(d->akey == 'h');
}

static void test_dir_lookup_down(void)
{
    const Dir *d = dir_lookup('d');
    assert(d != NULL);
    assert(d->key == 'd');
    assert(strcmp(d->tflag, "-D") == 0);
    assert(strcmp(d->vkey, "M-j") == 0);
    assert(d->akey == 'j');
}

static void test_dir_lookup_up(void)
{
    const Dir *d = dir_lookup('u');
    assert(d != NULL);
    assert(d->key == 'u');
    assert(strcmp(d->tflag, "-U") == 0);
    assert(strcmp(d->vkey, "M-k") == 0);
    assert(d->akey == 'k');
}

static void test_dir_lookup_right(void)
{
    const Dir *d = dir_lookup('r');
    assert(d != NULL);
    assert(d->key == 'r');
    assert(strcmp(d->tflag, "-R") == 0);
    assert(strcmp(d->vkey, "M-l") == 0);
    assert(d->akey == 'l');
}

static void test_dir_lookup_invalid(void)
{
    assert(dir_lookup('x') == NULL);
    assert(dir_lookup('L') == NULL);  /* case sensitive */
    assert(dir_lookup('\0') == NULL);
}

/* ── is_terminal tests ─────────────────────────────────────────────── */

static void test_is_terminal_ghostty(void)
{
    assert(is_terminal("com.mitchellh.ghostty") == 1);
    assert(is_terminal("ghostty") == 1);
}

static void test_is_terminal_kitty(void)
{
    assert(is_terminal("kitty") == 1);
}

static void test_is_terminal_alacritty(void)
{
    assert(is_terminal("Alacritty") == 1);  /* case insensitive */
    assert(is_terminal("alacritty") == 1);
}

static void test_is_terminal_foot(void)
{
    assert(is_terminal("foot") == 1);
}

static void test_is_terminal_wezterm(void)
{
    assert(is_terminal("org.wezfurlong.wezterm") == 1);
}

static void test_is_terminal_generic(void)
{
    assert(is_terminal("GNOME-Terminal") == 1);  /* matches "erminal" */
    assert(is_terminal("xfce4-terminal") == 1);
}

static void test_is_terminal_non_terminal(void)
{
    assert(is_terminal("firefox") == 0);
    assert(is_terminal("chromium") == 0);
    assert(is_terminal("") == 0);
    assert(is_terminal("obsidian") == 0);
}

/* ── parse_active_window tests ─────────────────────────────────────── */

static void test_parse_window_full(void)
{
    const char *json =
        "{\"address\":\"0x562c07644c10\",\"mapped\":true,\"hidden\":false,"
        "\"at\":[6,6],\"size\":[1188,663],\"workspace\":{\"id\":2,\"name\":\"2\"},"
        "\"floating\":true,\"monitor\":0,"
        "\"class\":\"com.mitchellh.ghostty\","
        "\"title\":\"tmux\",\"initialClass\":\"com.mitchellh.ghostty\","
        "\"pid\":2479196,\"xwayland\":false}";
    WinInfo w;
    assert(parse_active_window(json, &w) == 0);
    assert(w.pid == 2479196);
    assert(strcmp(w.class, "com.mitchellh.ghostty") == 0);
    assert(strcmp(w.addr, "0x562c07644c10") == 0);
}

static void test_parse_window_missing_pid(void)
{
    const char *json = "{\"class\":\"kitty\",\"title\":\"bash\"}";
    WinInfo w;
    assert(parse_active_window(json, &w) == 0);
    assert(w.pid == 0);
    assert(strcmp(w.class, "kitty") == 0);
    assert(w.addr[0] == '\0');   /* absent address must not be stale */
}

static void test_parse_window_missing_class(void)
{
    const char *json = "{\"pid\":12345,\"title\":\"bash\"}";
    WinInfo w;
    assert(parse_active_window(json, &w) == 0);
    assert(w.pid == 12345);
    assert(w.class[0] == '\0');
}

static void test_parse_window_empty(void)
{
    WinInfo w;
    assert(parse_active_window("", &w) == -1);
    assert(parse_active_window(NULL, &w) == -1);
}

static void test_parse_window_large_pid(void)
{
    const char *json = "{\"class\":\"alacritty\",\"pid\":9999999999}";
    WinInfo w;
    assert(parse_active_window(json, &w) == 0);
    assert(w.pid == 9999999999L);
}

/* ── parse_tmux_client_line tests ──────────────────────────────────── */

static void test_parse_tmux_line_focused(void)
{
    const char *line = "attached,focused 12345 %0 @1\n";
    char pane[32], win[32];
    long cpid;
    assert(parse_tmux_client_line(line, pane, sizeof(pane),
                                  win, sizeof(win), &cpid) == 1);
    assert(cpid == 12345);
    assert(strcmp(pane, "%0") == 0);
    assert(strcmp(win, "@1") == 0);
}

static void test_parse_tmux_line_not_focused(void)
{
    const char *line = "attached 12345 %0 @1\n";
    char pane[32], win[32];
    long cpid;
    assert(parse_tmux_client_line(line, pane, sizeof(pane),
                                  win, sizeof(win), &cpid) == 0);
}

static void test_parse_tmux_line_focused_utf8(void)
{
    /* Real tmux format with multiple flags */
    const char *line = "attached,focused,UTF-8 98765 %3 @2\n";
    char pane[32], win[32];
    long cpid;
    assert(parse_tmux_client_line(line, pane, sizeof(pane),
                                  win, sizeof(win), &cpid) == 1);
    assert(cpid == 98765);
    assert(strcmp(pane, "%3") == 0);
    assert(strcmp(win, "@2") == 0);
}

static void test_parse_tmux_line_malformed(void)
{
    char pane[32], win[32];
    long cpid;
    /* Too few fields */
    assert(parse_tmux_client_line("focused 123", pane, sizeof(pane),
                                  win, sizeof(win), &cpid) == 0);
    /* Empty */
    assert(parse_tmux_client_line("", pane, sizeof(pane),
                                  win, sizeof(win), &cpid) == 0);
}

/* ── is_ancestor_of tests (mocked) ─────────────────────────────────── */

static void test_ancestor_direct_parent(void)
{
    ppid_fn = mock_get_ppid;
    mock_tree_clear();
    mock_tree_add(100, 50);
    mock_tree_add(50, 1);
    assert(is_ancestor_of(50, 100) == 1);
    ppid_fn = get_ppid_proc;
}

static void test_ancestor_grandparent(void)
{
    ppid_fn = mock_get_ppid;
    mock_tree_clear();
    mock_tree_add(100, 50);
    mock_tree_add(50, 25);
    mock_tree_add(25, 10);
    mock_tree_add(10, 1);
    assert(is_ancestor_of(10, 100) == 1);
    assert(is_ancestor_of(25, 100) == 1);
    ppid_fn = get_ppid_proc;
}

static void test_ancestor_not_related(void)
{
    ppid_fn = mock_get_ppid;
    mock_tree_clear();
    mock_tree_add(100, 50);
    mock_tree_add(50, 1);
    assert(is_ancestor_of(999, 100) == 0);
    ppid_fn = get_ppid_proc;
}

static void test_ancestor_self(void)
{
    ppid_fn = mock_get_ppid;
    mock_tree_clear();
    mock_tree_add(100, 50);
    mock_tree_add(50, 1);
    assert(is_ancestor_of(100, 100) == 1);
    ppid_fn = get_ppid_proc;
}

static void test_ancestor_deep_chain(void)
{
    ppid_fn = mock_get_ppid;
    mock_tree_clear();
    /* Create a chain of 70 processes — exceeds the 64 iteration limit */
    for (int i = 70; i > 1; i--)
        mock_tree_add(i, i - 1);
    /* Ancestor at depth 63 should be found */
    assert(is_ancestor_of(70 - 63, 70) == 1);
    /* Ancestor at depth 65+ should NOT be found (iteration limit) */
    assert(is_ancestor_of(2, 70) == 0);
    ppid_fn = get_ppid_proc;
}

/* ── is_valid_move tests ───────────────────────────────────────────── */

static void test_valid_move_left(void)
{
    assert(is_valid_move("-L", 100, 50, 50, 50) == 1);   /* moved left */
    assert(is_valid_move("-L", 100, 50, 200, 50) == 0);  /* wrapped right */
}

static void test_valid_move_right(void)
{
    assert(is_valid_move("-R", 50, 50, 100, 50) == 1);   /* moved right */
    assert(is_valid_move("-R", 50, 50, 10, 50) == 0);    /* wrapped left */
}

static void test_valid_move_up(void)
{
    assert(is_valid_move("-U", 50, 100, 50, 50) == 1);   /* moved up */
    assert(is_valid_move("-U", 50, 100, 50, 200) == 0);  /* wrapped down */
}

static void test_valid_move_down(void)
{
    assert(is_valid_move("-D", 50, 50, 50, 100) == 1);   /* moved down */
    assert(is_valid_move("-D", 50, 50, 50, 10) == 0);    /* wrapped up */
}

static void test_valid_move_invalid_flag(void)
{
    assert(is_valid_move("-X", 50, 50, 100, 100) == 0);
}

/* ── get_ppid tests (real /proc) ───────────────────────────────────── */

static void test_get_ppid_self(void)
{
    long my_ppid = get_ppid_proc(getpid());
    assert(my_ppid == getppid());
}

static void test_get_ppid_nonexistent(void)
{
    assert(get_ppid_proc(999999999) == -1);
}


/* ── parse_proc_stat tests ─────────────────────────────────────────── */

static void test_proc_stat_simple(void)
{
    ProcStat ps;
    /* pid (comm) state ppid pgrp session tty_nr tpgid ... */
    assert(parse_proc_stat("4242 (nvim) S 100 4242 4242 34816 4242 4194304 ...",
                           &ps) == 0);
    assert(strcmp(ps.comm, "nvim") == 0);
    assert(ps.state == 'S');
    assert(ps.ppid  == 100);
    assert(ps.pgrp  == 4242);
    assert(ps.tpgid == 4242);
}

static void test_proc_stat_comm_with_spaces_and_parens(void)
{
    /* comm is only bounded by the LAST ')' — counting fields from the
     * left would misread every field after it. */
    ProcStat ps;
    assert(parse_proc_stat("77 (nvim (v0.11)) S 5 66 66 34816 88 0 0",
                           &ps) == 0);
    assert(strcmp(ps.comm, "nvim (v0.11)") == 0);
    assert(ps.ppid  == 5);
    assert(ps.pgrp  == 66);
    assert(ps.tpgid == 88);
}

static void test_proc_stat_backgrounded(void)
{
    /* Ctrl-Z'd vim: its group is not the one the tty reads from. */
    ProcStat ps;
    assert(parse_proc_stat("9 (nvim) T 5 900 900 34816 500 0 0", &ps) == 0);
    assert(ps.pgrp != ps.tpgid);
    assert(ps.state == 'T');
}

static void test_proc_stat_stopped_but_still_foreground(void)
{
    /* Started by a shell with no job control (`bash -c nvim`): Ctrl-Z
     * stops it, yet its group still owns the tty — so pgrp == tpgid is
     * not on its own enough to prove it can act on a key. */
    ProcStat ps;
    assert(parse_proc_stat("9 (nvim) T 5 900 900 34816 900 0 0", &ps) == 0);
    assert(ps.pgrp == ps.tpgid);
    assert(ps.state == 'T');
}

static void test_proc_stat_no_tty(void)
{
    /* A daemon has no controlling tty: tpgid is -1, never a match. */
    ProcStat ps;
    assert(parse_proc_stat("3 (foot) S 1 3 3 0 -1 0 0", &ps) == 0);
    assert(ps.tpgid == -1);
    assert(ps.pgrp != ps.tpgid);
}

static void test_proc_stat_malformed(void)
{
    ProcStat ps;
    assert(parse_proc_stat("", &ps) == -1);
    assert(parse_proc_stat(NULL, &ps) == -1);
    assert(parse_proc_stat("4242 nvim S 100", &ps) == -1);      /* no parens */
    assert(parse_proc_stat("4242 (nvim) S", &ps) == -1);        /* truncated */
}

/* ── is_vim_command tests ──────────────────────────────────────────── */

static void test_is_vim_command_matches(void)
{
    assert(is_vim_command("nvim"));
    assert(is_vim_command("vim"));
    assert(is_vim_command("NVIM"));          /* case insensitive */
    assert(is_vim_command("view"));
    assert(is_vim_command("nvim (v0.11)"));
}

static void test_is_vim_command_rejects(void)
{
    assert(!is_vim_command("bash"));
    assert(!is_vim_command("foot"));
    assert(!is_vim_command("claude"));
    assert(!is_vim_command(""));
    assert(!is_vim_command(NULL));
}

/* ── build_send_shortcut tests ─────────────────────────────────────── */

static void test_send_shortcut_command(void)
{
    char cmd[256];
    build_send_shortcut(cmd, sizeof(cmd), "0x559f2dca5ed0", 'h');
    assert(strstr(cmd, "hyprctl dispatch") != NULL);
    assert(strstr(cmd, "hl.dsp.send_shortcut") != NULL);
    assert(strstr(cmd, "mods = \"ALT\"") != NULL);
    assert(strstr(cmd, "key = \"h\"") != NULL);
    assert(strstr(cmd, "window = \"address:0x559f2dca5ed0\"") != NULL);
}

static void test_send_shortcut_quoting(void)
{
    /* The Lua table needs double quotes inside, so the shell word has to
     * be single-quoted — one unbalanced quote and hyprctl gets garbage. */
    char cmd[256];
    build_send_shortcut(cmd, sizeof(cmd), "0xabc", 'l');
    int singles = 0;
    for (const char *p = cmd; *p; p++) if (*p == '\'') singles++;
    assert(singles == 2);
    assert(strchr(cmd, '\'') < strstr(cmd, "hl.dsp.send_shortcut"));
}

static void test_send_shortcut_all_directions(void)
{
    for (int i = 0; i < 4; i++) {
        char cmd[256], want[32];
        build_send_shortcut(cmd, sizeof(cmd), "0x1", dirs[i].akey);
        snprintf(want, sizeof(want), "key = \"%c\"", dirs[i].akey);
        assert(strstr(cmd, want) != NULL);
    }
}

/* ── find_foreground_vim tests (real /proc) ────────────────────────── */

static void test_find_foreground_vim_none(void)
{
    /* This test binary is not a vim and has no vim children. */
    assert(find_foreground_vim((long)getpid()) == 0);
}

static void test_find_foreground_vim_bad_root(void)
{
    assert(find_foreground_vim(999999999L) == 0);
}

/* ── Main ──────────────────────────────────────────────────────────── */

int main(void)
{
    printf("\n=== hypr-nav unit tests ===\n\n");

    printf("dir_lookup:\n");
    RUN(test_dir_lookup_left);
    RUN(test_dir_lookup_down);
    RUN(test_dir_lookup_up);
    RUN(test_dir_lookup_right);
    RUN(test_dir_lookup_invalid);

    printf("\nis_terminal:\n");
    RUN(test_is_terminal_ghostty);
    RUN(test_is_terminal_kitty);
    RUN(test_is_terminal_alacritty);
    RUN(test_is_terminal_foot);
    RUN(test_is_terminal_wezterm);
    RUN(test_is_terminal_generic);
    RUN(test_is_terminal_non_terminal);

    printf("\nparse_active_window:\n");
    RUN(test_parse_window_full);
    RUN(test_parse_window_missing_pid);
    RUN(test_parse_window_missing_class);
    RUN(test_parse_window_empty);
    RUN(test_parse_window_large_pid);

    printf("\nparse_tmux_client_line:\n");
    RUN(test_parse_tmux_line_focused);
    RUN(test_parse_tmux_line_not_focused);
    RUN(test_parse_tmux_line_focused_utf8);
    RUN(test_parse_tmux_line_malformed);

    printf("\nis_ancestor_of (mocked):\n");
    RUN(test_ancestor_direct_parent);
    RUN(test_ancestor_grandparent);
    RUN(test_ancestor_not_related);
    RUN(test_ancestor_self);
    RUN(test_ancestor_deep_chain);

    printf("\nis_valid_move:\n");
    RUN(test_valid_move_left);
    RUN(test_valid_move_right);
    RUN(test_valid_move_up);
    RUN(test_valid_move_down);
    RUN(test_valid_move_invalid_flag);

    printf("\nparse_proc_stat:\n");
    RUN(test_proc_stat_simple);
    RUN(test_proc_stat_comm_with_spaces_and_parens);
    RUN(test_proc_stat_backgrounded);
    RUN(test_proc_stat_stopped_but_still_foreground);
    RUN(test_proc_stat_no_tty);
    RUN(test_proc_stat_malformed);

    printf("\nis_vim_command:\n");
    RUN(test_is_vim_command_matches);
    RUN(test_is_vim_command_rejects);

    printf("\nbuild_send_shortcut:\n");
    RUN(test_send_shortcut_command);
    RUN(test_send_shortcut_quoting);
    RUN(test_send_shortcut_all_directions);

    printf("\nfind_foreground_vim (real /proc):\n");
    RUN(test_find_foreground_vim_none);
    RUN(test_find_foreground_vim_bad_root);

    printf("\nget_ppid (real /proc):\n");
    RUN(test_get_ppid_self);
    RUN(test_get_ppid_nonexistent);

    printf("\n%d/%d tests passed\n\n", tests_passed, tests_run);
    return tests_passed == tests_run ? 0 : 1;
}
