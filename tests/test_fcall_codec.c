#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../kext/plan9.h"
#include "../kext/fcall.h"

static void
roundtrip_fcall(Fcall *in, int dotu)
{
	uchar buf[8192];
	Fcall out;
	uint n, m;

	memset(&out, 0, sizeof(out));

	n = sizeS2M(in, dotu);
	assert(n > 0);
	assert(n < sizeof(buf));

	m = convS2M(in, buf, sizeof(buf), dotu);
	assert(m == n);

	/*
	 * convM2S sets pointers into the message buffer (strings/data), so keep
	 * buf alive for the duration of checks on `out`.
	 */
	m = convM2S(buf, n, &out, dotu);
	assert(m == n);

	/* Always check tag/type for all messages */
	assert(out.type == in->type);
	assert(out.tag == in->tag);

	switch (in->type) {
	case Tversion:
		assert(out.msize == in->msize);
		assert(strcmp(out.version, in->version) == 0);
		break;
	case Tattach:
		assert(out.fid == in->fid);
		assert(out.afid == in->afid);
		assert(strcmp(out.uname, in->uname) == 0);
		assert(strcmp(out.aname, in->aname) == 0);
		if (dotu)
			assert(out.unamenum == in->unamenum);
		break;
	case Twalk:
		assert(out.fid == in->fid);
		assert(out.newfid == in->newfid);
		assert(out.nwname == in->nwname);
		for (int i = 0; i < out.nwname; i++)
			assert(strcmp(out.wname[i], in->wname[i]) == 0);
		break;
	case Tread:
		assert(out.fid == in->fid);
		assert(out.offset == in->offset);
		assert(out.count == in->count);
		break;
	case Twrite:
		assert(out.fid == in->fid);
		assert(out.offset == in->offset);
		assert(out.count == in->count);
		assert(out.data != NULL);
		assert(memcmp(out.data, in->data, in->count) == 0);
		break;
	case Rread:
		assert(out.count == in->count);
		assert(out.data != NULL);
		assert(memcmp(out.data, in->data, in->count) == 0);
		break;
	case Rerror:
		assert(out.ename != NULL);
		assert(strcmp(out.ename, in->ename) == 0);
		if (dotu)
			assert(out.errnum == in->errnum);
		break;
	default:
		/* Add more message types as coverage expands */
		break;
	}
}

static void
test_version(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Tversion;
	f.tag = (ushort)NOTAG;
	f.msize = 8192;
	f.version = "9P2000.L";
	roundtrip_fcall(&f, 0);
}

static void
test_attach_dotu(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Tattach;
	f.tag = 7;
	f.fid = 123;
	f.afid = NOFID;
	f.uname = "user";
	f.aname = "";
	f.unamenum = 501;
	roundtrip_fcall(&f, 1);
}

static void
test_walk_one(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Twalk;
	f.tag = 42;
	f.fid = 1;
	f.newfid = 2;
	f.nwname = 1;
	f.wname[0] = "etc";
	roundtrip_fcall(&f, 0);
}

static void
test_read(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Tread;
	f.tag = 9;
	f.fid = 55;
	f.offset = 4096;
	f.count = 1024;
	roundtrip_fcall(&f, 0);
}

static void
test_write(void)
{
	static char payload[] = "hello-9p";
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Twrite;
	f.tag = 10;
	f.fid = 55;
	f.offset = 0;
	f.count = (u32int)strlen(payload);
	f.data = payload;
	roundtrip_fcall(&f, 0);
}

static void
test_rread(void)
{
	static char payload[] = "abcdef";
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Rread;
	f.tag = 99;
	f.count = (u32int)strlen(payload);
	f.data = payload;
	roundtrip_fcall(&f, 0);
}

static void
test_rerror_dotu(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Rerror;
	f.tag = 3;
	f.ename = "permission denied";
	f.errnum = 13;
	roundtrip_fcall(&f, 1);
}

static void
test_dir_stat_dotu(void)
{
	Dir d1, d2;
	uchar buf[4096];
	char strs[1024];
	uint n;
	int dotu = 1;

	memset(&d1, 0, sizeof(d1));
	memset(&d2, 0, sizeof(d2));
	memset(buf, 0, sizeof(buf));
	memset(strs, 0, sizeof(strs));

	d1.type = 0;
	d1.dev = 0;
	d1.qid.type = 0;
	d1.qid.vers = 1;
	d1.qid.path = 2;
	d1.mode = 0644;
	d1.atime = 100;
	d1.mtime = 200;
	d1.length = 1234;
	d1.name = "file.txt";
	d1.uid = "u";
	d1.gid = "g";
	d1.muid = "m";
	d1.ext = "";
	d1.uidnum = 501;
	d1.gidnum = 20;
	d1.muidnum = 501;

	n = convD2M(&d1, buf, sizeof(buf), dotu);
	assert(n > 0);
	assert(statcheck(buf, n, dotu) == 0);
	assert(convM2D(buf, n, &d2, strs, dotu) == n);

	assert(strcmp(d2.name, d1.name) == 0);
	assert(strcmp(d2.uid, d1.uid) == 0);
	assert(strcmp(d2.gid, d1.gid) == 0);
	assert(strcmp(d2.muid, d1.muid) == 0);
	assert(d2.mode == d1.mode);
	assert(d2.length == d1.length);
	assert(d2.qid.path == d1.qid.path);
	assert(d2.qid.vers == d1.qid.vers);
	assert(d2.uidnum == d1.uidnum);
	assert(d2.gidnum == d1.gidnum);
	assert(d2.muidnum == d1.muidnum);
}

int
main(void)
{
	test_version();
	test_attach_dotu();
	test_walk_one();
	test_read();
	test_write();
	test_rread();
	test_rerror_dotu();
	test_dir_stat_dotu();
	return 0;
}

