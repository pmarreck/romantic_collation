/* The Zig shared library is the oracle. Neither implementation source is
 * available to this independently compiled public-ABI consumer. */
#include "romantic_collation.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
	void *library;
	rcol_status (*open)(const rcol_config *, rcol_collator **);
	void (*close)(rcol_collator *);
	rcol_status (*key)(const rcol_collator *,const uint8_t *,size_t,uint8_t *,size_t,size_t *);
	rcol_status (*compare)(const rcol_collator *,const uint8_t *,size_t,const uint8_t *,size_t,int32_t *);
	const char *(*version)(void);
	uint32_t (*ordering)(void);
	const char *(*status)(rcol_status);
	rcol_collator *handles[128];
} api;

static void load_symbol(void *lib,const char *name,void *out,size_t size) {
	void *symbol=dlsym(lib,name);
	if (!symbol || size!=sizeof symbol) {fprintf(stderr,"missing ABI symbol: %s\n",name);exit(1);}
	memcpy(out,&symbol,size);
}
#define LOAD(field,name) load_symbol(a.library,name,&a.field,sizeof a.field)
static api load(const char *path) {
	api a={0}; a.library=dlopen(path,RTLD_NOW|RTLD_LOCAL);
	if (!a.library) {fprintf(stderr,"%s\n",dlerror());exit(1);}
	LOAD(open,"rcol_open"); LOAD(close,"rcol_close"); LOAD(key,"rcol_sort_key_utf8");
	LOAD(compare,"rcol_compare_utf8"); LOAD(version,"rcol_version");
	LOAD(ordering,"rcol_ordering_version"); LOAD(status,"rcol_status_name");
	for (uint32_t mask=0;mask<128;mask++) {
		rcol_config cfg=RCOL_CONFIG_INIT(mask);
		if (a.open(&cfg,&a.handles[mask])!=RCOL_OK || !a.handles[mask]) exit(1);
	}
	return a;
}

static uint8_t left_key[262144],right_key[262144];
static size_t cases=0;
static void check(api *oracle,api *candidate,uint32_t mask,const uint8_t *s,size_t n) {
	size_t a=0,b=0;
	rcol_status sa=oracle->key(oracle->handles[mask],s,n,left_key,sizeof left_key,&a);
	rcol_status sb=candidate->key(candidate->handles[mask],s,n,right_key,sizeof right_key,&b);
	if (sa!=RCOL_OK || sb!=sa || a!=b || memcmp(left_key,right_key,a)) {
		fprintf(stderr,"key parity failed: options=%u bytes=",mask);
		for (size_t i=0;i<n && i<100;i++) fprintf(stderr,"%02x",s[i]);
		fprintf(stderr," status=%d/%d length=%zu/%zu\n",sa,sb,a,b);
		for (size_t i=0;i<a || i<b;i++) if (i>=a || i>=b || left_key[i]!=right_key[i]) {
			fprintf(stderr,"first differing offset=%zu oracle=%02x rust=%02x\n",i,i<a?left_key[i]:0,i<b?right_key[i]:0);break;
		}
		exit(1);
	}
	cases++;
}

/* The caller may retry with an exact buffer, including a buffer that aliases
 * the input. A length probe or undersized output must write no key bytes. */
static void check_buffer(api *oracle,api *candidate,uint32_t mask,const uint8_t *s,size_t n) {
	size_t need=0, reported=0;
	uint8_t storage[1024], expected[sizeof storage];
	if (oracle->key(oracle->handles[mask],s,n,expected,sizeof expected,&need)!=RCOL_OK ||
		need<2 || need>=sizeof storage || n>=sizeof storage) exit(1);
	memset(storage,0x7b,sizeof storage);
	rcol_collator *coll=candidate->handles[mask];
	if (candidate->key(coll,s,n,NULL,0,&reported)!=RCOL_OK || reported!=need ||
		candidate->key(coll,s,n,storage,need-1,&reported)!=RCOL_BUFFER_TOO_SMALL || reported!=need) {
		fprintf(stderr,"key sizing failed: options=%u length=%zu\n",mask,n);
		exit(1);
	}
	for (size_t i=0;i<sizeof storage;i++) if (storage[i]!=0x7b) {
		fprintf(stderr,"undersized key write: options=%u length=%zu offset=%zu\n",mask,n,i);
		exit(1);
	}
	memcpy(storage,s,n);
	uint8_t canary=storage[need];
	if (candidate->key(coll,storage,n,storage,need,&reported)!=RCOL_OK ||
		reported!=need || memcmp(storage,expected,need) || storage[need]!=canary) {
		fprintf(stderr,"key buffer contract failed: options=%u length=%zu\n",mask,n);
		exit(1);
	}
	cases++;
}
static uint32_t rng(uint32_t *s) { *s^=*s<<13;*s^=*s>>17;*s^=*s<<5;return *s; }

int main(int argc,char **argv) {
	if (argc!=3) return 2;
	api oracle=load(argv[1]),candidate=load(argv[2]);
	if (strcmp(oracle.version(),candidate.version()) || oracle.ordering()!=candidate.ordering()) return 1;
	for (int status=-1;status<=7;status++) if (strcmp(oracle.status(status),candidate.status(status))) return 1;
	const char *samples[]={"","file2","file10","Apple","apple","café","cafe\xcc\x81","ș","ş","s\xcc\xa6","ț",
		"VII","IX","IX™","IX—","IX2","a.IX","éIX","CIVIL","MIX","Mix","IX_","Ⅷ","½","℅","straße","coeur","cœur",
		"MMMM", "MMMMMMMMMMMMMMM", "MMMMMMMMMMMMMMMM",
		"-000５","+５","1.00","1,０００","１e５","1e9999999999","1e10000000000","10e99999999999999999999",
		"1e-100000000000000000000","0.00005e99999999999999999999999","\xff\xc0\x80","０","𝟚","𝟑","𝟒","𝟱","𝟼","中"};
	for (uint32_t mask=0;mask<128;mask++) {
		for (size_t i=0;i<sizeof samples/sizeof *samples;i++) check(&oracle,&candidate,mask,(const uint8_t *)samples[i],strlen(samples[i]));
		uint8_t binary[]={0,1,127,128,255,0,'I','X'};check(&oracle,&candidate,mask,binary,sizeof binary);
	}
	uint8_t boundary[67];
	for (size_t n=63;n<=65;n++) {
		memset(boundary,'a',sizeof boundary);
		check_buffer(&oracle,&candidate,0,boundary,n);
		memset(boundary,'9',sizeof boundary);
		check_buffer(&oracle,&candidate,0,boundary,n-32);
		memcpy(boundary,"1e",2);
		check_buffer(&oracle,&candidate,RCOL_SCIENTIFIC,boundary,n-30);
	}
	uint32_t state=0xc0ffee;
	for (size_t iteration=0;iteration<5000;iteration++) {
		uint8_t s[256];size_t n=rng(&state)%sizeof s;
		for (size_t i=0;i<n;i++) s[i]=(uint8_t)rng(&state);
		for (uint32_t mask=0;mask<128;mask++) check(&oracle,&candidate,mask,s,n);
	}
	for (uint32_t cp=0;cp<=0x10ffff;cp++) {
		uint8_t s[4];size_t n;
		if (cp<128) {s[0]=(uint8_t)cp;n=1;}
		else if (cp<2048) {s[0]=0xc0|(cp>>6);s[1]=0x80|(cp&63);n=2;}
		else if (cp<65536) {s[0]=0xe0|(cp>>12);s[1]=0x80|((cp>>6)&63);s[2]=0x80|(cp&63);n=3;}
		else {s[0]=0xf0|(cp>>18);s[1]=0x80|((cp>>12)&63);s[2]=0x80|((cp>>6)&63);s[3]=0x80|(cp&63);n=4;}
		check(&oracle,&candidate,0,s,n);check(&oracle,&candidate,64,s,n);
		/* Property tables must agree in context, not just for a scalar alone. */
		uint8_t context[8];
		memcpy(context,s,n);context[n]='I';context[n+1]='X';
		check(&oracle,&candidate,64,context,n+2);
		context[0]='I';context[1]='X';memcpy(context+2,s,n);
		check(&oracle,&candidate,64,context,n+2);
	}
	uint8_t *long_input=malloc(30000);if (!long_input) return 1;memset(long_input,'9',30000);
	for (uint32_t mask=0;mask<128;mask++) check(&oracle,&candidate,mask,long_input,30000);
	free(long_input);
	for (size_t i=0;i<128;i++) {oracle.close(oracle.handles[i]);candidate.close(candidate.handles[i]);}
	dlclose(oracle.library);dlclose(candidate.library);
	printf("backend_parity: %zu key cases; 1 passed, 0 failed\n",cases);
	return 0;
}
