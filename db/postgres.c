/* PostgreSQL returns bytea so ordering/indexing never consults an OS locale. */
#include "postgres.h"
#include "fmgr.h"
#include "varatt.h"
#include "mb/pg_wchar.h"
#include "utils/builtins.h"
#include "utils/memutils.h"
#include "romantic_collation.h"

PG_MODULE_MAGIC;
PG_FUNCTION_INFO_V1(romantic_key_v2);

Datum romantic_key_v2(PG_FUNCTION_ARGS) {
	if (rcol_ordering_version() != RCOL_ORDERING_VERSION)
		ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED), errmsg("romantic_key_v2 requires ordering revision 2")));
	if (GetDatabaseEncoding() != PG_UTF8)
		ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED), errmsg("romantic_key_v2 requires a UTF8 database")));
	text *input = PG_GETARG_TEXT_PP(0);
	int32 options = PG_GETARG_INT32(1);
	if (options < 0)
		ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE), errmsg("options must be nonnegative")));
	size_t len = VARSIZE_ANY_EXHDR(input);
	if (len > (MaxAllocSize - VARHDRSZ - 16) / 6)
		ereport(ERROR, (errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED), errmsg("romantic sort key input is too large")));
	size_t cap = len * 6 + 16;
	bytea *result = palloc(VARHDRSZ + cap);
	rcol_config config = RCOL_CONFIG_INIT(options);
	rcol_collator *coll = NULL;
	rcol_status status = rcol_open(&config, &coll);
	size_t need = 0;
	if (status == RCOL_OK)
		status = rcol_sort_key_utf8(coll, (const uint8_t *)VARDATA_ANY(input), len,
		                          (uint8_t *)VARDATA(result), cap, &need);
	/* Close before any PostgreSQL longjmp, including allocation errors. */
	rcol_close(coll);
	if (status == RCOL_BUFFER_TOO_SMALL && need <= MaxAllocSize - VARHDRSZ) {
		result = repalloc(result, VARHDRSZ + need);
		status = rcol_open(&config, &coll);
		if (status == RCOL_OK)
			status = rcol_sort_key_utf8(coll, (const uint8_t *)VARDATA_ANY(input), len,
			                          (uint8_t *)VARDATA(result), need, &need);
		rcol_close(coll);
	}
	if (status != RCOL_OK)
		ereport(ERROR, (errcode(status == RCOL_OUT_OF_MEMORY ? ERRCODE_OUT_OF_MEMORY : ERRCODE_INVALID_PARAMETER_VALUE),
		                errmsg("romantic sort key: %s", rcol_status_name(status))));
	SET_VARSIZE(result, VARHDRSZ + need);
	PG_FREE_IF_COPY(input, 0);
	PG_RETURN_BYTEA_P(result);
}
