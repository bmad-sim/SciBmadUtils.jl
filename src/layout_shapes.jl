#---------------------------------------------------------------------------------------------------
# Lattice layout plots.
#
# A lattice layout is a strip, usually placed above or below a plot of some quantity versus `s`
# (e.g. Twiss functions), that shows where the lattice elements are as a function of `s`.
# This is modeled after the Tao `lat_layout` plot.
#
# The geometry of the layout (what shape to draw where) is computed here, 
# the actual drawing is done in lat_layout.jl.
#---------------------------------------------------------------------------------------------------

"""
    LayoutShape(; shape = :box, color = :black, fill_color = nothing, line_color = nothing, 
                  size = 0.3, height_param = nothing, label = true, draw = true)

How an element is drawn in a lattice layout plot (see `lat_layout`).

## Fields
- `shape`: One of the following `Symbol`s:
  - `:box`             Rectangle.
  - `:xbox`            Rectangle with an "X" through it.
  - `:x`               An "X" (not filled).
  - `:circle`          Circle.
  - `:oval`            Ellipse filling the element's extent.
  - `:diamond`         Diamond.
  - `:bowtie`          Two triangles whose tips meet at the center: ⋈.
  - `:vertical_bowtie` Two triangles whose tips meet at the center, one above the other (hourglass).
  - `:vertical_bar`    Vertical line at the element center (not filled).
  - `:up_triangle`     Triangle with a vertex at the top.
  - `:down_triangle`   Triangle with a vertex at the bottom.
  - `:right_triangle`  Triangle with a vertex to the right.
  - `:left_triangle`   Triangle with a vertex to the left.
  - `:star_5`          Five pointed star.
  - `:star_6`          Six pointed star.
  - `:var_box`         Rectangle whose height varies with an element parameter. One edge is at 
                       the center line and the other is at `size * p` where `p` is given by 
                       `height_param`. So the box is above the center line if `p > 0` and 
                       below if `p < 0`.

  `:circle`, `:star_5` and `:star_6` keep their on-screen proportions and are drawn at the 
  element center independent of the element length.

  or a custom shape, which is scaled to fit the element's extent:
  - A vector of `(x, y)` points (e.g. `[(0, 0), (1, 0), (0.5, 1)]`) defining a closed polygon.
  - An SVG path string (the `d` attribute of an SVG `<path>`), e.g. `"M 0 0 L 10 0 L 5 10 Z"`. 
    Separate subpaths are drawn as separate polygons (holes are not cut out). As in SVG, 
    `y` increases downward.
- `color`:      Default for `fill_color` and `line_color`. Any color Makie understands, e.g. 
  `:red`, `"#ff0000"`, or `(:red, 0.5)` (with opacity).
- `fill_color`: Fill color. If `nothing`, `color` is used with opacity set by the `fill_alpha` 
  argument of `lat_layout!`. Use `:transparent` for an unfilled shape.
- `line_color`: Color of the outline. If `nothing`, `color` is used.
- `size`:  Half-height of the shape. The layout's center line is at `y = 0` and the
  largest default shape has `size = 0.5`.
- `height_param`: For a `:var_box`, the element parameter that sets the height. Either the 
  name of an element property (e.g. `:Kn1`), or a function of the element 
  (e.g. `ele -> ele.Kn1 * ele.L`). Choose `size` so that `size * p` fits within the layout's 
  vertical range of about ±0.6. Larger values are clipped.
- `label`: If `true`, the element's name (if not blank) is drawn below the shape.
- `draw`:  If `false`, the element is not drawn at all.

Zero-length elements are drawn with a width on screen equal to their height. 
"""
Base.@kwdef struct LayoutShape
  shape         = :box
  color         = :black
  fill_color    = nothing
  line_color    = nothing
  size::Float64 = 0.3
  height_param  = nothing
  label::Bool   = true
  draw::Bool    = true
end

function Base.show(io::IO, ls::LayoutShape)
  print(io, "LayoutShape(shape = $(repr(ls.shape)), color = $(repr(ls.color)), ",
            "fill_color = $(repr(ls.fill_color)), line_color = $(repr(ls.line_color)), ",
            "size = $(ls.size), height_param = $(repr(ls.height_param)), label = $(ls.label), ",
            "draw = $(ls.draw))")
end

"""
    DEFAULT_LAYOUT_SHAPES

`Dict` mapping an element `kind` (e.g. `"Quadrupole"`) to the `LayoutShape` used to draw
elements of that kind in a lattice layout plot. Modeled after the Tao default shapes.
Elements whose `kind` is not in the table are not drawn.

Modify this `Dict` to change the defaults for the session, or pass a `shapes` argument to
`lat_layout`/`lat_layout!`/`lat_layout_shapes` to override entries for a single plot.
"""
const DEFAULT_LAYOUT_SHAPES = Dict{String,LayoutShape}(
  "Drift"      => LayoutShape(draw = false),
  "SBend"      => LayoutShape(shape = :box,           color = :black,   size = 0.20, label = false),
  "Quadrupole" => LayoutShape(shape = :xbox,          color = :magenta, size = 0.37),
  "Sextupole"  => LayoutShape(shape = :xbox,          color = :green,   size = 0.37, label = false),
  "Octupole"   => LayoutShape(shape = :box,           color = :black,   size = 0.30, label = false),
  "Multipole"  => LayoutShape(shape = :box,           color = :black,   size = 0.30),
  "Solenoid"   => LayoutShape(shape = :box,           color = :blue,    size = 0.30),
  "Kicker"     => LayoutShape(shape = :up_triangle,   color = :red,     size = 0.40),
  "HKicker"    => LayoutShape(shape = :down_triangle, color = :red,     size = 0.40),
  "VKicker"    => LayoutShape(shape = :up_triangle,   color = :orange,  size = 0.40),
  "RFCavity"   => LayoutShape(shape = :xbox,          color = :red,     size = 0.50),
  "CrabCavity" => LayoutShape(shape = :xbox,          color = :purple,  size = 0.50),
  "BPM"        => LayoutShape(shape = :box,           color = :black,   size = 0.30, draw = false),
  "Marker"     => LayoutShape(shape = :box,           color = :blue,    size = 0.30, draw = false),
  "Patch"      => LayoutShape(shape = :box,           color = :gold,    size = 0.25, draw = false),
)

"""
    LayoutElement

One element to be drawn in a lattice layout. Produced by `lat_layout_shapes`.

## Fields
- `s_start`, `s_end`: Longitudinal positions of the entrance and exit of the element [m].
- `y_bottom`, `y_top`: Vertical extent of the shape. Normally symmetric about `y = 0`.
- `name`, `kind`: Name and kind of the element.
- `shape`: The `LayoutShape` used.
- `ele`: The `LineElement` itself.
"""
struct LayoutElement
  s_start::Float64
  s_end::Float64
  y_bottom::Float64
  y_top::Float64
  name::String
  kind::String
  shape::LayoutShape
  ele::LineElement
end

function Base.show(io::IO, le::LayoutElement)
  print(io, "LayoutElement($(repr(le.name)), $(le.kind), s = [$(le.s_start), $(le.s_end)], ",
            "y = [$(le.y_bottom), $(le.y_top)], $(repr(le.shape.shape)))")
end

#---------------------------------------------------------------------------------------------------

_layout_elements(bl::Beamline) = bl.line
_layout_elements(br::Branch) = reduce(vcat, (bl.line for bl in br.beamlines); init = LineElement[])
_layout_elements(lat::Lattice; branch = 1) = _layout_elements(lat.branches[branch])
_layout_elements(eles::AbstractVector{<:LineElement}) = eles

# Strength used to decide which side of the center line an element goes when `polarity = true`.
const _POLARITY_STRENGTH = Dict("Quadrupole" => :Kn1, "Sextupole" => :Kn2, "Octupole" => :Kn3)

function _polarity_strength(ele::LineElement)
  key = get(_POLARITY_STRENGTH, ele.kind, nothing)
  isnothing(key) && return 0.0
  try
    return Float64(scalarize(getproperty(ele, key)))
  catch
    return 0.0
  end
end

# Value of the parameter that sets the height of a `:var_box`.
function _height_param_value(ele::LineElement, param)
  isnothing(param) && error("A :var_box LayoutShape needs a `height_param` (e.g. `height_param = :Kn1`). ",
                            "Element: $(repr(ele.name)) ($(ele.kind)).")
  v = param isa Symbol ? getproperty(ele, param) : param(ele)
  return Float64(scalarize(v))
end

"""
    lat_layout_shapes(line; shapes = Dict(), polarity = false, branch = 1) -> Vector{LayoutElement}

Compute what is to be drawn in a lattice layout plot of `line`, which may be a `Beamline`,
`Branch`, `Lattice` (in which case branch `branch` is used), or a vector of `LineElement`s
that are in a `Beamline`. This function does not use Makie and is used by `lat_layout!`.

## Keyword arguments
- `shapes`:   `Dict` of `String => LayoutShape` overriding `DEFAULT_LAYOUT_SHAPES`. A key may
  be an element `kind` (e.g. `"Quadrupole"`) or an element `name` (e.g. `"QF"`). Element names
  take precedence over kinds.
- `polarity`: If `true`, quadrupoles, sextupoles and octupoles are drawn only above the
  center line if their normal strength (`Kn1`, `Kn2`, `Kn3`) is positive and only below if
  negative. For a quadrupole positive means horizontally focusing. Does not affect `:var_box` 
  shapes, which are always on the side given by the sign of their parameter.
"""
function lat_layout_shapes(line; shapes = Dict{String,LayoutShape}(), polarity::Bool = false, branch = 1)
  eles = line isa Lattice ? _layout_elements(line; branch = branch) : _layout_elements(line)
  out = LayoutElement[]
  for ele in eles
    name = ele.name
    kind = ele.kind
    ls = get(shapes, name, nothing)
    isnothing(ls) && (ls = get(shapes, kind, nothing))
    isnothing(ls) && (ls = get(DEFAULT_LAYOUT_SHAPES, kind, nothing))
    (isnothing(ls) || !ls.draw) && continue

    s0 = Float64(scalarize(ele.s))
    s1 = s0 + Float64(scalarize(ele.L))
    y_bottom, y_top = -ls.size, ls.size
    if ls.shape === :var_box
      y_bottom, y_top = minmax(0.0, ls.size * _height_param_value(ele, ls.height_param))
    elseif polarity
      k = _polarity_strength(ele)
      if k > 0
        y_bottom = 0.0
      elseif k < 0
        y_top = 0.0
      end
    end
    push!(out, LayoutElement(s0, s1, y_bottom, y_top, name, kind, ls, ele))
  end
  return out
end

#---------------------------------------------------------------------------------------------------
# Shape outlines in a unit square: `x` along `s` and `y` vertical, both in [0, 1]. 
# `fills` are polygons to fill and `strokes` are polylines to draw.

const _UNIT_BOX = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
const _UNIT_ELLIPSE = [(0.5 + 0.5cos(t), 0.5 + 0.5sin(t)) for t in range(0, 2π, length = 49)[1:end-1]]
const _DIAGONALS = [[(0.0, 0.0), (1.0, 1.0)], [(0.0, 1.0), (1.0, 0.0)]]

_closed(poly) = [poly; [first(poly)]]
_filled_outline(polys...) = (fills = collect(polys), strokes = [_closed(p) for p in polys])

"""
    _unit_outline(shape) -> (fills, strokes)

Outline of `shape` (see `LayoutShape`) in the unit square.
"""
function _unit_outline(shape::Symbol)
  if shape in (:box, :var_box)
    return _filled_outline(_UNIT_BOX)
  elseif shape == :xbox
    return (fills = [_UNIT_BOX], strokes = [[_closed(_UNIT_BOX)]; _DIAGONALS])
  elseif shape == :x
    return (fills = typeof(_UNIT_BOX)[], strokes = _DIAGONALS)
  elseif shape in (:circle, :oval)
    return _filled_outline(_UNIT_ELLIPSE)
  elseif shape == :diamond
    return _filled_outline([(0.0, 0.5), (0.5, 0.0), (1.0, 0.5), (0.5, 1.0)])
  elseif shape == :bowtie
    return _filled_outline([(0.0, 0.0), (0.5, 0.5), (0.0, 1.0)], [(1.0, 0.0), (0.5, 0.5), (1.0, 1.0)])
  elseif shape == :vertical_bowtie
    return _filled_outline([(0.0, 1.0), (1.0, 1.0), (0.5, 0.5)], [(0.0, 0.0), (1.0, 0.0), (0.5, 0.5)])
  elseif shape == :vertical_bar
    return (fills = typeof(_UNIT_BOX)[], strokes = [[(0.5, 0.0), (0.5, 1.0)]])
  elseif shape == :up_triangle
    return _filled_outline([(0.0, 0.0), (1.0, 0.0), (0.5, 1.0)])
  elseif shape == :down_triangle
    return _filled_outline([(0.0, 1.0), (1.0, 1.0), (0.5, 0.0)])
  elseif shape == :right_triangle
    return _filled_outline([(0.0, 0.0), (1.0, 0.5), (0.0, 1.0)])
  elseif shape == :left_triangle
    return _filled_outline([(1.0, 0.0), (0.0, 0.5), (1.0, 1.0)])
  elseif shape == :star_5
    return _filled_outline(_unit_star(5, (3 - sqrt(5)) / 2))   # Regular pentagram
  elseif shape == :star_6
    return _filled_outline(_unit_star(6, 1 / sqrt(3)))         # Regular hexagram
  else
    error("Unknown lattice layout shape: :$shape. See `LayoutShape` for the allowed shapes.")
  end
end

# Star with `n` points, one pointing up, and inner to outer radius ratio `ratio`. It is scaled 
# to fit in, and centered in, the unit square keeping its proportions.
function _unit_star(n, ratio)
  radius(k) = iseven(k) ? 1.0 : ratio   # Alternate outer and inner vertices
  pts = [(radius(k) * cos(π/2 + k * π / n), radius(k) * sin(π/2 + k * π / n)) for k in 0:2n-1]
  xmin, xmax = extrema(first.(pts))
  ymin, ymax = extrema(last.(pts))
  scale = 1 / max(xmax - xmin, ymax - ymin)
  xc, yc = (xmin + xmax) / 2, (ymin + ymax) / 2
  return [(0.5 + (x - xc) * scale, 0.5 + (y - yc) * scale) for (x, y) in pts]
end

# Custom polygon given as a vector of points.
function _unit_outline(points::AbstractVector)
  poly = [(Float64(p[1]), Float64(p[2])) for p in points]
  length(poly) < 2 && error("A custom lattice layout shape must have at least two points.")
  return _filled_outline(_normalize_to_unit_square([poly])...)
end

# Scale a set of polygons together so that their bounding box is the unit square. 
# A dimension with zero extent is centered.
function _normalize_to_unit_square(polys)
  xs = [p[1] for poly in polys for p in poly]
  ys = [p[2] for poly in polys for p in poly]
  xmin, xmax = extrema(xs)
  ymin, ymax = extrema(ys)
  nx(x) = xmax > xmin ? (x - xmin) / (xmax - xmin) : 0.5
  ny(y) = ymax > ymin ? (y - ymin) / (ymax - ymin) : 0.5
  return [[(nx(p[1]), ny(p[2])) for p in poly] for poly in polys]
end

# Shapes that keep their on-screen aspect ratio (unit square drawn as a square) independent of 
# element length.
_keeps_aspect(le::LayoutElement) = le.s_end == le.s_start || le.shape.shape in (:circle, :star_5, :star_6)
