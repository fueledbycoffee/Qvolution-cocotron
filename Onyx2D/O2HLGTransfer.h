#ifndef O2_HLG_TRANSFER_H
#define O2_HLG_TRANSFER_H

#include <stdbool.h>

/* BT.2100-3 Table 5 normalized scene values, independent of CG/display policy.
 * Domain violations return false and leave output unchanged. */
bool O2HLGOETF(double scene, double *encoded);
bool O2HLGInverseOETF(double encoded, double *scene);
/* Reference zero-black system only. Explicit peak 400..2000 cd/m2 selects
 * the standard's system gamma; no SDR/reference-white default is supplied. */
bool O2HLGReferenceOOTF(const double scene[3], double peakLuminance,
                         double display[3]);
bool O2HLGReferenceEOTF(const double encoded[3], double peakLuminance,
                         double display[3]);

#endif
