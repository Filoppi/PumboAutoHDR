# How to use
Download and install the latest version of ReShade (e.g. 5.8+).
Drop into the local "reshade-shaders\Shaders" folder.

Under normal conditions, this ReShade shader requires Lilium's DXVK fork, which is able to force games to use scRGB (RGBA16F) textures as internal render targets and output, this allows for 3 things:
 - The quality of the output image is increased, due to a higher bit depth
 - The image retains any "overbright" pixels, as in, colors the game tried to draw beyond the 0-1 range that would get lost in SDR
 - Forcing Windows to interpret the image as an HDR one
The fork can be found here:
https://github.com/EndlesslyFlowering/dxvk/releases/

Additionally, this shader would also directly work with games natively support scRGB (RGBA16F) output, though generally these are already HDR so AutoHDR wouldn't be needed.

# How does this work
Differently from most other AutoHDR implementations (e.g. Windows 11 one, SpecialK, ...) this shader aims to be more of an additive enhancment that doesn't drastically change the image, but just makes it shine.

There are multiple AutoHDR implementations offered through a drop down list, but most of them are color hue conserving, thus only impact the brightness of the colors, preserving the original look much more compared to the common alternative.
With the default settings, highlights are boosted but shadows and midtones are left almost completely untouched.
One downside of this is that you might notice some kind of shift when AutoHDR starts being applied, but that's generally fixable by tweaking the settings.

Alternatively, there's also an "inverse tonemap" implementation that is similar to AutoHDR, but it's not color conserving.
Use it if you prefer it. The "Highlights shoulder" settings only affect the inverse tonemap path under normal conditions.

For anything else, read the tooltip of each setting.

# A decent preset
![Image](https://gcdnb.pbrd.co/images/YzZICs8w7mrY.png?o=1)

This preset was created for my local modded version of "Fallout: New Vegas" so it might not apply to other games.
In general, I suggest setting the max output nits beyond 700 (even if your screen supports it) as it will likely just always be to bright.

# Credits
Thanks to Lilium for the support
