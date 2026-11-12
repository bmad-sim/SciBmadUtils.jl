"""
    SciBmadUtils

Simulation utilities for the SciBmad ecosystem:
- The translator from SciBmad lattices to the PALS lattice standard: see `to_pals` and `write_pals`.
- Lattice layout plots: see `lat_layout`, `lat_layout!` and `lat_layout_shapes`. Drawing needs
  a Makie backend (e.g. CairoMakie or GLMakie) to be loaded.
"""
module SciBmadUtils

using Beamlines
using Beamlines: BMULTIPOLE_STRENGTH_INVERSE_MAP, BMULTIPOLE_TILT_INVERSE_MAP,
                 EMULTIPOLE_STRENGTH_INVERSE_MAP, EMULTIPOLE_TILT_INVERSE_MAP, Context, ParamDict, RefMeaning,
                 deval, flattened_pdict
using Beamlines: scalarize
using OrderedCollections

export to_pals, write_pals
export LayoutShape, LayoutElement, DEFAULT_LAYOUT_SHAPES, lat_layout_shapes, lat_layout, lat_layout!

# SciBmad -> PALS translator
include("translator-support.jl")
include("translator-parameter-handling.jl")
include("translator.jl")
include("yaml.jl")

# Lattice layout plots. The drawing is in the Makie extension.
include("layout_shapes.jl")
include("lat_layout.jl")

end
