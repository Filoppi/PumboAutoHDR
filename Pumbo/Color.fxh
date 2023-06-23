#define K_BT709  float3(0.2126f, 0.7152f, 0.0722f)
#define K_BT2020 float3(0.2627f, 0.6780f, 0.0593f)

static const float BT709_max_nits = 80.f;
// Linear BT.709 mid grey (it could also be ~0.215)
static const float mid_gray = 0.18f;

// sRGB gamma to linear (scRGB)
float sRGB_to_linear(float v, bool ignoreAboveOne /*= false*/)
{
    float a = 0.055f;

    [flatten]
    if (ignoreAboveOne && v >= 1.f)
    {
        // Nothing to do
    }
    else if (v <= 0.04045f)
        v = v / 12.92f;
    else
        v = pow((v + a) / (1.0f + a), 2.4f);

    return v;
}

float3 sRGB_to_linear(float3 colour, bool ignoreAboveOne /*= false*/)
{
    return float3(
		sRGB_to_linear(colour.r, ignoreAboveOne),
		sRGB_to_linear(colour.g, ignoreAboveOne),
		sRGB_to_linear(colour.b, ignoreAboveOne));
}

// "L_white" of 2 matches simple Reinhard
float3 inv_tonemap_ReinhardPerComponent(float3 L, float L_white /*= 1.0f*/)
{
    const float3 L2 = L * L;
    const float LW2 = L_white * L_white;
    const float3 LP1 = (0.5f * ((L * LW2) - LW2));
	// It shouldn't be possible for this to be negative (but if it was, put a max() with 0)
    const float3 LP2P1 = LW2 * ((L2 * LW2) - (2.0f * L * LW2) + (4.0f * L) + LW2);
    const float3 LP2 = (0.5f * sqrt(LP2P1));

	// The results can both be negative for some reason (especially on pitch black pixels), so we max against 0.
    const float3 LA = LP1 + LP2;
    L = max(LA, 0.0f);

    return L;
}

// Linearly remaps colors from "0 to fInValue" onto "0 to fOutValue",
// and "fInValue to fMaxValue" onto "fOutValue to fMaxValue".
// This is not color preserving nor brightness preserving, as it's done per channel.
float3 remapFromZero(float3 vHDRColor, float fInValue, float fOutValue, float fMaxValue)
{
    float3 vAlpha = 1.0f - saturate((vHDRColor - fInValue) / (fMaxValue - fInValue));
    vHDRColor *= lerp(1.0f, fOutValue, vAlpha);
    return vHDRColor;
}

static const float3x3 XYZ_2_sRGB_MAT = float3x3(
	3.2409699419, -1.5373831776, -0.4986107603,
	-0.9692436363, 1.8759675015, 0.0415550574,
	0.0556300797, -0.2039769589, 1.0569715142);
static const float3x3 sRGB_2_XYZ_MAT = float3x3(
	0.4124564, 0.3575761, 0.1804375,
	0.2126729, 0.7151522, 0.0721750,
	0.0193339, 0.1191920, 0.9503041);
static const float3x3 XYZ_2_AP1_MAT = float3x3(
	1.6410233797, -0.3248032942, -0.2364246952,
	-0.6636628587, 1.6153315917, 0.0167563477,
	0.0117218943, -0.0082844420, 0.9883948585);
static const float3x3 D65_2_D60_CAT = float3x3(
	1.01303, 0.00610531, -0.014971,
	0.00769823, 0.998165, -0.00503203,
	-0.00284131, 0.00468516, 0.924507);
static const float3x3 D60_2_D65_CAT = float3x3(
	0.987224, -0.00611327, 0.0159533,
	-0.00759836, 1.00186, 0.00533002,
	0.00307257, -0.00509595, 1.08168);
static const float3x3 AP1_2_XYZ_MAT = float3x3(
	0.6624541811, 0.1340042065, 0.1561876870,
	0.2722287168, 0.6740817658, 0.0536895174,
	-0.0055746495, 0.0040607335, 1.0103391003);
static const float3 AP1_RGB2Y = float3(
	0.2722287168, //AP1_2_XYZ_MAT[0][1],
	0.6740817658, //AP1_2_XYZ_MAT[1][1],
	0.0536895174 //AP1_2_XYZ_MAT[2][1]
);
// Bizarre matrix but this expands sRGB to between P3 and AP1
// CIE 1931 chromaticities:	x		y
//				Red:		0.6965	0.3065
//				Green:		0.245	0.718
//				Blue:		0.1302	0.0456
//				White:		0.31271	0.32902
static const float3x3 Wide_2_XYZ_MAT = float3x3(
    0.5441691, 0.2395926, 0.1666943,
    0.2394656, 0.7021530, 0.0583814,
    -0.0023439, 0.0361834, 1.0552183);

// Expand bright saturated colors outside the sRGB (REC.709) gamut to fake wide gamut rendering (BT.2020).
// Inspired by Unreal Engine 4/5 (ACES).
// Input (and output) needs to be in sRGB linear space.
// Calling this with a value of 0 still results in changes (it's actually an edge case, don't call it, it produces invalid/imaginary colors).
// Calling this with values above 1 yields diminishing returns.
float3 expandGamut(float3 vHDRColor, float fExpandGamut /*= 1.0f*/)
{
    const float3x3 sRGB_2_AP1 = mul(XYZ_2_AP1_MAT, mul(D65_2_D60_CAT, sRGB_2_XYZ_MAT));
    const float3x3 AP1_2_sRGB = mul(XYZ_2_sRGB_MAT, mul(D60_2_D65_CAT, AP1_2_XYZ_MAT));
    const float3x3 Wide_2_AP1 = mul(XYZ_2_AP1_MAT, Wide_2_XYZ_MAT);
    const float3x3 ExpandMat = mul(Wide_2_AP1, AP1_2_sRGB);

    float3 ColorAP1 = mul(sRGB_2_AP1, vHDRColor);

    float LumaAP1 = dot(ColorAP1, AP1_RGB2Y);
    float3 ChromaAP1 = ColorAP1 / LumaAP1;

    float ChromaDistSqr = dot(ChromaAP1 - 1, ChromaAP1 - 1);
    float ExpandAmount = (1 - exp2(-4 * ChromaDistSqr)) * (1 - exp2(-4 * fExpandGamut * LumaAP1 * LumaAP1));

    float3 ColorExpand = mul(ExpandMat, ColorAP1);
    ColorAP1 = lerp(ColorAP1, ColorExpand, ExpandAmount);

    vHDRColor = mul(AP1_2_sRGB, ColorAP1);
    return vHDRColor;
}

bool IsNAN(const float input)
{
    if (isnan(input) || isinf(input))
        return true;
    else
        return false;
}

float fixNAN(const float input)
{
    if (IsNAN(input))
        return 0.f;
    else
        return input;
}

float3 fixNAN(float3 input)
{
    if (IsNAN(input.r))
        input.r = 0.f;
    else if (IsNAN(input.g))
        input.g = 0.f;
    else if (IsNAN(input.b))
        input.b = 0.f;
  
    return input;
}

float max3(float a, float b, float c)
{
    return max(a, max(b, c));
}

float luminance(float3 vColor)
{
    return dot(vColor, K_BT709);
}

float average(float3 vColor)
{
    return dot(vColor, float3(1.f / 3.f, 1.f / 3.f, 1.f / 3.f));
}

float rangeCompressPow(float x, float fPow /*= 1.0f*/)
{
    return 1.0 - pow(exp(-x), fPow);
}

float lumaCompress(float val, float fMaxValue, float fShoulderStart, float fPow /*= 1.0f*/)
{
    float v2 = fShoulderStart + (fMaxValue - fShoulderStart) * rangeCompressPow((val - fShoulderStart) / (fMaxValue - fShoulderStart), fPow);
    return val <= fShoulderStart ? val : v2;
}