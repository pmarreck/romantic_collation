/* A separately compiled consumer checks the installed-style public boundary. */
#include "romantic_collation.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

_Static_assert(sizeof(rcol_status) == 4, "status ABI width");
_Static_assert(offsetof(rcol_config, abi_version) == sizeof(size_t), "config ABI offset");
_Static_assert(offsetof(rcol_config, options) == sizeof(size_t) + 4, "config ABI offset");

int main(void) {
	int fail = 0;
	const uint8_t input[] = {'a', 0, 'b', 0xff};
	uint8_t output[128];
	size_t need = 0;
	rcol_collator *coll = NULL;
	rcol_config cfg = RCOL_CONFIG_INIT(RCOL_CODE_POINT);
	if (rcol_ordering_version() != 1) fail++;
	if (rcol_open(&cfg, &coll) != RCOL_OK || !coll) return 1;
	if (rcol_sort_key_utf8(coll, input, sizeof input, output, sizeof output, &need) != RCOL_OK ||
	    need != sizeof input + 1 || memcmp(output, input, sizeof input) || output[sizeof input] != 0) fail++;
	int32_t order = 77;
	if (rcol_compare_utf8(coll, input, sizeof input, input, 1, &order) != RCOL_OK || order != RCOL_GREATER) fail++;
	order = 77;
	if (rcol_compare_utf8(NULL, input, sizeof input, input, 1, &order) != RCOL_INVALID_ARGUMENT || order != 77) fail++;
	rcol_close(coll);
	printf("ffi_contract: %d passed, %d failed\n", 4-fail, fail);
	return fail;
}
