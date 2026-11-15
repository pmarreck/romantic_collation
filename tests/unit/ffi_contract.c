/* A separately compiled consumer checks the installed-style public boundary. */
#include "romantic_collation.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

_Static_assert(sizeof(rcol_status) == 4, "status ABI width");
_Static_assert(offsetof(rcol_config, abi_version) == sizeof(size_t), "config ABI offset");
_Static_assert(offsetof(rcol_config, options) == sizeof(size_t) + 4, "config ABI offset");

int main(void) {
	int fail = 0, checks = 0;
#define CHECK(condition) do { checks++; if (!(condition)) { fprintf(stderr, "ABI check failed at line %d\n", __LINE__); fail++; } } while (0)
	const uint8_t input[] = {'a', 0, 'b', 0xff};
	uint8_t output[128];
	size_t need = 0;
	rcol_collator *coll = NULL;
	rcol_config cfg = RCOL_CONFIG_INIT(RCOL_CODE_POINT);
	CHECK(rcol_ordering_version() == 1);
	CHECK(strcmp(rcol_version(), "0.1.0") == 0);
	CHECK(strcmp(rcol_status_name(RCOL_INTERNAL_ERROR), "internal error") == 0);
	if (rcol_open(&cfg, &coll) != RCOL_OK || !coll) return 1;
	CHECK(rcol_sort_key_utf8(coll, input, sizeof input, output, sizeof output, &need) == RCOL_OK &&
	    need == sizeof input + 1 && !memcmp(output, input, sizeof input) && output[sizeof input] == 0);
	CHECK(rcol_sort_key_utf8(coll, input, sizeof input, NULL, 0, &need) == RCOL_OK && need == sizeof input + 1);
	memset(output, 0x7b, sizeof output);
	CHECK(rcol_sort_key_utf8(coll, input, sizeof input, output, 1, &need) == RCOL_BUFFER_TOO_SMALL && need == sizeof input + 1);
	for (size_t i = 0; i < sizeof output; i++) CHECK(output[i] == 0x7b);
	CHECK(rcol_sort_key_utf8(coll, NULL, 0, output, sizeof output, &need) == RCOL_OK && need == 1 && output[0] == 0);
	CHECK(rcol_sort_key_utf8(coll, NULL, 1, output, sizeof output, &need) == RCOL_INVALID_ARGUMENT && need == 0);
	CHECK(rcol_sort_key_utf8(coll, input, sizeof input, NULL, 1, &need) == RCOL_INVALID_ARGUMENT && need == 0);
	CHECK(rcol_sort_key_utf8(coll, input, sizeof input, output, sizeof output, NULL) == RCOL_INVALID_ARGUMENT);
	int32_t order = 77;
	CHECK(rcol_compare_utf8(coll, input, sizeof input, input, 1, &order) == RCOL_OK && order == RCOL_GREATER);
	order = 77;
	CHECK(rcol_compare_utf8(NULL, input, sizeof input, input, 1, &order) == RCOL_INVALID_ARGUMENT && order == 77);
	CHECK(rcol_compare_utf8(coll, NULL, 1, input, 1, &order) == RCOL_INVALID_ARGUMENT && order == 77);
	CHECK(rcol_compare_utf8(coll, NULL, 0, NULL, 0, &order) == RCOL_OK && order == RCOL_EQUAL);
	rcol_close(coll);
	rcol_close(NULL);
	coll = (rcol_collator *)(void *)&cfg;
	CHECK(rcol_open(NULL, &coll) == RCOL_INVALID_ARGUMENT && coll == NULL);
	CHECK(rcol_open(&cfg, NULL) == RCOL_INVALID_ARGUMENT);
	cfg.abi_version++;
	CHECK(rcol_open(&cfg, &coll) == RCOL_UNSUPPORTED_ABI && coll == NULL);
	cfg.abi_version--;
	cfg.options = 128;
	CHECK(rcol_open(&cfg, &coll) == RCOL_UNSUPPORTED_OPTION && coll == NULL);
	cfg.struct_size = 0;
	CHECK(rcol_open(&cfg, &coll) == RCOL_INVALID_ARGUMENT && coll == NULL);
	/* Every option mask also checks that direct comparison agrees with binary
	 * key order through the separately installed ABI, including embedded NULs. */
	for (uint32_t mask = 0; mask < 128; mask++) {
		rcol_config c = RCOL_CONFIG_INIT(mask);
		uint8_t other[128]; size_t n = 0, m = 0;
		CHECK(rcol_open(&c, &coll) == RCOL_OK && coll != NULL);
		if (!coll) continue;
		CHECK(rcol_sort_key_utf8(coll, input, sizeof input, output, sizeof output, &n) == RCOL_OK);
		CHECK(rcol_sort_key_utf8(coll, input, 1, other, sizeof other, &m) == RCOL_OK);
		int key_order = memcmp(output, other, n < m ? n : m);
		if (!key_order) key_order = (n > m) - (n < m);
		CHECK(rcol_compare_utf8(coll, input, sizeof input, input, 1, &order) == RCOL_OK && order == (key_order > 0) - (key_order < 0));
		rcol_close(coll);
	}
	printf("ffi_contract: %d passed, %d failed\n", checks-fail, fail);
	return fail;
}
