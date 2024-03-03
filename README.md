# How to use
Download the files in this repository (github allows to download a full zip) and install the latest version of ReShade (e.g. 5.8+, untested with older versions).
Drop into the local "reshade-shaders" folder.

Under normal conditions, this ReShade shader requires Lilium's DXVK fork, which is able to force games to use scRGB (RGBA16F) textures as internal render targets and output, this allows for 3 things:
 - The quality of the output image is increased, due to a higher bit depth
 - The image retains any "overbright" pixels, as in, colors the game tried to draw beyond the 0-1 range that would get lost in SDR
 - Forcing Windows to interpret the image as an HDR one
The fork can be found here:
https://github.com/EndlesslyFlowering/dxvk/releases/
Note that buffers need to be upgraded to float16 for scRGB HDR to engage, and ReShade needs to be installed for Vulkan.

Additionally, this shader also directly works with games that natively support scRGB (RGBA16F) output, though generally these are already HDR so AutoHDR wouldn't be needed.
SpecialK can also be used to enforce scRGB output.
The AddOn from this similar ReShade https://github.com/EndlesslyFlowering/AutoHDR-ReShade (original by MajorPainTheCactus) can also be used to enforce HDR output on some games.
Some games, like Starfield, support mods to force scRGB output even if the game is still rendering in SDR. This shader can be directly used with these.

For support: https://discord.gg/px7EEfM2YF

# How does this work
Differently from most other AutoHDR implementations (e.g. Windows 11 one, SpecialK, ...) this shader aims to be more of an additive enhancment that doesn't drastically change the image, but just makes it shine.
Additionally, you can also specify the gamma of the source SDR image (Windows AutoHDR assumes SDR signals follow the sRGB gamma, but that's barely ever true for games, as most of them were designed and calibrated on gamma 2.2 displays).

There are multiple AutoHDR implementations offered through a drop down list, but most of them are color hue conserving, thus only impact the brightness of the colors, preserving the original look much more compared to the common alternative.
With the default settings, highlights are boosted but shadows and midtones are left almost completely untouched.
One downside of this is that you might notice some kind of shift when AutoHDR starts being applied, but that's generally fixable by tweaking the settings.

Alternatively, there's also an "inverse tonemap" implementation that is similar to AutoHDR, but it's not color conserving.
Use it if you prefer it. The "Highlights shoulder" settings only affect the inverse tonemap path under normal conditions.

This shader can also be used as an additional clipping preventing tonemapping pass for HDR games that do not correctly map their output to the display brightness (e.g. game outputting 10000 nits, while your screen can do up to 800).

For anything else, read the tooltip of each setting.

# A decent preset

The default values are already calibrated to look decent under most cases.
Some general suggestions:
- "Auto HDR target/max brightness": avoid setting it beyond ~750 nits (even if your screen supports it) as it will likely just always be too bright. This AutoHDR method is additive, so you don't want your picture to be unbalanced towards highlights.
- "Auto HDR shoulder start alpha": the lower the better. Setting it to 0 can provide the best results as it prevents the point where AutoHDR starts being applied from being seen.

# Credits
Thanks to Lilium for the support


<a href="https://www.buymeacoffee.com/realFiloppi" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>
