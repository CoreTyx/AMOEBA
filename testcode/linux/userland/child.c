/* child -- helper for `spawn`, installed in /bin but not run by /init.
 * argv: child <n> <magic>; envp must contain SPAWN_ENV=<n>.  Exits n*7 & 0xff. */
#include "ulib.h"
static long parse(const char *s) { long v = 0; while (*s >= '0' && *s <= '9') v = v * 10 + (*s++ - '0'); return v; }
int main(int argc, char **argv, char **envp)
{
    if (argc != 3 || strcmp(argv[2], "AMOEBA") != 0) return 250;
    long n = parse(argv[1]);
    int env_ok = 0;
    for (char **e = envp; *e; e++)
        if (strncmp(*e, "SPAWN_ENV=", 10) == 0 && parse(*e + 10) == n) env_ok = 1;
    if (!env_ok) return 251;
    return (int)((n * 7) & 0xff);
}
