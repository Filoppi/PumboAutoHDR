#include "ReShade.fxh"
#include "Color.fxh"

#define COLOR_SPACE_UNKNOWN     0
#define COLOR_SPACE_SRGB        1
#define COLOR_SPACE_SCRGB       2
#define COLOR_SPACE_BT2020_PQ   3

#if BUFFER_COLOR_SPACE == COLOR_SPACE_SRGB
  #define ACTUAL_COLOR_SPACE 0
#elif BUFFER_COLOR_SPACE == COLOR_SPACE_SCRGB
  #define ACTUAL_COLOR_SPACE 2
#elif BUFFER_COLOR_SPACE == COLOR_SPACE_BT2020_PQ
  #define ACTUAL_COLOR_SPACE 3
#else
  #define ACTUAL_COLOR_SPACE 0
#endif

// We don't default to "ACTUAL_COLOR_SPACE" here as if we are upgrading the backbuffer, we'd detect the wrong value
uniform uint IN_COLOR_SPACE
<
  ui_label    = "Input Color Space";
  ui_type     = "combo";
  ui_items    = "SDR sRGB\0SDR Rec.709 Gamma 2.2\0HDR scRGB\0HDR10 BT.2020 PQ\0";
  ui_tooltip = "Specify the input color space.\nSome SDR games use sRGB gamma and some other use 2.2 gamma, pick the one that looks more correct.\nFor HDR, either pick scRGB or HDR10";
  ui_category = "Calibration";
> = 0;

uniform bool IGNORE_SDR_GAMMA_OVER_1
<
  ui_label = "Ignore gamma on SDR colors beyond 1";
  ui_tooltip = "Some games never really directly used the gamma formula for output, they just baked content and shaders to automatically look right on gamma screens.\nIf these games output values above 1, it's generally good to not undo the gamma curve on these colors";
  ui_category = "Calibration";
> = false;

uniform bool FORCE_SCRGB_OUT_COLOR_SPACE
<
  ui_label = "Force scRGB Output Color Space";
  ui_category = "Calibration";
> = true;

uniform float SDR_WHITEPOINT_NITS
<
  ui_label = "SDR white point (paper white) nits";
  ui_type = "drag";
  ui_category = "Calibration";
  ui_min = 1.f;
  ui_max = 500.f;
  ui_step = 1.f;
> =
BT709_max_nits;

uniform float HDR_MAX_NITS
<
  ui_label = "HDR display max nits";
  ui_category = "Calibration";
  ui_type = "drag";
  ui_min =
BT709_max_nits;
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
  ui_max = 8.f;
  ui_step = 0.05f;
> = 1.f;

uniform uint INVERSE_TONEMAP_METHOD
<
  ui_category = "Inverse tone mapping";
  ui_label    = "Inverse tonemap method";
  ui_tooltip  = "Do not use with Auto HDR";
  ui_type     = "combo";
  ui_items    = "None\0Advanced Reinhard by channel\0";
> = 0;

uniform float TONEMAPPER_WHITE_POINT
<
  ui_label = "Tonemapper white point (in units)";
  ui_tooltip = "Useful to invert the tonemapper. Increases saturation. Has no effect at 1";
  ui_category = "Inverse tone mapping";
  ui_type = "drag";
  ui_min = 1.f;
  ui_max = 100.f;
  ui_step = 0.01f;
> = 2.f;

uniform uint AUTO_HDR_METHOD
<
  ui_category = "Auto HDR";
  ui_label    = "Auto HDR method";
  ui_type     = "combo";
  ui_items    = "None\0By channel average (color conserving) - RECCOMENDED\0By luminance (color conserving)\0By channel (increases saturation)\0By max channel (color conserving)\0";
> = 0;

uniform float AUTO_HDR_SHOULDER_START_ALPHA
<
  ui_label = "Auto HDR shoulder start alpha";
  ui_tooltip = "Determines how bright an SDR color needs to be before we start scaling its brightness to generate fake HDR highlights. Has no effect at 1";
  ui_category = "Auto HDR";
  ui_type = "drag";
  ui_min = 0.f;
  ui_max = 1.f;
  ui_step = 0.01f;
> = 0.f;

uniform float AUTO_HDR_MAX_NITS
<
  ui_label = "Auto HDR target/max brightness";
  ui_category = "Auto HDR";
  ui_type = "drag";
  ui_min = BT709_max_nits;
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
  ui_max = 8.f;
  ui_step = 0.05f;
> = 2.5f;

uniform float BLACK_FLOOR_LUMINANCE
<
  ui_label = "Black floor luminance";
  ui_tooltip = "Fixes raised black floors by remapping (by luminance) colors";
  ui_category = "Fine tuning";
  ui_type = "drag";
  ui_min = 0.0f;
  ui_max = mid_gray;
  ui_step = 0.000001f;
> = 0.f;

uniform float SHADOW_TUNING
<
  ui_label = "Shadow";
  ui_tooltip = "Rebalances shadow. Neutral at 1";
  ui_category = "Fine tuning";
  ui_type = "drag";
  ui_min = 0.01f;
  ui_max = 10.f;
  ui_step = 0.01f;
> = 1.f;

uniform float EXTRA_HDR_SATURATION
<
  ui_label = "Extra HDR saturation";
  ui_tooltip = "Generates HDR colors (BT.2020) from bright saturated SDR (BT.709) ones";
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
    fixedGammaColor = clamp(fixedGammaColor, -65504.f, 65504.f);

    if (IN_COLOR_SPACE == 0) // sRGB
        fixedGammaColor = sRGB_to_linear(fixedGammaColor, IGNORE_SDR_GAMMA_OVER_1);
    else if (IN_COLOR_SPACE == 1) // Rec.709 Gamma 2.2
        fixedGammaColor = (IGNORE_SDR_GAMMA_OVER_1 && fixedGammaColor >= 1) ? fixedGammaColor : pow(fixedGammaColor, 2.2f);
    else if (IN_COLOR_SPACE == 3) // HDR10 BT.2020 PQ
    {
        fixedGammaColor = PQ_to_linear(fixedGammaColor);
        fixedGammaColor = BT2020_to_BT709(fixedGammaColor);
    }

    // Fix up negative luminance (imaginary/invalid colors)
    if (luminance(fixedGammaColor) < 0.f)
        fixedGammaColor = float3(0.f, 0.f, 0.f);
    
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
    if (INVERSE_TONEMAP_METHOD > 0 && TONEMAPPER_WHITE_POINT != 1.0f) // Reinhard has no effect with a white point of 1
    {
        if (INVERSE_TONEMAP_METHOD == 1) // Advanced Reinhard - Component based
            fixTonemapColor = inv_tonemap_ReinhardPerComponent(fixTonemapColor, TONEMAPPER_WHITE_POINT);
#if 0 // Disabled as it's unlikely to ever have been used by SDR games and it looks ugly
        else if (INVERSE_TONEMAP_METHOD == 2) // Advanced Reinhard - Luminance based
        {
            const float PreTonemapLuminance = luminance(fixTonemapColor);
            const float PostTonemapLuminance = inv_tonemap_ReinhardPerComponent(PreTonemapLuminance, TONEMAPPER_WHITE_POINT).r;
            fixTonemapColor *= PostTonemapLuminance / PreTonemapLuminance;
        }
#endif
        //TODO: add some other inverse tonemappers and SpecialK Perceptual Boost
        
        // Re-map the image to roughly keep the same average brightness
        fixTonemapColor /= inv_tonemap_ReinhardPerComponent(float3(mid_gray, mid_gray, mid_gray), TONEMAPPER_WHITE_POINT) / mid_gray;
    }

    const float SDRBrightnessScale = SDR_WHITEPOINT_NITS / BT709_max_nits;

    // Auto HDR
    float3 autoHDRColor = fixTonemapColor;
    if (AUTO_HDR_METHOD > 0)
    {
        float3 SDRRatio = 0.f;
        float3 divisor = 1.f;
        
        //TODO: delete all except average and channel?
        
        // By average
        if (AUTO_HDR_METHOD == 1)
        {
            SDRRatio = average(autoHDRColor);
        }
        // By luminance
        else if (AUTO_HDR_METHOD == 2)
        {
            SDRRatio = luminance(autoHDRColor);
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
        
        [unroll]
        for (int i = 0; i < 3; ++i)
        {
            const float autoHDRMaxWhite = max(AUTO_HDR_MAX_NITS / SDRBrightnessScale, BT709_max_nits) / BT709_max_nits;
            if (SDRRatio[i] > AUTO_HDR_SHOULDER_START_ALPHA && AUTO_HDR_SHOULDER_START_ALPHA < 1.f)
            {
                const float autoHDRShoulderRatio = 1.f - (max(1.f - SDRRatio[i], 0.f) / (1.f - AUTO_HDR_SHOULDER_START_ALPHA));
                const float autoHDRExtraRatio = (pow(autoHDRShoulderRatio, AUTO_HDR_SHOULDER_POW) * (autoHDRMaxWhite - 1.f)) / divisor[i];
                const float autoHDRTotalRatio = SDRRatio[i] + autoHDRExtraRatio;
                autoHDRColor[i] *= autoHDRTotalRatio / SDRRatio[i];
            }
        }
    }

    float3 displayMappedColor = autoHDRColor;
    displayMappedColor *= SDRBrightnessScale;

    fineTunedColor = displayMappedColor;
    float HDRLuminance = luminance(displayMappedColor);
    // Note: this is influenced by the AutoHDR params and by "SDRBrightnessScale"
    if (EXTRA_HDR_SATURATION > 0.f && HDRLuminance > 0.f)
    {
        fineTunedColor = expandGamut(fineTunedColor, EXTRA_HDR_SATURATION);
        HDRLuminance = luminance(fineTunedColor);
    }
    displayMappedColor = fineTunedColor;

    // Display mapping.
    // Avoid doing it if we are doing AutoHDR within the screen brightness range already (even the result might snap based on the condition when we change params).
    if (HDRLuminance > 0.0f && (AUTO_HDR_METHOD == 0 || (AUTO_HDR_MAX_NITS > HDR_MAX_NITS)))
    {
        const float maxOutputLuminance = HDR_MAX_NITS / BT709_max_nits;
        const float highlightsShoulderStart = HIGHLIGHTS_SHOULDER_START_ALPHA * maxOutputLuminance;
        const float compressedHDRLuminance = lumaCompress(HDRLuminance, maxOutputLuminance, highlightsShoulderStart, HIGHLIGHTS_SHOULDER_POW);
        displayMappedColor *= compressedHDRLuminance / HDRLuminance;
    }

    displayMappedColor = fixNAN(displayMappedColor);

    if (!FORCE_SCRGB_OUT_COLOR_SPACE && IN_COLOR_SPACE == 3)
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