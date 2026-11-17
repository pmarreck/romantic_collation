/* Independent acceptance oracle: parse official Unicode files here, without
 * access to either implementation's classifiers or generated range tables. */
#include "romantic_collation.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned char properties[0x110000];
enum { SPACE=1, PUNCT=2 };
static void die(const char *message) { fprintf(stderr,"structural_unicode: %s\n",message); exit(1); }
static void source(const char *path,int prop_list) {
	FILE *file=fopen(path,"r"); if (!file) die("cannot open Unicode data");
	char line[2048];
	while (fgets(line,sizeof line,file)) {
		if (line[0]=='#' || line[0]=='\n') continue;
		unsigned first=0,last=0; int flag=0;
		if (prop_list) {
			char *sep=strchr(line,';'); if (!sep) continue;
			char property[80]; if (sscanf(sep+1,"%79s",property)!=1) die("invalid property row");
			if (strcmp(property,"White_Space")) continue;
			if (sscanf(line,"%x..%x",&first,&last)!=2) { if (sscanf(line,"%x",&first)!=1) die("invalid range"); last=first; }
			flag=SPACE;
		} else {
			char *name=strchr(line,';'); if (!name) die("missing Unicode name");
			char *category=strchr(name+1,';'); if (!category) die("missing Unicode category");
			if (category[1]!='P') continue;
			if (sscanf(line,"%x",&first)!=1) die("invalid code point");
			last=first; flag=PUNCT;
		}
		if (last>=sizeof properties || first>last) die("Unicode range outside scalar domain");
		for (unsigned cp=first;cp<=last;cp++) properties[cp]|=(unsigned char)flag;
	}
	if (ferror(file) || fclose(file)) die("Unicode source read failed");
}
static void symbol(void *module,const char *name,void *out,size_t size) {
	void *p=dlsym(module,name); if (!p || size!=sizeof p) die("missing public ABI export"); memcpy(out,&p,size);
}
static int compare(const uint8_t *a,size_t n,const uint8_t *b,size_t m) {
	int order=memcmp(a,b,n<m?n:m); return order?order:(n>m)-(n<m);
}
static size_t utf8(unsigned cp,uint8_t *out) {
	if (cp<0x80) {out[0]=(uint8_t)cp;return 1;}
	if (cp<0x800) {out[0]=0xc0|(cp>>6);out[1]=0x80|(cp&63);return 2;}
	if (cp<0x10000) {out[0]=0xe0|(cp>>12);out[1]=0x80|((cp>>6)&63);out[2]=0x80|(cp&63);return 3;}
	out[0]=0xf0|(cp>>18);out[1]=0x80|((cp>>12)&63);out[2]=0x80|((cp>>6)&63);out[3]=0x80|(cp&63);return 4;
}
int main(int argc,char **argv) {
	if (argc!=4) return 2;
	source(argv[2],0); source(argv[3],1);
	void *module=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL); if (!module) die(dlerror());
	rcol_status (*open_coll)(const rcol_config *,rcol_collator **);
	void (*close_coll)(rcol_collator *);
	rcol_status (*key)(const rcol_collator *,const uint8_t *,size_t,uint8_t *,size_t,size_t *);
	symbol(module,"rcol_open",&open_coll,sizeof open_coll); symbol(module,"rcol_close",&close_coll,sizeof close_coll);
	symbol(module,"rcol_sort_key_utf8",&key,sizeof key);
	rcol_collator *house=NULL,*raw=NULL; rcol_config cfg=RCOL_CONFIG_INIT(0);
	if (open_coll(&cfg,&house)!=RCOL_OK) die("open house collator failed");
	cfg.options=RCOL_CODE_POINT; if (open_coll(&cfg,&raw)!=RCOL_OK) die("open raw collator failed");
	uint8_t space[32],digit[32],letter[32],prior[32]; size_t ns=0,nd=0,nl=0,np=0;
	if (key(house,(const uint8_t *)"a ",2,space,sizeof space,&ns)!=RCOL_OK ||
	    key(house,(const uint8_t *)"a0",2,digit,sizeof digit,&nd)!=RCOL_OK ||
	    key(house,(const uint8_t *)"aa",2,letter,sizeof letter,&nl)!=RCOL_OK) die("reference key failed");
	unsigned spaces=0,punctuation=0,scalars=0;
	for (unsigned cp=0;cp<0x110000;cp++) {
		if (cp>=0xd800 && cp<=0xdfff) continue;
		uint8_t input[8]={'a'},actual[128],codepoint[16]; size_t n=utf8(cp,input+1)+1,need=0,nraw=0;
		if (key(house,input,n,actual,sizeof actual,&need)!=RCOL_OK) die("house key failed");
		int same_space=!compare(actual,need,space,ns);
		if (same_space != !!(properties[cp]&SPACE)) { fprintf(stderr,"White_Space mismatch U+%04X\n",cp); return 1; }
		if (properties[cp]&SPACE) spaces++;
		if (properties[cp]&PUNCT) {
			if (compare(actual,need,space,ns)<=0 || compare(actual,need,digit,nd)>=0 || compare(actual,need,letter,nl)>=0 ||
			    (np && compare(prior,np,actual,need)>=0)) { fprintf(stderr,"punctuation order mismatch U+%04X\n",cp); return 1; }
			if (need>sizeof prior) die("punctuation key unexpectedly large");
			memcpy(prior,actual,need);np=need;punctuation++;
		}
		if (key(raw,input,n,codepoint,sizeof codepoint,&nraw)!=RCOL_OK || nraw!=n+1 ||
		    memcmp(input,codepoint,n) || codepoint[n]!=0) die("code-point mode changed");
		scalars++;
	}
	if (spaces!=25 || punctuation<800 || scalars!=1112064) die("incomplete source/domain sweep");
	close_coll(house);close_coll(raw);dlclose(module);
	printf("structural_unicode: %u scalars, %u punctuation, %u spaces; 3 passed, 0 failed\n",scalars,punctuation,spaces);
	return 0;
}
