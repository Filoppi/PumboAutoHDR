#define K_BT709  float3(0.2126f, 0.7152f, 0.0722f)
#define K_BT2020 float3(0.2627f, 0.6780f, 0.0593f)

static const float BT709_max_nits = 80.f;
// SMPTE ST 2084 (Perceptual Quantization) is only defined until this amount of nits
static const float HDR10_max_nits = 10000.f;
// Linear BT.709 mid grey (it could also be ~0.215)
static const float mid_gray = 0.18f;

// sRGB gamma to linear (scRGB)
float sRGB_to_linear(float color, bool ignoreOutOfGamut /*= false*/)
{
    const float a = 0.055f;

    [flatten]
    if (ignoreOutOfGamut && (color >= 1.f || color <= 0.f))
    {
        // Nothing to do
    }
    else if (color <= 0.04045f)
        color = color / 12.92f;
    else
        color = pow((color + a) / (1.0f + a), 2.4f);

    return color;
}

float3 sRGB_to_linear(float3 colour, bool ignoreOutOfGamut /*= false*/)
{
    return float3(
		sRGB_to_linear(colour.r, ignoreOutOfGamut),
		sRGB_to_linear(colour.g, ignoreOutOfGamut),
		sRGB_to_linear(colour.b, ignoreOutOfGamut));
}

float3 gamma_to_linear_mirrored(float3 Color, float Gamma /*= 2.2f*/)
{
    return pow(abs(Color), Gamma) * sign(Color);
}

float3 linear_to_gamma_mirrored(float3 Color, float Gamma /*= 2.2f*/)
{
	return pow(abs(Color), 1.f / Gamma) * sign(Color);
}

static const float PQ_constant_N = (2610.0 / 4096.0 / 4.0);
static const float PQ_constant_M = (2523.0 / 4096.0 * 128.0);
static const float PQ_constant_C1 = (3424.0 / 4096.0);
static const float PQ_constant_C2 = (2413.0 / 4096.0 * 32.0);
static const float PQ_constant_C3 = (2392.0 / 4096.0 * 32.0);
static const float PQMaxWhitePoint = HDR10_max_nits / BT709_max_nits;

// PQ (Perceptual Quantizer - ST.2084) encode/decode used for HDR10 BT.2100
float3 linear_to_PQ(float3 linearCol)
{
    linearCol /= PQMaxWhitePoint;
	
    float3 colToPow = pow(linearCol, PQ_constant_N);
    float3 numerator = PQ_constant_C1 + PQ_constant_C2 * colToPow;
    float3 denominator = 1.f + PQ_constant_C3 * colToPow;
    float3 pq = pow(numerator / denominator, PQ_constant_M);

    return pq;
}

float3 PQ_to_linear(float3 ST2084)
{
    float3 colToPow = pow(ST2084, 1.0f / PQ_constant_M);
    float3 numerator = max(colToPow - PQ_constant_C1, 0.f);
    float3 denominator = PQ_constant_C2 - (PQ_constant_C3 * colToPow);
    float3 linearColor = pow(numerator / denominator, 1.f / PQ_constant_N);

    linearColor *= PQMaxWhitePoint;

    return linearColor;
}

static const float3x3 BT709_2_BT2020 = float3x3(
	0.627401924722236, 0.329291971755002, 0.0433061035227622,
	0.0690954897392608, 0.919544281267395, 0.0113602289933443,
	0.0163937090881632, 0.0880281623979006, 0.895578128513936);
static const float3x3 BT2020_2_BT709 = float3x3(
	1.66049621914783, -0.587656444131135, -0.0728397750166941,
	-0.124547095586012, 1.13289510924730, -0.00834801366128445,
	-0.0181536813870718, -0.100597371685743, 1.11875105307281);

float3 BT709_to_BT2020(float3 color)
{
    return mul(BT709_2_BT2020, color);
}

float3 BT2020_to_BT709(float3 color)
{
    return mul(BT2020_2_BT709, color);
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

float3 inv_ACES_Filmic(float3 color)
{
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;
    
    // Avoid out of gamut colors from breaking the formula
    color = saturate(color);
    
    // OG formula:
    // return (color * ((a * color) + b)) / (color * ((c * color) + d) + e);
    
    float3 fixed_numerator = (-d * color) + b;
    float3 variable_numerator_part1 = (d * color) - b;
    float3 variable_numerator = sqrt((variable_numerator_part1 * variable_numerator_part1) - (4.f * e * color * ((c * color) - a)));
    float3 denominator = 2.f * ((c * color) - a);
    float3 result1 = (fixed_numerator + variable_numerator) / denominator;
    float3 result2 = (fixed_numerator - variable_numerator) / denominator;
    color = max(result1, result2);
    return color;
}

// Fully scales any color <= than "fInValue" by "fScaleValue",
// and it scales increasingly less any other color in between "fInValue" and "fMaxValue".
// This is not color preserving nor brightness preserving, as it's done per channel.
float3 remapFromZero(float3 vHDRColor, float fInValue, float fScaleValue, float fMaxValue)
{
    float3 vAlpha = 1.0f - saturate((vHDRColor - fInValue) / (fMaxValue - fInValue));
    vHDRColor *= lerp(1.0f, fScaleValue, vAlpha);
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
    if (LumaAP1 <= 0.f)
    {
        return vHDRColor;
    }
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

// (in) sRGB/BT.709
// (out) OKLab:
// L - perceived lightness
// a - how green/red the color is
// b - how blue/yellow the color is
float3 linear_srgb_to_oklab(float3 rgb) {
	float l = (0.4122214708f * rgb.r) + (0.5363325363f * rgb.g) + (0.0514459929f * rgb.b);
	float m = (0.2119034982f * rgb.r) + (0.6806995451f * rgb.g) + (0.1073969566f * rgb.b);
	float s = (0.0883024619f * rgb.r) + (0.2817188376f * rgb.g) + (0.6299787005f * rgb.b);
    
	// Not sure whether the pow(abs())*sign() is technically correct, but if we pass in scRGB negative colors, this breaks,
	// and we think this might work fine (we could convert to BT.2020 first otherwise)
	// L'M'S'
	float l_ = pow(abs(l), 1.f / 3.f) * sign(l);
	float m_ = pow(abs(m), 1.f / 3.f) * sign(m);
	float s_ = pow(abs(s), 1.f / 3.f) * sign(s);

	return float3(
		(0.2104542553f * l_) + (0.7936177850f * m_) - (0.0040720468f * s_),
		(1.9779984951f * l_) - (2.4285922050f * m_) + (0.4505937099f * s_),
		(0.0259040371f * l_) + (0.7827717662f * m_) - (0.8086757660f * s_)
	);
}

// sRGB/Rec.709
float3 oklab_to_linear_srgb(float3 lab) {
	float L = lab[0];
	float a = lab[1];
	float b = lab[2];
	float l_ = L + (0.3963377774f * a) + (0.2158037573f * b);
	float m_ = L - (0.1055613458f * a) - (0.0638541728f * b);
	float s_ = L - (0.0894841775f * a) - (1.2914855480f * b);

	float l = l_ * l_ * l_;
	float m = m_ * m_ * m_;
	float s = s_ * s_ * s_;

	return float3(
		(+4.0767416621f * l) - (3.3077115913f * m) + (0.2309699292f * s),
		(-1.2684380046f * l) + (2.6097574011f * m) - (0.3413193965f * s),
		(-0.0041960863f * l) - (0.7034186147f * m) + (1.7076147010f * s)
	);
}

float3 oklab_to_oklch(float3 lab) {
	float L = lab[0];
	float a = lab[1];
	float b = lab[2];
	return float3(
		L,
		sqrt((a*a) + (b*b)),
		atan2(b, a)
	);
}

float3 oklch_to_oklab(float3 lch) {
	float L = lch[0];
	float C = lch[1];
	float h = lch[2];
	return float3(
		L,
		C * cos(h),
		C * sin(h)
	);
}

float3 oklch_to_linear_srgb(float3 lch) {
	return oklab_to_linear_srgb(
			oklch_to_oklab(lch)
	);
}

float3 linear_srgb_to_oklch(float3 rgb) {
	return oklab_to_oklch(
		linear_srgb_to_oklab(rgb)
	);
}