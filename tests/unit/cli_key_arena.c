#include <stdio.h>
#include <string.h>
#define main collate_program_main
#include "../../cli/main.c"
#undef main

int main(void) {
	key_arena arena = {0};
	rcol_collator *coll = NULL;
	rcol_config config = RCOL_CONFIG_INIT(RCOL_CODE_POINT);
	if (rcol_open(&config, &coll) != RCOL_OK) return 1;
	int failed = 0;
	uint8_t *first = NULL;
	for (size_t i = 0; i < 20000; i++) {
		uint8_t *key = NULL;
		size_t need = 0;
		rcol_status status;
		if (arena_build_key(&arena, rcol_sort_key_utf8, coll, (const uint8_t *)"file2", 5,
		                    &key, &need, &status) != SORT_KEY_OK || need != 6 || memcmp(key, "file2\0", 6)) {
			failed++; break;
		}
		if (i == 0) first = key;
	}
	if (!first || memcmp(first, "file2\0", 6)) failed++;
	if (arena.key_bytes != 120000 || arena.reserved_bytes > 2 * 65536) failed++;
	arena_deinit(&arena);
	rcol_close(coll);
	printf("cli_key_arena: %d passed, %d failed\n", 3-failed, failed);
	return failed;
}
