/* BEAM adapter over the Rust implementation's packaged C ABI. CPU-bound work
 * always uses dirty schedulers; no native pointer or state escapes to Elixir. */
#include <erl_nif.h>
#include "romantic_collation.h"
#include <string.h>

typedef struct { rcol_collator *coll[128]; } state;
static int load(ErlNifEnv *env,void **private,ERL_NIF_TERM info) {
	(void)env; (void)info;
	if (rcol_ordering_version()!=1) return -1;
	state *s=enif_alloc(sizeof *s);if (!s) return -1;
	memset(s,0,sizeof *s);
	for (unsigned i=0;i<128;i++) {
		rcol_config cfg=RCOL_CONFIG_INIT(i);
		if (rcol_open(&cfg,&s->coll[i])!=RCOL_OK) {
			for (unsigned j=0;j<i;j++) rcol_close(s->coll[j]);
			enif_free(s);return -1;
		}
	}
	*private=s;return 0;
}
static void unload(ErlNifEnv *env,void *private) {
	(void)env;state *s=private;
	for (unsigned i=0;i<128;i++) rcol_close(s->coll[i]);
	enif_free(s);
}
static ERL_NIF_TERM failure(ErlNifEnv *env,rcol_status status) {
	const char *reason=status==RCOL_OUT_OF_MEMORY?"out_of_memory":"internal_error";
	return enif_raise_exception(env,enif_make_tuple2(env,enif_make_atom(env,"romantic_collation"),enif_make_atom(env,reason)));
}
static int options(ErlNifEnv *env,ERL_NIF_TERM term,unsigned *mask) {
	return enif_get_uint(env,term,mask) && *mask<128;
}
static ERL_NIF_TERM make_key(ErlNifEnv *env,const ErlNifBinary *input,unsigned mask) {
	state *s=enif_priv_data(env);
	uint8_t scratch[2048];size_t need=0;
	rcol_status status=rcol_sort_key_utf8(s->coll[mask],input->data,input->size,scratch,sizeof scratch,&need);
	if (status!=RCOL_OK && status!=RCOL_BUFFER_TOO_SMALL) return failure(env,status);
	ERL_NIF_TERM term;
	uint8_t *output=enif_make_new_binary(env,need,&term);
	if (!output) return failure(env,RCOL_OUT_OF_MEMORY);
	if (status==RCOL_OK) memcpy(output,scratch,need);
	else {
		status=rcol_sort_key_utf8(s->coll[mask],input->data,input->size,output,need,&need);
		if (status!=RCOL_OK) return failure(env,status);
	}
	return term;
}
static ERL_NIF_TERM key(ErlNifEnv *env,int argc,const ERL_NIF_TERM argv[]) {
	(void)argc;ErlNifBinary input;unsigned mask;
	if (!enif_inspect_binary(env,argv[0],&input) || !options(env,argv[1],&mask)) return enif_make_badarg(env);
	return make_key(env,&input,mask);
}
static ERL_NIF_TERM compare(ErlNifEnv *env,int argc,const ERL_NIF_TERM argv[]) {
	(void)argc;ErlNifBinary a,b;unsigned mask;int32_t order=0;state *s=enif_priv_data(env);
	if (!enif_inspect_binary(env,argv[0],&a) || !enif_inspect_binary(env,argv[1],&b) || !options(env,argv[2],&mask)) return enif_make_badarg(env);
	rcol_status status=rcol_compare_utf8(s->coll[mask],a.data,a.size,b.data,b.size,&order);
	if (status!=RCOL_OK) return failure(env,status);
	return enif_make_atom(env,order<0?"lt":order>0?"gt":"eq");
}
static ERL_NIF_TERM keys(ErlNifEnv *env,int argc,const ERL_NIF_TERM argv[]) {
	(void)argc;unsigned mask;
	if (!options(env,argv[1],&mask)) return enif_make_badarg(env);
	ERL_NIF_TERM head,tail=argv[0],result=enif_make_list(env,0);
	while (enif_get_list_cell(env,tail,&head,&tail)) {
		ErlNifBinary input;
		if (!enif_inspect_binary(env,head,&input)) return enif_make_badarg(env);
		ERL_NIF_TERM value=make_key(env,&input,mask);
		if (enif_is_exception(env,value)) return value;
		result=enif_make_list_cell(env,value,result);
	}
	if (!enif_is_empty_list(env,tail)) return enif_make_badarg(env);
	ERL_NIF_TERM reversed;
	if (!enif_make_reverse_list(env,result,&reversed)) return enif_make_badarg(env);
	return reversed;
}
static ErlNifFunc functions[]={
	{"key",2,key,ERL_NIF_DIRTY_JOB_CPU_BOUND},
	{"keys",2,keys,ERL_NIF_DIRTY_JOB_CPU_BOUND},
	{"compare",3,compare,ERL_NIF_DIRTY_JOB_CPU_BOUND}
};
ERL_NIF_INIT(Elixir.RomanticCollation.Native,functions,load,NULL,NULL,unload)
