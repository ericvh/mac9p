#include "../common/versneg.h"

#include <assert.h>
#include <string.h>

static void
expect_list(const char *requested, int dotl, int dotu, const char **exp, int expn)
{
	const char *out[8] = {0};
	int n = mac9p_build_version_candidates(requested, dotl, dotu, out, 8);
	assert(n == expn);
	for (int i = 0; i < n; i++) {
		assert(out[i] != NULL);
		assert(strcmp(out[i], exp[i]) == 0);
	}
}

int
main(void)
{
	/* No request: default preference */
	{
		const char *exp[] = {"9P2000.L", "9P2000.u", "9P2000"};
		expect_list(NULL, 0, 0, exp, 3);
	}

	/* Prefer dotu flag without explicit request */
	{
		const char *exp[] = {"9P2000.u", "9P2000.L", "9P2000"};
		expect_list(NULL, 0, 1, exp, 3);
	}

	/* Prefer dotl flag without explicit request */
	{
		const char *exp[] = {"9P2000.L", "9P2000.u", "9P2000"};
		expect_list(NULL, 1, 0, exp, 3);
	}

	/* Explicit request should be first, even if it is "older" */
	{
		const char *exp[] = {"9P2000", "9P2000.L", "9P2000.u"};
		expect_list("9P2000", 0, 0, exp, 3);
	}

	/* Explicit request with dotu preference should include dotu early, no dups */
	{
		const char *exp[] = {"9P2000", "9P2000.u", "9P2000.L"};
		expect_list("9P2000", 0, 1, exp, 3);
	}

	/* Explicit request already equals dotl: no duplicates */
	{
		const char *exp[] = {"9P2000.L", "9P2000.u", "9P2000"};
		expect_list("9P2000.L", 1, 1, exp, 3);
	}

	return 0;
}

