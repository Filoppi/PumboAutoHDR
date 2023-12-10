#include "ReShade.fxh"
#include "Color.fxh"

// These are from the "color_space" enum in ReShade
#define RESHADE_COLOR_SPACE_UNKNOWN     0
#define RESHADE_COLOR_SPACE_SRGB        1
#define RESHADE_COLOR_SPACE_SCRGB       2
#define RESHADE_COLOR_SPACE_BT2020_PQ   3

// "BUFFER_COLOR_SPACE" is defined by ReShade.
// "ACTUAL_COLOR_SPACE" uses the enum values defined in "IN_COLOR_SPACE".
#if BUFFER_COLOR_SPACE == RESHADE_COLOR_SPACE_SRGB
  #define ACTUAL_COLOR_SPACE 1
#elif BUFFER_COLOR_SPACE == RESHADE_COLOR_SPACE_SCRGB
  #define ACTUAL_COLOR_SPACE 4
#elif BUFFER_COLOR_SPACE == RESHADE_COLOR_SPACE_BT2020_PQ
  #define ACTUAL_COLOR_SPACE 5
#else
  #define ACTUAL_COLOR_SPACE 0
#endif

// This uses the enum values defined in "IN_COLOR_SPACE"
#define DEFAULT_COLOR_SPACE 1

// We don't default to "Auto" here as if we are upgrading the backbuffer, we'd detect the wrong value
uniform uint IN_COLOR_SPACE
<
  ui_label    = "Input Color Space";
  ui_type     = "combo";
  ui_items    = "Auto\0SDR sRGB\0SDR Rec.709 Gamma 2.2\0SDR Rec.709 Gamma 2.4\0HDR scRGB\0HDR10 BT.2020 PQ\0";
  ui_tooltip = "Specify the input color space (Auto doesn't always work right).\nSome SDR games use sRGB gamma and some other use 2.2 gamma, pick the one that looks more correct.\nFor HDR, either pick scRGB or HDR10";
  ui_category = "Calibration";
> = DEFAULT_COLOR_SPACE;

uniform uint OUT_OF_GAMUT_COLORS_BEHAVIOUR
<
  ui_label    = "Out of gamut colors behaviour";
  ui_type     = "combo";
  ui_items    = "Apply Gamma\0Ignore Gamma\0Clip\0";
  ui_tooltip = "When forcing HDR (float) buffers on SDR games, they can occasionally output rgb colors brighter than 1 or lower than 0.\nThis dictates how we should react to them. Pick what looks best";
  ui_category = "Calibration";
> = 0;

uniform uint OUT_COLOR_SPACE
<
  ui_label    = "Output Color Space";
  ui_type     = "combo";
  ui_items    = "Auto\0HDR scRGB\0HDR10 BT.2020 PQ\0";
  ui_tooltip = "Specify the output color space";
  ui_category = "Calibration";
> = 0;

uniform float SDR_WHITEPOINT_NITS
<
  ui_label = "SDR white point (paper white) nits";
  ui_type = "drag";
  ui_tooltip = "SDR is neutral at 80 nits, though for most viewing conditions 203 is a good starting value";
  ui_category = "Calibration";
  ui_min = 1.f;
  ui_max = 500.f;
  ui_step = 1.f;
> = sRGB_max_nits;

uniform float HDR_MAX_NITS
<
  ui_label = "HDR display max nits";
  ui_tooltip = "This is used by HDR tonemapping. Set it equal or higher the AutoHDR max nits to ignore it and avoid double tonemapping";
  ui_category = "Calibration";
  ui_type = "drag";
  ui_min = sRGB_max_nits;
  ui_max = 10000.f;
  ui_step = 1.f;
> = 750.f;

uniform float HIGHLIGHTS_SHOULDER_START_ALPHA
<
  ui_label = "Highlights shoulder start alpha";
  ui_tooltip = "When do we start compressing highlight within your monitor capabilities?";
  ui_category = "Calibration";
  ui_type = "drag";
  ui_min = 0.f;
  ui_max = 1.f;
  ui_step = 0.01f;
> = 0.5f;

uniform float HIGHLIGHTS_SHOULDER_POW
<
  ui_label = "Highlights shoulder pow";
  ui_tooltip = "Modulates the highlight compression curve";
  ui_category = "Calibration";
  ui_type = "drag";
  ui_min = 0.001f;
  ui_max = 10.f;
  ui_step = 0.05f;
> = 1.f;

uniform uint AUTO_HDR_METHOD
<
  ui_category = "Auto HDR";
  ui_label    = "Auto HDR method";
  ui_type     = "combo";
  ui_items    = "None\0By luminance (color conserving) - RECCOMENDED\0By channel average (color conserving)\0By channel (increases saturation)\0By max channel (color conserving)\0By Oklab lightness\0";
> = 0;

uniform float AUTO_HDR_SHOULDER_START_ALPHA
<
  ui_label = "Auto HDR shoulder start alpha";
  ui_tooltip = "Determines how bright the source SDR color needs to be before we start scaling its brightness to generate fake HDR highlights. Has no effect at 1";
  ui_category = "Auto HDR";
  ui_type = "drag";
  ui_min = 0.f;
  ui_max = 1.f;
  ui_step = 0.01f;
> = 0.f;

uniform float AUTO_HDR_MAX_NITS
<
  ui_label = "Auto HDR target/max brightness";
  ui_tooltip = "Depending on the other AutoHDR settings, going too bright (e.g. beyond the 600-1000 nits range), can lead to weird results, as we are still limited by an SDR source image";
  ui_category = "Auto HDR";
  ui_type = "drag";
  ui_min = sRGB_max_nits;
  ui_max = 2000.f;
  ui_step = 1.f;
> = 400.f;

uniform float AUTO_HDR_SHOULDER_POW
<
  ui_label = "Auto HDR shoulder pow";
  ui_tooltip = "Modulates the Auto HDR highlights curve";
  ui_category = "Auto HDR";
  ui_type = "drag";
  ui_min = 1.f;
  ui_max = 10.f;
  ui_step = 0.05f;
> = 2.5f;

uniform uint INVERSE_TONEMAP_METHOD
<
  ui_category = "Inverse tone mapping";
  ui_label    = "Inverse tonemap method";
  ui_tooltip  = "Do not use with Auto HDR; it's a more bare bones version of it.\nSome of these might clip all out of gamut colors from the source image";
  ui_type     = "combo";
  ui_items    = "None\0Advanced Reinhard by channel\0ACES Filmic\0";
> = 0;

uniform float TONEMAPPER_WHITE_POINT
<
  ui_label = "Tonemapper white point (in units)";
  ui_tooltip = "Used as parameter by some tonemappers. Increases saturation. Has no effect at 1";
  ui_category = "Inverse tone mapping";
  ui_type = "drag";
  ui_min = 1.f;
  ui_max = 100.f;
  ui_step = 0.01f;
> = 2.f;

uniform float BLACK_FLOOR_LUMINANCE
<
  ui_label = "Black floor luminance";
  ui_tooltip = "Fixes raised black floors by remapping colors (by luminance)";
  ui_category = "Fine tuning";
  ui_type = "drag";
  ui_min = 0.0f;
  ui_max = mid_gray;
  ui_step = 0.0000005f;
> = 0.f;

uniform float SHADOW_TUNING
<
  ui_label = "Shadow";
  ui_tooltip = "Rebalances shadows. Neutral at 1";
  ui_category = "Fine tuning";
  ui_type = "drag";
  ui_min = 0.01f;
  ui_max = 10.f;
  ui_step = 0.01f;
> = 1.f;

uniform float HIGHLIGHT_SATURATION
<
  ui_label = "Highlight saturation";
  ui_tooltip = "Allows tuning of highlights saturation. Neutral at 1";
  ui_category = "Fine tuning";
  ui_type = "drag";
  ui_min = 0.75f;
  ui_max = 1.5f;
  ui_step = 0.005f;
> = 1.f;

uniform float EXTRA_HDR_SATURATION
<
  ui_label = "Extra HDR saturation";
  ui_tooltip = "Generates HDR colors (BT.2020) from bright saturated SDR (BT.709) ones. Neutral at 0";
  ui_category = "Fine tuning";
  ui_type = "drag";
  ui_min = 0.f;
  ui_max = 1.f;
  ui_step = 0.01f;
> = 0.f;

void AdvancedAutoHDR(
      float4 vpos : SV_Position,
      float2 texcoord : TEXCOORD,
  out float4 output : SV_Target0)
{
    const float3 input = tex2D(ReShade::BackBuffer, texcoord).rgb;

    float3 fixedGammaColor = input;
    fixedGammaColor = clamp(fixedGammaColor, -FLT16_MAX, FLT16_MAX);
    
    uint inColorSpace = IN_COLOR_SPACE;
    if (inColorSpace == 0) // Auto selection
    {
        if (ACTUAL_COLOR_SPACE == 0) // Fall back on default if the actual color space is unknown
            inColorSpace = DEFAULT_COLOR_SPACE;
        else
            inColorSpace = ACTUAL_COLOR_SPACE;
    }
    
    const bool ignoreOutOfGamutColorsGamma = OUT_OF_GAMUT_COLORS_BEHAVIOUR == 1;
    const bool clipOutOfGamutColors = OUT_OF_GAMUT_COLORS_BEHAVIOUR == 2;

    if (inColorSpace == 0 || inColorSpace == 1) // sRGB (and Auto)
        fixedGammaColor = sRGB_to_linear(fixedGammaColor, ignoreOutOfGamutColorsGamma);
    else if (inColorSpace == 2 || inColorSpace == 3) // Rec.709 Gamma 2.2 | Rec.709 Gamma 2.4
    {
        const float gamma = (inColorSpace == 2) ? 2.2f : 2.4f;
        
        float3 extraColor = 0.f;
        if (ignoreOutOfGamutColorsGamma)
        {
            extraColor = fixedGammaColor - saturate(fixedGammaColor);
            fixedGammaColor = saturate(fixedGammaColor);
        }
        
        fixedGammaColor = gamma_to_linear_mirrored(fixedGammaColor, gamma);
        fixedGammaColor += extraColor;

    }
    else if (inColorSpace == 5) // HDR10 BT.2020 PQ
    {
        fixedGammaColor = PQ_to_linear(fixedGammaColor); // We use sRGB white point (80 nits, not 100)
        fixedGammaColor = BT2020_to_BT709(fixedGammaColor);
    }
    
    if (clipOutOfGamutColors)
    {
        fixedGammaColor = saturate(fixedGammaColor);
    }

    // Fix up negative luminance (imaginary/invalid colors)
    if (luminance(fixedGammaColor) < 0.f)
        fixedGammaColor = 0.f;
    
    // Fix raised blacks floor
    float3 fineTunedColor = fixedGammaColor;
    // Just do it by luminance for now, even if average or per channel might be better
    const float preRaisedBlacksFixLuminance = luminance(fineTunedColor);
    if (preRaisedBlacksFixLuminance > 0.f)
    {
        const float postRaisedBlacksFixLuminance = max(preRaisedBlacksFixLuminance - BLACK_FLOOR_LUMINANCE, 0.f);
        fineTunedColor *= (postRaisedBlacksFixLuminance / preRaisedBlacksFixLuminance) * (1.f / (1.f - BLACK_FLOOR_LUMINANCE));
    }
    
#if 0 // Remap shadows (per channel)
    fineTunedColor = remapFromZero(fineTunedColor, 0.f, SHADOW_TUNING, mid_gray * 0.5f);
#else // Remap shadows (luminance based)
    const float preFineTuningLuminance = luminance(fineTunedColor);
    if (preFineTuningLuminance > 0.f)
    {
        const float postFineTuningLuminance = remapFromZero(preFineTuningLuminance.xxx, 0.f, SHADOW_TUNING, mid_gray * 0.5f).x;
        fineTunedColor *= postFineTuningLuminance / preFineTuningLuminance;
    }
#endif

    float3 fixTonemapColor = fineTunedColor;
    if (INVERSE_TONEMAP_METHOD > 0)
    {
        if (INVERSE_TONEMAP_METHOD == 1) // Advanced Reinhard - Component based
        {
            fixTonemapColor = inv_tonemap_ReinhardPerComponent(fixTonemapColor, TONEMAPPER_WHITE_POINT);
            
            // Re-map the image to roughly keep the same average brightness
            fixTonemapColor /= inv_tonemap_ReinhardPerComponent(float3(mid_gray, mid_gray, mid_gray), TONEMAPPER_WHITE_POINT) / mid_gray;
        }
        else if (INVERSE_TONEMAP_METHOD == 2) // (Approximate) ACES Filmic
        {
            fixTonemapColor = inv_ACES_Filmic(fixTonemapColor);
        }
#if 0 // Disabled as it's unlikely to ever have been used by SDR games (tonemapping by luminance can create colors beyond 1) and it looks ugly
        else if (INVERSE_TONEMAP_METHOD == 3) // Advanced Reinhard - Luminance based
        {
            const float PreTonemapLuminance = luminance(fixTonemapColor);
            const float PostTonemapLuminance = inv_tonemap_ReinhardPerComponent(PreTonemapLuminance, TONEMAPPER_WHITE_POINT).r;
            fixTonemapColor *= PostTonemapLuminance / PreTonemapLuminance;
        }
#endif
        //TODO: add some other inverse tonemappers and SpecialK Perceptual Boost
    }

    const float SDRBrightnessScale = SDR_WHITEPOINT_NITS / sRGB_max_nits;

    // Auto HDR
    const bool doAutoHDR = AUTO_HDR_METHOD > 0 && AUTO_HDR_SHOULDER_START_ALPHA < 1.f;
    float3 autoHDRColor = fixTonemapColor;
    if (doAutoHDR)
    {
        float3 SDRRatio = 0.f;
        float3 divisor = 1.f;
        
        //TODO: delete all except average and channel?
        //TODO: Try to add a new method that does AutoHDR in PQ space (I gave it a quick attempt and it didn't seem to change much, though it might be easier for users to configure).
        //Alternatively, we could find the "SDRRation" with ICtCp.
        
        // By luminance
        if (AUTO_HDR_METHOD == 1)
        {
            SDRRatio = luminance(autoHDRColor);
        }
        // By average
        else if (AUTO_HDR_METHOD == 2)
        {
            SDRRatio = average(autoHDRColor);
        }
        // By channel
        else if (AUTO_HDR_METHOD == 3)
        {
            SDRRatio = autoHDRColor;
            
#if 0 // Disabled as this is currently broken. I don't think it ever worked.
            // Divide by luminance to make Auto HDR stronger on weaker channels, otherwise it's not really balanced visually
            divisor = K_BT709 / max3(K_BT709.x, K_BT709.y, K_BT709.z);
#endif
        }
        // By max channel
        else if (AUTO_HDR_METHOD == 4)
        {
            SDRRatio = max3(autoHDRColor.x, autoHDRColor.y, autoHDRColor.z);
        }
        // By OKLAB perceived lightness (~perceptually accurate)
        // This is perception space so it likely requires a different AutoHDR shoulder pow.
        else if (AUTO_HDR_METHOD == 5)
        {
            SDRRatio = linear_srgb_to_oklab(autoHDRColor)[0];
        }
        
        SDRRatio = max(SDRRatio, AUTO_HDR_SHOULDER_START_ALPHA);
        const float autoHDRMaxWhite = max(AUTO_HDR_MAX_NITS / SDRBrightnessScale, sRGB_max_nits) / sRGB_max_nits;
        const float3 autoHDRShoulderRatio = 1.f - (max(1.f - SDRRatio, 0.f) / (1.f - AUTO_HDR_SHOULDER_START_ALPHA));
        const float3 autoHDRExtraRatio = (pow(autoHDRShoulderRatio, AUTO_HDR_SHOULDER_POW) * (autoHDRMaxWhite - 1.f)) / divisor;
        const float3 autoHDRTotalRatio = SDRRatio + autoHDRExtraRatio;
        autoHDRColor *= autoHDRTotalRatio / SDRRatio;
    }
    
    fineTunedColor = autoHDRColor;
    if (HIGHLIGHT_SATURATION != 1.f)
    {
        const float OklabLightness = linear_srgb_to_oklab(fineTunedColor)[0];
        const float highlightSaturationRatio = max((OklabLightness - (2.f / 3.f)) / (1.f / 3.f), 0.f);
        fineTunedColor = saturation(fineTunedColor, lerp(1.f, HIGHLIGHT_SATURATION, highlightSaturationRatio));
    }

    float3 displayMappedColor = fineTunedColor;

    // Note: this is influenced by the AutoHDR params and by "SDRBrightnessScale".
    // Theoretically this should be done when the image is fully in linear space,
    // like 0-10k nits or more, before tonemapping, but we can't recreate such image from the data we have.
    if (EXTRA_HDR_SATURATION > 0.f)
    {
        // Do this with a paper white of 203 nits, so it's balanced (the formula seems to be made for that),
        // and gives consistent results independently of the user paper white
        const float recommendedBrightnessScale = ReferenceWhiteNits_BT2408 / sRGB_max_nits;
        
        fineTunedColor = displayMappedColor * recommendedBrightnessScale;
        fineTunedColor = expandGamut(fineTunedColor, EXTRA_HDR_SATURATION);
        displayMappedColor = fineTunedColor / recommendedBrightnessScale;
    }
    
    displayMappedColor *= SDRBrightnessScale;
    float HDRLuminance = luminance(displayMappedColor);
    
    // Display mapping.
    // Avoid doing it if we are doing AutoHDR within the screen brightness range already (even the result might snap based on the condition when we change params).
    if (HDRLuminance > 0.0f && (!doAutoHDR || (AUTO_HDR_MAX_NITS > HDR_MAX_NITS)))
    {
        const float maxOutputLuminance = HDR_MAX_NITS / sRGB_max_nits;
        const float highlightsShoulderStart = HIGHLIGHTS_SHOULDER_START_ALPHA * maxOutputLuminance;
        const float compressedHDRLuminance = lumaCompress(HDRLuminance, maxOutputLuminance, highlightsShoulderStart, HIGHLIGHTS_SHOULDER_POW);
        displayMappedColor *= compressedHDRLuminance / HDRLuminance;
    }

    displayMappedColor = fixNAN(displayMappedColor);

    if ((OUT_COLOR_SPACE == 0 && inColorSpace == 4) || OUT_COLOR_SPACE == 2)
    {
        displayMappedColor = BT709_to_BT2020(displayMappedColor);
        displayMappedColor = linear_to_PQ(displayMappedColor);
    }

    output = float4(displayMappedColor, 1.f);
}

technique AdvancedAutoHDR
<
ui_tooltip = "Meant to be used with SDR games + a hook (e.g. DXVK or SpecialK) that is able to replace the game buffers to float16 (scRGB). There is no BT.2020 support for now.";
>
{
    pass AdvancedAutoHDR
    {
        VertexShader = PostProcessVS;
        PixelShader = AdvancedAutoHDR;
    }
}