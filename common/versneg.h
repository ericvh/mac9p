#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Build a small ordered list of 9P version strings to try during negotiation.
 *
 * - If requested != NULL, it is tried first.
 * - Otherwise, the default preference is: 9P2000.L, 9P2000.u, 9P2000.
 * - Duplicates are removed.
 *
 * Returns the number of entries written to out[] (<= outmax).
 */
int mac9p_build_version_candidates(const char *requested,
                                  int prefer_dotl,
                                  int prefer_dotu,
                                  const char **out,
                                  int outmax);

#ifdef __cplusplus
}
#endif

