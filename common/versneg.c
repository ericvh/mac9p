#include "versneg.h"

#include <string.h>

static int
append_unique(const char *v, const char **out, int *n, int outmax)
{
	if (v == NULL || out == NULL || n == NULL || outmax <= 0)
		return 0;
	for (int i = 0; i < *n; i++) {
		if (out[i] && strcmp(out[i], v) == 0)
			return 0;
	}
	if (*n >= outmax)
		return 0;
	out[(*n)++] = v;
	return 1;
}

int
mac9p_build_version_candidates(const char *requested,
                              int prefer_dotl,
                              int prefer_dotu,
                              const char **out,
                              int outmax)
{
	int n = 0;

	/* caller may pass a pre-sized array; we only fill up to outmax */
	if (out == NULL || outmax <= 0)
		return 0;

	/*
	 * The canonical strings. Keep these in sync with the rest of the codebase:
	 * - 9P2000
	 * - 9P2000.u
	 * - 9P2000.L
	 */
	const char *v2000 = "9P2000";
	const char *v2000u = "9P2000.u";
	const char *v2000L = "9P2000.L";

	if (requested && *requested)
		append_unique(requested, out, &n, outmax);

	/*
	 * If no explicit request, allow preference hints from mount flags.
	 * (If requested is present, these are just fallbacks.)
	 */
	if (prefer_dotl)
		append_unique(v2000L, out, &n, outmax);
	if (prefer_dotu)
		append_unique(v2000u, out, &n, outmax);

	/* Always include remaining defaults as fallbacks */
	append_unique(v2000L, out, &n, outmax);
	append_unique(v2000u, out, &n, outmax);
	append_unique(v2000, out, &n, outmax);

	return n;
}

