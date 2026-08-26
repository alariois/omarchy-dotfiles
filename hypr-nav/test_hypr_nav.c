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
}

static void test_dir_lookup_down(void)
{
    const Dir *d = dir_lookup('d');
    assert(d != NULL);
    assert(d->key == 'd');
    assert(strcmp(d->tflag, "-D") == 0);
    assert(strcmp(d->vkey, "M-j") == 0);
}

static void test_dir_lookup_up(void)
{
    const Dir *d = dir_lookup('u');
    assert(d != NULL);
    assert(d->key == 'u');
    assert(strcmp(d->tflag, "-U") == 0);
    assert(strcmp(d->vkey, "M-k") == 0);
}

static void test_dir_lookup_right(void)
{
    const Dir *d = dir_lookup('r');
    assert(d != NULL);
    assert(d->key == 'r');
    assert(strcmp(d->tflag, "-R") == 0);
    assert(strcmp(d->vkey, "M-l") == 0);
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
}

static void test_parse_window_missing_pid(void)
{
    const char *json = "{\"class\":\"kitty\",\"title\":\"bash\"}";
    WinInfo w;
    assert(parse_active_window(json, &w) == 0);
    assert(w.pid == 0);
    assert(strcmp(w.class, "kitty") == 0);
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

    printf("\nget_ppid (real /proc):\n");
    RUN(test_get_ppid_self);
    RUN(test_get_ppid_nonexistent);

    printf("\n%d/%d tests passed\n\n", tests_passed, tests_run);
    return tests_passed == tests_run ? 0 : 1;
}
