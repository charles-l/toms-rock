extern void web_main(void);

#include "raylib/src/raylib.h"
#include <stdio.h>

void DoClear(const Color *c, const Color d) {
    //TraceLog(LOG_ERROR, ">>> paddr: %p %x %x %x %x", &d, c->r, c->g, c->b, c->a);
    ClearBackground(*c);
}

void DoText(const char *text, int x, int y, int size) {
    DrawText(text, x, y, size, LIGHTGRAY);
}


int main() {
    web_main();
    return 0;
}
