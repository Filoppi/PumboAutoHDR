#include "ReShade.fxh"
#include "Color.fxh"

// These are from the "color_space" enum in ReShade
#define RESHADE_COLOR_SPACE_UNKNOWN     0
#define RESHADE_COLOR_SPACE_SRGB        1
#define RESHADE_COLOR_SPACE_SCRGB       2
#define RESHADE_COLOR_SPACE_BT2020_PQ   3

// "BUFFER_COLOR_SPACE" is defined by ReShade.
// "ACTUAL_COLOR_SPACE" uses the enum values defined in "IN_COLOR_SPACE" below.
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
#define DEFAULT_COLOR_SPACE 2

// We don't default to "Auto" here as if we are upgrading the backbuffer, we'd detect the wrong value
uniform uint IN_COLOR_SPACE
<
  ui_label    = "Input Color Space";
  ui_type     = "combo";
  ui_items    = "Auto\0SDR sRGB\0SDR Rec.709 Gamma 2.2\0SDR Rec.709 Gamma 2.4\0HDR scRGB\0HDR10 (BT.2020 PQ)\0";
  ui_tooltip = "Specify the input color space (\"Auto\" is usually correct).\nMost SDR games targeted \"Gamma 2.2\", though some targeted \"sRGB\", pick the one that looks more correct.\nFor HDR, either pick \"scRGB\" or \"HDR10\"";
  ui_category = "Calibration";
> = DEFAULT_COLOR_SPACE;

uniform float BRIGHTGNESS_SCALE
<
  ui_label = "Brightness Scale";
  ui_type = "drag";
  ui_tooltip = "Controls how bright the output image is. A value of 1 is \"neutral\"";
  ui_category = "Calibration";
  ui_min = 0.01f;
  ui_max = 10.f;
  ui_step = 0.1f;
> = 1.f;

uniform uint OUT_COLOR_SPACE
<
  ui_label    = "Output Color Space";
  ui_type     = "combo";
  ui_items    = "Auto\0SDR sRGB\0SDR Rec.709 Gamma 2.2\0SDR Rec.709 Gamma 2.4\0HDR scRGB\0HDR10 (BT.2020 PQ)\0";
  ui_tooltip = "Specify the output color space";
  ui_category = "Advanced calibration";
> = 0;

void ConvertColorSpace(
      float4 vpos : SV_Position,
      float2 texcoord : TEXCOORD,
  out float4 output : SV_Target0)
{
    const float3 input = tex2D(ReShade::BackBuffer, texcoord).rgb;

    float3 displayMappedColor = input;
    displayMappedColor = clamp(displayMappedColor, -FLT16_MAX, FLT16_MAX);
    
    uint inColorSpace = IN_COLOR_SPACE;
    if (inColorSpace == 0) // Auto selection
    {
        if (ACTUAL_COLOR_SPACE == 0) // Fall back on default if the actual color space is unknown
            inColorSpace = DEFAULT_COLOR_SPACE;
        else
            inColorSpace = ACTUAL_COLOR_SPACE;
    }

    if (inColorSpace == 0 || inColorSpace == 1) // sRGB (and Auto)
        displayMappedColor = sRGB_to_linear_mirrored(displayMappedColor);
    else if (inColorSpace == 2 || inColorSpace == 3) // Rec.709 Gamma 2.2 | Rec.709 Gamma 2.4
    {
        const float gamma = (inColorSpace == 2) ? 2.2f : 2.4f;
        displayMappedColor = gamma_to_linear_mirrored(displayMappedColor, gamma);

    }
    else if (inColorSpace == 5) // HDR10 BT.2020 PQ
    {
        displayMappedColor = PQ_to_linear(displayMappedColor); // We use sRGB white level (80 nits, not 100)
        displayMappedColor = BT2020_to_BT709(displayMappedColor);
    }
    
    displayMappedColor *= BRIGHTGNESS_SCALE;
    
    uint outColorSpace = OUT_COLOR_SPACE == 0 ? ACTUAL_COLOR_SPACE : OUT_COLOR_SPACE;
    if (outColorSpace == 1)
    {
        displayMappedColor = linear_to_sRGB_mirrored(displayMappedColor);
    }
    else if (outColorSpace == 2 || outColorSpace == 3)
    {
        const float gamma = (outColorSpace == 2) ? 2.2f : 2.4f;
        displayMappedColor = linear_to_gamma_mirrored(displayMappedColor, gamma);
    }
    else if (outColorSpace == 5)
    {
        displayMappedColor = BT709_to_BT2020(displayMappedColor);
        displayMappedColor = linear_to_PQ(displayMappedColor);
    }

    output = float4(displayMappedColor, 1.f);
}

technique ConvertColorSpace
<
ui_tooltip = "This shader can convert between a source and a target color space, transfer functions etc (basically, video standards).\nYOU DO NOT NEED THIS under normal circumstances, but it can be useful in case you are using AdvancedAutoHDR with REST.";
>
{
    pass ConvertColorSpace
    {
        VertexShader = PostProcessVS;
        PixelShader = ConvertColorSpace;
    }
}
