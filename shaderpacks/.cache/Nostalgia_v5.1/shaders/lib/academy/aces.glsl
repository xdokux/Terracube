/*
====================================================================================================

    Copyright (C) 2023 RRe36

    All Rights Reserved unless otherwise explicitly stated.


    By downloading this you have agreed to the license and terms of use.
    These can be found inside the included license-file
    or here: https://rre36.com/copyright-license

    Violating these terms may be penalized with actions according to the Digital Millennium
    Copyright Act (DMCA), the Information Society Directive and/or similar laws
    depending on your country.

====================================================================================================
*/

/*
====================================================================================================

        License Terms for Academy Color Encoding System Components

        Academy Color Encoding System (ACES) software and tools are provided by the
        Academy under the following terms and conditions: A worldwide, royalty-free,
        non-exclusive right to copy, modify, create derivatives, and use, in source and
        binary forms, is hereby granted, subject to acceptance of this license.

        Copyright © 2015 Academy of Motion Picture Arts and Sciences (A.M.P.A.S.).
        Portions contributed by others as indicated. All rights reserved.

        Performance of any of the aforementioned acts indicates acceptance to be bound
        by the following terms and conditions:

        * Copies of source code, in whole or in part, must retain the above copyright
        notice, this list of conditions and the Disclaimer of Warranty.

        * Use in binary form must retain the above copyright notice, this list of
        conditions and the Disclaimer of Warranty in the documentation and/or other
        materials provided with the distribution.

        * Nothing in this license shall be deemed to grant any rights to trademarks,
        copyrights, patents, trade secrets or any other intellectual property of
        A.M.P.A.S. or any contributors, except as expressly stated herein.

        * Neither the name "A.M.P.A.S." nor the name of any other contributors to this
        software may be used to endorse or promote products derivative of or based on
        this software without express prior written permission of A.M.P.A.S. or the
        contributors, as appropriate.

        This license shall be construed pursuant to the laws of the State of
        California, and any disputes related thereto shall be subject to the
        jurisdiction of the courts therein.

        Disclaimer of Warranty: THIS SOFTWARE IS PROVIDED BY A.M.P.A.S. AND CONTRIBUTORS
        "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
        THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND
        NON-INFRINGEMENT ARE DISCLAIMED. IN NO EVENT SHALL A.M.P.A.S., OR ANY
        CONTRIBUTORS OR DISTRIBUTORS, BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
        SPECIAL, EXEMPLARY, RESITUTIONARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
        LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
        PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
        LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
        OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
        ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

        WITHOUT LIMITING THE GENERALITY OF THE FOREGOING, THE ACADEMY SPECIFICALLY
        DISCLAIMS ANY REPRESENTATIONS OR WARRANTIES WHATSOEVER RELATED TO PATENT OR
        OTHER INTELLECTUAL PROPERTY RIGHTS IN THE ACADEMY COLOR ENCODING SYSTEM, OR
        APPLICATIONS THEREOF, HELD BY PARTIES OTHER THAN A.M.P.A.S.,WHETHER DISCLOSED OR
        UNDISCLOSED.

====================================================================================================
*/

#define ACES_RRTODT_APPROX 0

#ifndef incACESMT
    #include "transforms.glsl"
#endif

#include "functions.glsl"
#include "spline.glsl"


/*
    This is directly based off the reference implementation of the
    Reference Rendering Transform given by the academy on https://github.com/ampas/aces-dev
    Equivalent Reference Revision: 1.2
*/

#define acesRRTExposureBias 1.00    //[0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50]
#define acesRRTGammaLift 1.00       //[0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50]
#define acesRRTGlowGainOffset 0.0   //[-0.20 -0.18 -0.16 -0.14 -0.12 -0.10 -0.08 -0.06 -0.04 -0.02 0.0 0.02 0.04 0.06 0.08 0.10 0.12 0.14 0.16 0.18 0.20]
#define acesRRTSatOffset 0.0    //[-0.20 -0.18 -0.16 -0.14 -0.12 -0.10 -0.08 -0.06 -0.04 -0.02 0.0 0.02 0.04 0.06 0.08 0.10 0.12 0.14 0.16 0.18 0.20]
#define acesODTSatOffset 0.0    //[-0.20 -0.18 -0.16 -0.14 -0.12 -0.10 -0.08 -0.06 -0.04 -0.02 0.0 0.02 0.04 0.06 0.08 0.10 0.12 0.14 0.16 0.18 0.20]

const float dimSurroundGamma = 0.9311; //default 0.9811

const float rrtGlowGain     = 0.25 + acesRRTGlowGainOffset;     //default 0.05
const float rrtGlowMid      = 0.08;     //default 0.08

const float rrtRedScale     = 1.0;     //default 0.82
const float rrtRedPrivot    = 0.03;     //default 0.03
const float rrtRedHue       = 0.0;      //default 0.0
const float rrtRedWidth     = 135.0;    //default 135.0

#ifndef DIM
const float rrtSatFactor    = 0.97 + acesRRTSatOffset;     //default 0.96
const float odtSatFactor    = 0.93 + acesODTSatOffset;      //default 0.93
#else
const float rrtSatFactor    = 0.95 + acesRRTSatOffset;     //default 0.96
const float odtSatFactor    = 0.93 + acesODTSatOffset;      //default 0.93
#endif

const float rrtGammaLift    = 0.96 / acesRRTGammaLift;      //Default 1.00

vec3 darkToDimSurround(vec3 linearCV) {
    vec3 XYZ    = linearCV * AP1_XYZ;
    vec3 xyY    = XYZ_xyY(XYZ);
        xyY.z   = clamp(xyY.z, 0.0, 65535.0);
        xyY.z   = pow(xyY.z, dimSurroundGamma);
        XYZ     = xyY_XYZ(xyY);

    return XYZ * XYZ_AP1;
}

mat3x3 calcSaturationMatrix(const float sat, const vec3 rgb_y) {
    mat3x3 M;
        M[0].r = (1.0 - sat) * rgb_y.r + sat;
        M[1].r = (1.0 - sat) * rgb_y.r;
        M[2].r = (1.0 - sat) * rgb_y.r;

        M[0].g = (1.0 - sat) * rgb_y.g;
        M[1].g = (1.0 - sat) * rgb_y.g + sat;
        M[2].g = (1.0 - sat) * rgb_y.g;

        M[0].b = (1.0 - sat) * rgb_y.b;
        M[1].b = (1.0 - sat) * rgb_y.b;
        M[2].b = (1.0 - sat) * rgb_y.b + sat;

    return M;
}

vec3 rrtSweeteners(vec3 ACES2065) {
    /* Glow module */
    float saturation    = rgbSaturation(ACES2065);
    float ycIn          = rgbYC(ACES2065);
    float s             = sigmoidShaper((saturation - 0.4) * rcp(0.2));
    float addedGlow     = 1.0 + glowFwd(ycIn, rrtGlowGain * s, rrtGlowMid);
    
        ACES2065       *= addedGlow;

    /* Red Modifier module */
    float hue           = rgbHue(ACES2065);
    float centeredHue   = centerHue(hue, rrtRedHue);
    float hueWeight     = cubicBasisShaper(centeredHue, rrtRedWidth);

        ACES2065.r     += hueWeight * saturation * (rrtRedPrivot - ACES2065.r) * (1.0 - rrtRedScale);

    /* Transform AP0 ACES2065-1 to AP1 ACEScg */
        ACES2065        = clamp(ACES2065, 0.0, 65535.0);

    vec3 ACEScg         = ACES2065 * AP0_AP1;
        ACEScg          = clamp(ACEScg, 0.0, 65535.0);

    /* Global Desaturation */
        ACEScg          = mix(vec3(dot(ACEScg, AP1_RGB_Y)), ACEScg, rrtSatFactor);

    /* Added Gamma Correction to allow for color response tuning before mapping to LDR */
        ACEScg          = pow(ACEScg, vec3(rrtGammaLift));
    
    return ACEScg;
}

/*
    ACES Spline fit by Stephen Hill
    Deviations from the RRT are about as much as the Unreal-fit, but without random NaNs on the toe segment
*/

struct splineParam {
    float a;
    float b;
    float c;
    float d;
    float e;
};

vec4 splineOperator(vec4 aces, const splineParam param) {     //white scale in alpha
    aces   *= 1.413;

    vec4 a  = aces * (aces + param.a) - param.b;
    vec4 b  = aces * (param.c * aces + param.d) + param.e;

    return clamp(a / b, 0.0, 65535.0);
}

vec3 academyApproxCustom(vec3 aces) {
    vec3 rgbPre         = rrtSweeteners(aces);

    const float white = pi4;
    const splineParam curve = splineParam(0.0245786, 0.000090537, 0.983729, 0.5129510, 0.168081);

    vec4 mapped         = splineOperator(vec4(rgbPre, white), curve);

    vec3 mappedColor    = mapped.rgb / mapped.a;

    /* global desaturation */
        mappedColor     = mix(vec3(dot(mappedColor, AP1_RGB_Y)), mappedColor, odtSatFactor);
        mappedColor     = clamp16F(mappedColor);

    return mappedColor * AP1_AP0;
}


/*
"Packed" ACES transforms
*/

#if (defined COLOR_SPACE_SRGB || defined COLOR_SPACE_DCI_P3 || defined COLOR_SPACE_DISPLAY_P3 || defined COLOR_SPACE_REC2020 || defined COLOR_SPACE_ADOBE_RGB)

uniform int currentColorSpace;

// https://en.wikipedia.org/wiki/Rec._709#Transfer_characteristics
vec3 EOTF_Curve(vec3 LinearCV, const float LinearFactor, const float Exponent, const float Alpha, const float Beta) {
    return mix(LinearCV * LinearFactor, clamp(Alpha * pow(LinearCV, vec3(Exponent)) - (Alpha - 1.0), 0.0, 1.0), step(Beta, LinearCV));
}

// https://en.wikipedia.org/wiki/SRGB#Transfer_function_(%22gamma%22)
vec3 EOTF_IEC61966(vec3 LinearCV) {
    return EOTF_Curve(LinearCV, 12.92, 1.0 / 2.4, 1.055, 0.0031308);;
    //return mix(LinearCV * 12.92, clamp(pow(LinearCV, vec3(1.0/2.4)) * 1.055 - 0.055, 0.0, 1.0), step(0.0031308, LinearCV));
}

// https://en.wikipedia.org/wiki/Rec._709#Transfer_characteristics
vec3 EOTF_BT709(vec3 LinearCV) {
    return EOTF_Curve(LinearCV, 4.5, 0.45, 1.099, 0.018);
    //return mix(LinearCV * 4.5, clamp(pow(LinearCV, vec3(0.45)) * 1.099 - 0.099, 0.0, 1.0), step(0.018, LinearCV));
}

// https://en.wikipedia.org/wiki/Rec._2020#Transfer_characteristics
vec3 EOTF_BT2020_12Bit(vec3 LinearCV) {
    return EOTF_Curve(LinearCV, 4.5, 0.45, 1.0993, 0.0181);
}

// https://en.wikipedia.org/wiki/DCI-P3
vec3 EOTF_P3DCI(vec3 LinearCV) {
    return pow(LinearCV, vec3(1.0 / 2.6));
}
// https://en.wikipedia.org/wiki/Adobe_RGB_color_space
vec3 EOTF_Adobe(vec3 LinearCV) {
    return pow(LinearCV, vec3(1.0 / 2.2));
}

vec3 OutputGamutTransform(vec3 ACES) {
    switch(currentColorSpace) {
        case COLOR_SPACE_SRGB:
            ACES = ACES * AP0_sRGB;
            return EOTF_IEC61966(ACES);

        case COLOR_SPACE_DCI_P3:
            ACES = ACES * AP0_P3DCI;
            return EOTF_P3DCI(ACES);

        case COLOR_SPACE_DISPLAY_P3:
            ACES = ACES * AP0_P3D65;
            return EOTF_IEC61966(ACES);

        case COLOR_SPACE_REC2020:
            ACES = ACES * AP0_REC2020;
            return EOTF_BT709(ACES);

        case COLOR_SPACE_ADOBE_RGB:
            ACES = ACES * AP0_REC2020;
            return EOTF_Adobe(ACES);
    }
    // Fall back to sRGB if unknown
    ACES = ACES * AP0_sRGB;
    return EOTF_IEC61966(ACES);
}

#else

#define VIEWPORT_GAMUT 0    //[0 1 2] 0: sRGB, 1: P3D65, 2: Display P3

vec3 OutputGamutTransform(vec3 ACES) {
#if VIEWPORT_GAMUT == 1
    vec3 P3 = ACES * AP0_P3D65;
    //return LinearToSRGB(P3);
    return pow(P3, vec3(1.0 / 2.6));
#elif VIEWPORT_GAMUT == 2
    vec3 P3 = ACES * AP0_P3D65;
    return LinearToSRGB(P3);
#else
    return LinearToSRGB(ACES * AP0_sRGB);
#endif
}

#endif



//
// Compression LMT to fix bright colour clipping/burning based on ACES v1.3
//

float CompressLMT(float DistToAch, const float lim, const float thr, const float pwr)
{
	if (DistToAch >= thr)
	{
        // Calculate scale factor for y = 1 intersect
		float scl = (lim - thr) / pow(pow((1.0 - thr) / (lim - thr), -pwr) - 1.0, 1.0 / pwr);

        // Normalize distance outside threshold by scale factor
		float nd = (DistToAch - thr) / scl;
		float p = pow(nd, pwr);

		return thr + scl * nd / (pow(1.0 + p, 1.0 / pwr)); // Compress
	}
	
	return DistToAch;
}

vec3 ACES_CompressionLMT(vec3 AP1_CV)
{
	float Achromatic = max(AP1_CV.r, max(AP1_CV.g, AP1_CV.b));
	
	vec3 DistToAch = Achromatic == 0.0 ? vec3(0.0f, 0.0f, 0.0f) : (Achromatic - AP1_CV) / abs(Achromatic);
	
	const float LIM_CYAN = 1.147f;
	const float LIM_MAGENTA = 1.264f;
	const float LIM_YELLOW = 1.312f;
	
	const float THR_CYAN = 0.815f;
	const float THR_MAGENTA = 0.803f;
	const float THR_YELLOW = 0.880f;
	
	const float PWR = 1.2f * pi;
	
	vec3 CompressionDist = vec3(
		CompressLMT(DistToAch.r, LIM_CYAN, THR_CYAN, PWR),
		CompressLMT(DistToAch.g, LIM_MAGENTA, THR_MAGENTA, PWR),
		CompressLMT(DistToAch.b, LIM_YELLOW, THR_YELLOW, PWR)
	);
	
	return vec3(
		Achromatic - CompressionDist.r * abs(Achromatic),
		Achromatic - CompressionDist.g * abs(Achromatic),
		Achromatic - CompressionDist.b * abs(Achromatic)
	);
}



vec3 ACES_AP1_SRGB(vec3 AP1) {
        AP1     = ACES_CompressionLMT(AP1);
    vec3 ACES   = AP1 * AP1_AP0;
        ACES    = academyApproxCustom(ACES);
        //ACES    = ACES * AP0_sRGB;

    return OutputGamutTransform(ACES);
}