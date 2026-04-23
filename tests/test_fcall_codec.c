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
	case Rversion:
		assert(out.msize == in->msize);
		assert(strcmp(out.version, in->version) == 0);
		break;
	case Tauth:
		assert(out.afid == in->afid);
		assert(strcmp(out.uname, in->uname) == 0);
		assert(strcmp(out.aname, in->aname) == 0);
		if (dotu)
			assert(out.unamenum == in->unamenum);
		break;
	case Rauth:
		assert(out.aqid.path == in->aqid.path);
		assert(out.aqid.vers == in->aqid.vers);
		assert(out.aqid.type == in->aqid.type);
		break;
	case Tattach:
		assert(out.fid == in->fid);
		assert(out.afid == in->afid);
		assert(strcmp(out.uname, in->uname) == 0);
		assert(strcmp(out.aname, in->aname) == 0);
		if (dotu)
			assert(out.unamenum == in->unamenum);
		break;
	case Rattach:
		assert(out.qid.path == in->qid.path);
		assert(out.qid.vers == in->qid.vers);
		assert(out.qid.type == in->qid.type);
		break;
	case Twalk:
		assert(out.fid == in->fid);
		assert(out.newfid == in->newfid);
		assert(out.nwname == in->nwname);
		for (int i = 0; i < out.nwname; i++)
			assert(strcmp(out.wname[i], in->wname[i]) == 0);
		break;
	case Rwalk:
		assert(out.nwqid == in->nwqid);
		for (int i = 0; i < out.nwqid; i++) {
			assert(out.wqid[i].path == in->wqid[i].path);
			assert(out.wqid[i].vers == in->wqid[i].vers);
			assert(out.wqid[i].type == in->wqid[i].type);
		}
		break;
	case Topen:
		assert(out.fid == in->fid);
		assert(out.mode == in->mode);
		break;
	case Ropen:
		assert(out.qid.path == in->qid.path);
		assert(out.qid.vers == in->qid.vers);
		assert(out.qid.type == in->qid.type);
		assert(out.iounit == in->iounit);
		break;
	case Tcreate:
		assert(out.fid == in->fid);
		assert(strcmp(out.name, in->name) == 0);
		assert(out.perm == in->perm);
		assert(out.mode == in->mode);
		if (dotu)
			assert(strcmp(out.ext, in->ext) == 0);
		break;
	case Rcreate:
		assert(out.qid.path == in->qid.path);
		assert(out.qid.vers == in->qid.vers);
		assert(out.qid.type == in->qid.type);
		assert(out.iounit == in->iounit);
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
	case Rwrite:
		assert(out.count == in->count);
		break;
	case Tclunk:
	case Tremove:
	case Tstat:
	case Twstat:
		assert(out.fid == in->fid);
		if (in->type == Twstat) {
			assert(out.nstat == in->nstat);
			assert(out.stat != NULL);
			assert(memcmp(out.stat, in->stat, in->nstat) == 0);
		}
		break;
	case Rclunk:
	case Rremove:
	case Rflush:
	case Rwstat:
		/* no additional fields */
		break;
	case Tflush:
		assert(out.oldtag == in->oldtag);
		break;
	case Rerror:
		assert(out.ename != NULL);
		assert(strcmp(out.ename, in->ename) == 0);
		if (dotu)
			assert(out.errnum == in->errnum);
		break;
	case Rstat:
		assert(out.nstat == in->nstat);
		assert(out.stat != NULL);
		assert(memcmp(out.stat, in->stat, in->nstat) == 0);
		break;
	default:
		/* Add more message types as coverage expands */
		break;
	}
}

static Qid
mkqid(uint8_t type, uint32_t vers, uint64_t path)
{
	Qid q;
	q.type = type;
	q.vers = vers;
	q.path = path;
	return q;
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
test_rversion(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Rversion;
	f.tag = (ushort)NOTAG;
	f.msize = 4096;
	f.version = "9P2000.u";
	roundtrip_fcall(&f, 0);
}

static void
test_auth_dotu(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Tauth;
	f.tag = 1;
	f.afid = 111;
	f.uname = "user";
	f.aname = "svc";
	f.unamenum = 501;
	roundtrip_fcall(&f, 1);
}

static void
test_rauth(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Rauth;
	f.tag = 1;
	f.aqid = mkqid(0x80, 7, 0x1234);
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
test_rattach(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Rattach;
	f.tag = 7;
	f.qid = mkqid(0x80, 1, 0x2);
	roundtrip_fcall(&f, 0);
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
test_rwalk_one(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Rwalk;
	f.tag = 42;
	f.nwqid = 1;
	f.wqid[0] = mkqid(0x00, 2, 0x99);
	roundtrip_fcall(&f, 0);
}

static void
test_open(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Topen;
	f.tag = 2;
	f.fid = 10;
	f.mode = 0; /* OREAD */
	roundtrip_fcall(&f, 0);
}

static void
test_ropen(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Ropen;
	f.tag = 2;
	f.qid = mkqid(0x00, 3, 0x100);
	f.iounit = 8192;
	roundtrip_fcall(&f, 0);
}

static void
test_create_dotu(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Tcreate;
	f.tag = 3;
	f.fid = 10;
	f.name = "newfile";
	f.perm = 0644;
	f.mode = 1; /* OWRITE */
	f.ext = "";
	roundtrip_fcall(&f, 1);
}

static void
test_rcreate(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Rcreate;
	f.tag = 3;
	f.qid = mkqid(0x00, 4, 0x101);
	f.iounit = 8192;
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
test_rwrite(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Rwrite;
	f.tag = 10;
	f.count = 7;
	roundtrip_fcall(&f, 0);
}

static void
test_clunk(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Tclunk;
	f.tag = 11;
	f.fid = 55;
	roundtrip_fcall(&f, 0);
}

static void
test_rclunk(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Rclunk;
	f.tag = 11;
	roundtrip_fcall(&f, 0);
}

static void
test_remove(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Tremove;
	f.tag = 12;
	f.fid = 56;
	roundtrip_fcall(&f, 0);
}

static void
test_rremove(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Rremove;
	f.tag = 12;
	roundtrip_fcall(&f, 0);
}

static void
test_flush(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Tflush;
	f.tag = 13;
	f.oldtag = 99;
	roundtrip_fcall(&f, 0);
}

static void
test_rflush(void)
{
	Fcall f;
	memset(&f, 0, sizeof(f));
	f.type = Rflush;
	f.tag = 13;
	roundtrip_fcall(&f, 0);
}

static void
mk_statbuf(uchar *buf, uint *n, int dotu)
{
	Dir d;
	memset(&d, 0, sizeof(d));
	d.type = 0;
	d.dev = 0;
	d.qid.type = 0;
	d.qid.vers = 1;
	d.qid.path = 2;
	d.mode = 0644;
	d.atime = 100;
	d.mtime = 200;
	d.length = 1234;
	d.name = "file.txt";
	d.uid = "u";
	d.gid = "g";
	d.muid = "m";
	d.ext = "";
	d.uidnum = 501;
	d.gidnum = 20;
	d.muidnum = 501;
	*n = convD2M(&d, buf, 4096, dotu);
	assert(*n > 0);
}

static void
test_stat_and_wstat(void)
{
	uchar sbuf[4096];
	uint sn;

	mk_statbuf(sbuf, &sn, 1);

	{
		Fcall f;
		memset(&f, 0, sizeof(f));
		f.type = Tstat;
		f.tag = 20;
		f.fid = 77;
		roundtrip_fcall(&f, 0);
	}
	{
		Fcall f;
		memset(&f, 0, sizeof(f));
		f.type = Rstat;
		f.tag = 20;
		f.nstat = (ushort)sn;
		f.stat = sbuf;
		roundtrip_fcall(&f, 0);
	}
	{
		Fcall f;
		memset(&f, 0, sizeof(f));
		f.type = Twstat;
		f.tag = 21;
		f.fid = 77;
		f.nstat = (ushort)sn;
		f.stat = sbuf;
		roundtrip_fcall(&f, 0);
	}
	{
		Fcall f;
		memset(&f, 0, sizeof(f));
		f.type = Rwstat;
		f.tag = 21;
		roundtrip_fcall(&f, 0);
	}
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
	test_rversion();
	test_auth_dotu();
	test_rauth();
	test_attach_dotu();
	test_rattach();
	test_walk_one();
	test_rwalk_one();
	test_open();
	test_ropen();
	test_create_dotu();
	test_rcreate();
	test_read();
	test_write();
	test_rread();
	test_rwrite();
	test_clunk();
	test_rclunk();
	test_remove();
	test_rremove();
	test_flush();
	test_rflush();
	test_stat_and_wstat();
	test_rerror_dotu();
	test_dir_stat_dotu();
	return 0;
}

