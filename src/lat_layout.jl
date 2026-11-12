#---------------------------------------------------------------------------------------------------
# Lattice layout drawing functions. These are implemented in the Makie extension
# (ext/SciBmadUtilsMakieExt.jl), which is loaded when Makie is loaded.
#---------------------------------------------------------------------------------------------------

"""
    lat_layout!(ax, line; kwargs...) -> ax

Draw a lattice layout of `line` (a `Beamline`, `Branch`, `Lattice` or vector of `LineElement`s)
into the existing Makie `Axis` `ax`.

The center line is at `y = 0` and shapes extend to at most `y = ±0.5`. Element labels are
drawn rotated, below the shapes. See `LayoutShape` for the available shapes and colors.

## Keyword arguments
- `shapes`, `polarity`, `branch`: See `lat_layout_shapes`.
- `labels = true`:      Draw element names (for shapes with `label = true`).
- `label_fontsize = 10`: Font size of the labels.
- `fill_alpha = 0.5`:   Opacity of the shape fill for shapes whose `fill_color` is `nothing`. 
  Set to `0` for outline-only shapes as in Tao.
- `strokewidth = 1`:    Line width of the shape outlines.
- `centerline = true`:  Draw the horizontal center line along the full `s` range.
- `set_limits = true`:  Set the y-limits of `ax` to fit the shapes and labels. The space for 
  the labels is sized in pixels from the longest label, so it does not grow with the axis height.

A Makie backend (e.g. CairoMakie or GLMakie) must be loaded. See also `lat_layout`, which creates an appropriately formatted `Axis`.
"""
function lat_layout! end

"""
    lat_layout(gridpos, line; link = nothing, height = 80, labels = true, axis = (;), kwargs...) -> Axis

Create a new Makie `Axis` at the figure grid position `gridpos` (e.g. `fig[2, 1]`) and draw
a lattice layout of `line` into it. A Makie backend (e.g. CairoMakie or GLMakie) must be loaded.

The y-axis decorations, grid and spines are hidden. The x-axis decorations are also hidden
unless `axis` says otherwise, since normally the layout shares its `s` axis with the
plot(s) that it accompanies. Zooming and panning are restricted to `s`.

## Keyword arguments
- `link`:   An `Axis` or vector of `Axis`es whose x-axes are linked to the layout so that
  zooming/panning stays in sync. If `nothing`, the x-limits are set to the `s` range of `line`.
- `height`: Height of the layout axis in pixels.
- `axis`:   `NamedTuple` of extra attributes passed to the `Axis` constructor, e.g.
  `axis = (xlabel = "s [m]",)`. If `xlabel` is given, x decorations are shown.
- Other keywords are passed to `lat_layout!`.

## Example
```julia
using SciBmadUtils, CairoMakie
fig = Figure()
ax  = Axis(fig[2, 1], xlabel = "s [m]", ylabel = "β [m]")
lines!(ax, s, beta)
lat_layout(fig[1, 1], bl; link = ax)   # Layout above the plot. Use fig[3, 1] for below.
fig
```
"""
function lat_layout end
