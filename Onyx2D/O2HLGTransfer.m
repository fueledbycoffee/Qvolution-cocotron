#include "O2HLGTransfer.h"
#include <math.h>
#include <stddef.h>

static const double hlgA = 0.17883277;

bool O2HLGOETF(double scene, double *encoded) {
    if (encoded == NULL || !isfinite(scene) || scene < 0 || scene > 1)
        return false;
    double b = 1 - 4 * hlgA;
    double c = 0.5 - hlgA * log(4 * hlgA);
    *encoded = scene <= 1.0 / 12 ? sqrt(3 * scene) : hlgA * log(12 * scene - b) + c;
    return true;
}

bool O2HLGInverseOETF(double encoded, double *scene) {
    if (scene == NULL || !isfinite(encoded) || encoded < 0 || encoded > 1)
        return false;
    double b = 1 - 4 * hlgA;
    double c = 0.5 - hlgA * log(4 * hlgA);
    *scene = encoded <= 0.5 ? encoded * encoded / 3 : (exp((encoded - c) / hlgA) + b) / 12;
    return true;
}

/* The rounded normative a makes inverseOETF(1) slightly greater than 1. Keep
 * that value when composing the equations, without normalizing or clipping. */
static bool referenceOOTF(const double scene[3], double peak, double display[3], double maximum) {
    if (scene == NULL || display == NULL || !isfinite(peak) || peak < 400 || peak > 2000)
        return false;
    for (int i = 0; i < 3; i++)
        if (!isfinite(scene[i]) || scene[i] < 0 || scene[i] > maximum)
            return false;
    double luminance = 0.2627 * scene[0] + 0.6780 * scene[1] + 0.0593 * scene[2];
    double gamma = 1.2 + 0.42 * log10(peak / 1000);
    double scale = peak * pow(luminance, gamma - 1);
    double result[3];
    for (int i = 0; i < 3; i++)
        result[i] = scale * scene[i];
    for (int i = 0; i < 3; i++)
        display[i] = result[i];
    return true;
}

bool O2HLGReferenceOOTF(const double scene[3], double peak, double display[3]) {
    return referenceOOTF(scene, peak, display, 1);
}

bool O2HLGReferenceEOTF(const double encoded[3], double peak, double display[3]) {
    if (encoded == NULL || display == NULL)
        return false;
    double scene[3], maximum;
    for (int i = 0; i < 3; i++)
        if (!O2HLGInverseOETF(encoded[i], &scene[i]))
            return false;
    O2HLGInverseOETF(1, &maximum);
    return referenceOOTF(scene, peak, display, maximum);
}
