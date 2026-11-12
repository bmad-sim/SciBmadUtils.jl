#---------------------------------------------------------------------------------------------------
# Drawing of lattice layout plots with Makie. See src/layout_shapes.jl for what is drawn.
# This extension is loaded when Makie is loaded together with SciBmadUtils.
#---------------------------------------------------------------------------------------------------

module SciBmadUtilsMakieExt

using SciBmadUtils
using SciBmadUtils: LayoutShape, LayoutElement, lat_layout_shapes, _layout_elements, _keeps_aspect,
                    _normalize_to_unit_square, _filled_outline
import SciBmadUtils: lat_layout, lat_layout!, _unit_outline
using Beamlines: Lattice, scalarize
using Makie


# Vertical limits of a layout axis. Shapes extend to at most ±0.5. When there are labels, the
# bottom limit is lowered to make room for the (rotated) labels. See `_set_layout_ylims!`.
const LAYOUT_YTOP = 0.6
const LAYOUT_YBOTTOM = -0.6

function _with_alpha(c, alpha)
  rgba = Makie.to_color(c)
  return Makie.RGBAf(rgba.r, rgba.g, rgba.b, alpha)
end

# Return [s_start, s_end] of the whole line (including drifts and other undrawn elements).
function _s_range(line, branch)
  eles = line isa Lattice ? _layout_elements(line; branch = branch) : _layout_elements(line)
  isempty(eles) && return (0.0, 0.0)
  s0 = Float64(scalarize(first(eles).s))
  s1 = Float64(scalarize(last(eles).s)) + Float64(scalarize(last(eles).L))
  return (s0, s1)
end

# Custom shape given as an SVG path string. Curves are approximated by line segments.
function _unit_outline(svg::AbstractString)
  bp = Makie.replace_nonfreetype_commands(BezierPath(svg))  # Arcs -> curves, ClosePath -> LineTo
  polys = Vector{NTuple{2,Float64}}[]
  last = (0.0, 0.0)
  for c in bp.commands
    if c isa MoveTo
      push!(polys, [Tuple(c.p)])
    elseif c isa LineTo
      push!(polys[end], Tuple(c.p))
    elseif c isa CurveTo
      p0, p1, p2, p3 = Point2d(last), c.c1, c.c2, c.p
      for t in range(0, 1, length = 13)[2:end]
        push!(polys[end], Tuple((1-t)^3 * p0 + 3(1-t)^2*t * p1 + 3(1-t)*t^2 * p2 + t^3 * p3))
      end
    end
    last = polys[end][end]
  end
  filter!(p -> length(p) > 1, polys)
  isempty(polys) && error("SVG path for a lattice layout shape has no drawable segments: $(repr(svg))")
  polys = _normalize_to_unit_square(polys)
  polys = [[(x, 1 - y) for (x, y) in poly] for poly in polys]  # SVG y points down
  return _filled_outline(polys...)
end

# Map a point in the unit square to the data rectangle [x0, x0+w] × [y0, y0+h].
_to_data(p, x0, w, y0, h) = Point2f(x0 + p[1] * w, y0 + p[2] * h)

# Append fills and strokes of `outline` mapped to a data rectangle.
function _append_shape!(polys, poly_fill, segs, seg_color, outline, fillc, linec, x0, w, y0, h)
  for f in outline.fills
    push!(polys, [_to_data(p, x0, w, y0, h) for p in f])
    push!(poly_fill, fillc)
  end
  for st in outline.strokes, i in 1:length(st)-1
    push!(segs, _to_data(st[i], x0, w, y0, h), _to_data(st[i+1], x0, w, y0, h))
    push!(seg_color, linec, linec)
  end
end

#---------------------------------------------------------------------------------------------------

function lat_layout!(ax::Makie.AbstractAxis, line; shapes = Dict{String,LayoutShape}(),
                     polarity::Bool = false, branch = 1, labels::Bool = true,
                     label_fontsize = 10, fill_alpha = 0.5, strokewidth = 1,
                     centerline::Bool = true, set_limits::Bool = true)
  les = lat_layout_shapes(line; shapes = shapes, polarity = polarity, branch = branch)

  # All drawing is batched into a few plot objects so that large rings are drawn quickly.
  # Shapes that span the element are fixed in data coordinates. Shapes that keep their on-screen 
  # aspect ratio (circles and zero-length elements) depend on the axis scaling and so are 
  # recomputed when the axis limits or size change.
  polys      = Vector{Point2f}[]   # Filled polygons
  poly_fill  = Makie.RGBAf[]
  segs       = Point2f[]           # Outlines. Pairs of points.
  seg_color  = Makie.RGBAf[]
  aspect     = Tuple{LayoutElement,Any,Makie.RGBAf,Makie.RGBAf}[]  # (element, outline, fill, line)
  lpos       = Point2f[]           # Labels
  ltext      = String[]
  outlines   = IdDict{Any,Any}()   # Cache of outlines, mainly for SVG shapes

  for le in les
    ls = le.shape
    outline = get!(() -> _unit_outline(ls.shape), outlines, ls.shape)
    linec = Makie.to_color(something(ls.line_color, ls.color))
    fillc = isnothing(ls.fill_color) ? _with_alpha(ls.color, fill_alpha) : Makie.to_color(ls.fill_color)
    s0, s1, yb, yt = le.s_start, le.s_end, le.y_bottom, le.y_top
    if _keeps_aspect(le)
      push!(aspect, (le, outline, fillc, linec))
    else
      _append_shape!(polys, poly_fill, segs, seg_color, outline, fillc, linec, s0, s1 - s0, yb, yt - yb)
    end

    if labels && ls.label && !isempty(le.name)
      push!(lpos, Point2f((s0 + s1) / 2, min(yb, 0.0) - 0.08))
      push!(ltext, le.name)
    end
  end

  s_lo, s_hi = _s_range(line, branch)
  if centerline
    lines!(ax, [s_lo, s_hi], [0.0, 0.0]; color = :black, linewidth = 1)
  end
  isempty(polys) || poly!(ax, polys; color = poly_fill, strokewidth = 0)
  isempty(segs)  || linesegments!(ax, segs; color = seg_color, linewidth = strokewidth)

  if !isempty(aspect)
    # Data width in s per unit of data height in y that looks equal on screen.
    s_per_y = lift(ax.finallimits, ax.scene.viewport) do lims, vp
      wl, wv = Makie.widths(lims), Makie.widths(vp)
      any(iszero, (wl[2], wv[1], wv[2])) ? 0.0 : (wv[2] / wl[2]) / (wv[1] / wl[1])
    end
    shapes_obs = lift(s_per_y) do r
      apolys, afill, asegs, acolor = Vector{Point2f}[], Makie.RGBAf[], Point2f[], Makie.RGBAf[]
      for (le, outline, fillc, linec) in aspect
        h = le.y_top - le.y_bottom
        w = h * r
        x0 = (le.s_start + le.s_end) / 2 - w / 2
        _append_shape!(apolys, afill, asegs, acolor, outline, fillc, linec, x0, w, le.y_bottom, h)
      end
      (apolys, afill, asegs, acolor)
    end
    apolys = lift(x -> x[1], shapes_obs)
    asegs  = lift(x -> x[3], shapes_obs)
    isempty(apolys[]) || poly!(ax, apolys; color = shapes_obs[][2], strokewidth = 0)
    isempty(asegs[])  || linesegments!(ax, asegs; color = shapes_obs[][4], linewidth = strokewidth)
  end

  isempty(lpos)  || text!(ax, lpos; text = ltext, rotation = π/2, align = (:right, :center),
                          fontsize = label_fontsize)

  if set_limits
    # Length in pixels of the longest rotated label plus a margin.
    label_px = isempty(ltext) ? 0.0 : _max_text_width(ltext, label_fontsize) + 8
    _set_layout_ylims!(ax, label_px)
  end
  return ax
end

# Width in pixels of the widest string in `texts` drawn in the current theme's regular font.
# Falls back to an estimate if the font cannot be determined.
function _max_text_width(texts, fontsize)
  try
    font = Makie.to_font(Makie.theme(:fonts), :regular)
    return maximum(t -> Makie.widths(Makie.text_bb(t, font, fontsize))[1], texts)
  catch
    return 0.6 * fontsize * maximum(length, texts)
  end
end

# Set the y-limits of a layout axis so that the space for the labels is `label_px` pixels 
# independent of the axis height. Since the axis height is only known once the figure layout 
# is computed, the limits are updated whenever the axis viewport changes.
function _set_layout_ylims!(ax, label_px)
  function update(h)
    if label_px == 0
      ylims!(ax, LAYOUT_YBOTTOM, LAYOUT_YTOP)
    else
      shape_px = h > 0 ? max(h - label_px, 0.3 * h) : 2 * label_px  # Fallback before layout
      ylims!(ax, LAYOUT_YBOTTOM - label_px * (LAYOUT_YTOP - LAYOUT_YBOTTOM) / shape_px, LAYOUT_YTOP)
    end
  end
  on(vp -> update(Makie.widths(vp)[2]), ax.scene.viewport; update = true)
end

#---------------------------------------------------------------------------------------------------

function lat_layout(gp::Union{Makie.GridPosition,Makie.GridSubposition}, line; link = nothing,
                    height = 80, labels::Bool = true, axis = (;), kwargs...)
  ax = Axis(gp; height = height, xgridvisible = false, ygridvisible = false,
            leftspinevisible = false, rightspinevisible = false,
            topspinevisible = false, bottomspinevisible = false, axis...)
  hideydecorations!(ax)
  haskey(axis, :xlabel) || hidexdecorations!(ax)
  ax.yzoomlock = true
  ax.ypanlock = true
  ax.yrectzoom = false

  lat_layout!(ax, line; labels = labels, kwargs...)

  if isnothing(link)
    branch = get(kwargs, :branch, 1)
    s_lo, s_hi = _s_range(line, branch)
    s_hi > s_lo && xlims!(ax, s_lo, s_hi)
  else
    linkxaxes!(ax, (link isa AbstractVector ? link : [link])...)
  end
  return ax
end

end
