/* SQLite scalar keys preserve error reporting, unlike comparison callbacks. */
#include <sqlite3ext.h>
SQLITE_EXTENSION_INIT1
#include "romantic_collation.h"
#include <stdint.h>

static void key(sqlite3_context *ctx, int argc, sqlite3_value **argv) {
	if (sqlite3_value_type(argv[0]) == SQLITE_NULL ||
	    (argc == 2 && sqlite3_value_type(argv[1]) == SQLITE_NULL)) return;
	if (sqlite3_value_type(argv[0]) != SQLITE_TEXT) {
		sqlite3_result_error(ctx, "romantic_key_v1 requires TEXT", -1);
		return;
	}
	sqlite3_int64 options = 0;
	if (argc == 2) {
		if (sqlite3_value_type(argv[1]) != SQLITE_INTEGER ||
		    (options = sqlite3_value_int64(argv[1])) < 0 || options > UINT32_MAX) {
			sqlite3_result_error(ctx, "options must be an unsigned 32-bit integer", -1);
			return;
		}
	}
	rcol_config config = RCOL_CONFIG_INIT(options);
	rcol_collator *coll = NULL;
	rcol_status status = rcol_open(&config, &coll);
	if (status != RCOL_OK) goto error;
	const uint8_t *text = sqlite3_value_text(argv[0]);
	if (!text) { rcol_close(coll); sqlite3_result_error_nomem(ctx); return; }
	size_t len = (size_t)sqlite3_value_bytes(argv[0]);
	size_t limit = (size_t)sqlite3_limit(sqlite3_context_db_handle(ctx), SQLITE_LIMIT_LENGTH, -1);
	if (limit < 16) { rcol_close(coll); sqlite3_result_error_toobig(ctx); return; }
	size_t cap = len > (limit - 16) / 6 ? limit : len * 6 + 16;
	uint8_t *buffer = sqlite3_malloc64(cap);
	if (!buffer) { rcol_close(coll); sqlite3_result_error_nomem(ctx); return; }
	size_t need = 0;
	status = rcol_sort_key_utf8(coll, text, len, buffer, cap, &need);
	if (status == RCOL_BUFFER_TOO_SMALL && need <= limit) {
		uint8_t *grown = sqlite3_realloc64(buffer, need);
		if (!grown) { sqlite3_free(buffer); rcol_close(coll); sqlite3_result_error_nomem(ctx); return; }
		buffer = grown;
		status = rcol_sort_key_utf8(coll, text, len, buffer, need, &need);
	}
	rcol_close(coll);
	if (status == RCOL_BUFFER_TOO_SMALL) {
		sqlite3_free(buffer); sqlite3_result_error_toobig(ctx); return;
	}
	if (status != RCOL_OK) { sqlite3_free(buffer); goto error; }
	sqlite3_result_blob64(ctx, buffer, need, sqlite3_free);
	return;
error:
	if (status == RCOL_OUT_OF_MEMORY) sqlite3_result_error_nomem(ctx);
	else sqlite3_result_error(ctx, rcol_status_name(status), -1);
}

#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_romantic_init(sqlite3 *db, char **error, const sqlite3_api_routines *api) {
	(void)error;
	SQLITE_EXTENSION_INIT2(api);
	if (rcol_ordering_version() != 1) return SQLITE_MISMATCH;
	int flags = SQLITE_UTF8 | SQLITE_DETERMINISTIC | SQLITE_INNOCUOUS;
	int rc = sqlite3_create_function_v2(db, "romantic_key_v1", 1, flags, NULL, key, NULL, NULL, NULL);
	if (rc == SQLITE_OK)
		rc = sqlite3_create_function_v2(db, "romantic_key_v1", 2, flags, NULL, key, NULL, NULL, NULL);
	return rc;
}
