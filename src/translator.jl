#= Translation of SciBmad lattices, branches and beamlines to PALS. =#

"""
    Internal: PALSTranslation

State of a translation to PALS.

## Fields
- `context`  -- `Context` used to evaluate `DefExpr`s.
- `names`    -- Names in use in the PALS `facility`. Names must be unique.
- `unnamed`  -- Names generated for elements without a name, keyed by the parameter dictionary
                of the element they all inherit from.
- `elements` -- Element definitions written at the start of the `facility`, keyed by name.
"""
struct PALSTranslation
    context::Context
    names::Set{String}
    unnamed::IdDict{ParamDict,String}
    elements::OrderedDict{String,OrderedDict{String,Any}}
end

PALSTranslation(context::Context) =
    PALSTranslation(context, Set{String}(), IdDict{ParamDict,String}(), OrderedDict{String,OrderedDict{String,Any}}())

"""
    Internal: unique_name!(tr::PALSTranslation, name::String) -> String

Returns `name`, with a suffix `_<N>` added if needed to make it unique, and marks it as used.
"""
function unique_name!(tr::PALSTranslation, name::String)
    new_name = name
    n = 0
    while new_name in tr.names
        n += 1
        new_name = "$(name)_$n"
    end
    push!(tr.names, new_name)
    return new_name
end

"""
    Internal: reserve_element_names!(tr::PALSTranslation, beamlines)

Marks the PALS names of all named elements in `beamlines` as used. This is done first so
that names generated for unnamed elements, branches, etc. never clash with element names.
"""
function reserve_element_names!(tr::PALSTranslation, beamlines)
    for bl in beamlines, ele in bl.line
        name = ele.name
        isempty(name) || push!(tr.names, pals_name(name))
    end
end

"""
    Internal: element_name!(tr::PALSTranslation, ele::LatElement, kind::String) -> String

Returns the PALS name of `ele`. Unnamed elements are given a name generated from the PALS
`kind`. Unnamed elements that are copies of the same element share a name.
"""
function element_name!(tr::PALSTranslation, ele::LatElement, kind::String)
    name = ele.name
    isempty(name) || return pals_name(name)

    # Find the element that `ele` is a copy of
    pdict = getfield(ele, :pdict)
    while haskey(pdict, InheritParams)
        pdict = getfield(pdict[InheritParams].parent, :pdict)
    end
    return get!(() -> unique_name!(tr, lowercase(kind)), tr.unnamed, pdict)
end

"""
    Internal: dict_diff(base::AbstractDict, new::AbstractDict) -> OrderedDict

Returns the entries of `new` that differ from `base`. Parameters in `base` that are not in
`new` are returned with value `nothing` which is written as `null` (not set) in PALS.
"""
function dict_diff(base::AbstractDict, new::AbstractDict)
    acc = OrderedDict{String,Any}()
    for (k, v) in new
        if !haskey(base, k)
            acc[k] = v
        elseif base[k] != v
            acc[k] = (base[k] isa AbstractDict && v isa AbstractDict) ? dict_diff(base[k], v) : v
        end
    end
    for (k, v) in base
        haskey(new, k) && continue
        # For a parameter group, unset each of its parameters
        acc[k] = v isa AbstractDict ? dict_diff(v, Dict()) : nothing
    end
    return acc
end

"""
    Internal: element_item!(tr::PALSTranslation, ele::LatElement)

Returns the PALS `line` item for `ele`. The first element with a given name is added to
`tr.elements` and the item is just the name. Later elements with the same name but
different parameters are written in the line with only the parameters that differ from
the first, which PALS allows for an item that refers to an element defined elsewhere.
"""
function element_item!(tr::PALSTranslation, ele::LatElement)
    info = element_to_pals(ele, tr.context)
    name = element_name!(tr, ele, info["kind"])
    base = get(tr.elements, name, nothing)
    if isnothing(base)
        tr.elements[name] = info
        return name
    end
    base == info && return name
    return OrderedDict{String,Any}(name => dict_diff(base, info))
end

"""
    Internal: beamline_reference(bl::Beamline, first::Bool, context::Context) -> OrderedDict

Returns the reference parameters set by the `Beamline` `bl`: a `ReferenceP` group for the
`BeginningEle` of a branch if `first` is `true`, and otherwise a `ReferenceChangeP` group.
Reference energies given as a magnetic rigidity, or a change at the start of a branch, are
written as the reference momentum computed by Beamlines.
"""
function beamline_reference(bl::Beamline, first::Bool, context::Context)
    acc = OrderedDict{String,Any}()
    isempty(bl.line) && return acc
    pdict = flattened_pdict(bl.line[1])
    haskey(pdict, InitialBeamlineParams) || return acc
    # getproperty of InitialBeamlineParams errors for unset values, so use getfield
    ibp = pdict[InitialBeamlineParams]
    species = getfield(ibp, :species_ref)
    if species != Species()
        acc["species_ref"] = String(nameof(species))
    end

    ref = deval(getfield(ibp, :ref), context)
    isnothing(ref) && return acc
    meaning = getfield(ibp, :ref_meaning)
    if meaning == RefMeaning.E_ref
        acc["E_tot_ref"] = pals_value(ref)
    elseif meaning == RefMeaning.pc_ref
        acc["pc_ref"] = pals_value(ref)
    elseif meaning == RefMeaning.dE_ref
        first ? (acc["E_tot_ref"] = pals_value(bl.E_ref)) : (acc["dE_ref"] = pals_value(ref))
    elseif meaning == RefMeaning.dpc_ref
        first ? (acc["pc_ref"] = pals_value(bl.pc_ref)) : (acc["dpc_ref"] = pals_value(ref))
    else    # p_over_q_ref or dp_over_q_ref
        acc["pc_ref"] = pals_value(bl.pc_ref)
    end
    return acc
end

"""
    Internal: branch_to_pals!(tr::PALSTranslation, name::String, beamlines) -> OrderedDict

Returns the PALS `BeamLine` named `name` holding all the elements of `beamlines`. The line
starts with a `BeginningEle` holding the reference parameters of the first `Beamline`,
and a `ReferenceChange` element is placed at the start of every following `Beamline` that
sets reference parameters.
"""
function branch_to_pals!(tr::PALSTranslation, name::String, beamlines)
    line = Any[]
    for (i, bl) in enumerate(beamlines)
        ref = beamline_reference(bl, i == 1, tr.context)
        if i == 1
            ele_name = unique_name!(tr, "$(name)_begin")
            tr.elements[ele_name] = OrderedDict{String,Any}("kind" => "BeginningEle")
            isempty(ref) || (tr.elements[ele_name]["ReferenceP"] = ref)
            push!(line, ele_name)
        elseif !isempty(ref)
            ele_name = unique_name!(tr, "$(name)_ref_change")
            tr.elements[ele_name] = OrderedDict{String,Any}("kind" => "ReferenceChange", "ReferenceChangeP" => ref)
            push!(line, ele_name)
        end
        for ele in bl.line
            push!(line, element_item!(tr, ele))
        end
    end
    return OrderedDict{String,Any}(name => OrderedDict{String,Any}("kind" => "BeamLine", "line" => line))
end

"""
    Internal: uses_extensions(x) -> Bool

Returns `true` if any dictionary key in the PALS tree `x` is a SciBmad extension, that is,
starts with `SciBmad_`.
"""
uses_extensions(x) = false
uses_extensions(x::AbstractVector) = any(uses_extensions, x)
uses_extensions(x::AbstractDict) =
    any(((k, v),) -> startswith(String(k), "SciBmad_") || uses_extensions(v), x)

"""
    Internal: lattice_to_pals!(tr, lattice_name, branch_names, branch_beamlines) -> OrderedDict

Returns the PALS tree for a lattice named `lattice_name` with branches named `branch_names`
whose `Beamline`s are `branch_beamlines`. Names must be made unique with `unique_name!`.
"""
function lattice_to_pals!(tr::PALSTranslation, lattice_name, branch_names, branch_beamlines)
    lines = [branch_to_pals!(tr, n, bls) for (n, bls) in zip(branch_names, branch_beamlines)]

    facility = Any[]
    for (name, info) in tr.elements
        push!(facility, OrderedDict{String,Any}(name => info))
    end
    append!(facility, lines)
    push!(facility, OrderedDict{String,Any}(lattice_name => OrderedDict{String,Any}(
        "kind" => "Lattice",
        "branches" => collect(String, branch_names),
    )))

    pals = OrderedDict{String,Any}("version" => nothing)
    if uses_extensions(facility)
        pals["extension_labels"] = OrderedDict{String,Any}(
            "prefixes" => OrderedDict{String,Any}("SciBmad_" => "Prefix for the SciBmad ecosystem."),
        )
    end
    pals["facility"] = facility
    return OrderedDict{String,Any}("PALS" => pals)
end

"""
    to_pals(lattice::Lattice) -> OrderedDict
    to_pals(branch::Branch; lattice_name = "lattice") -> OrderedDict
    to_pals(beamline::Beamline; name = "beamline", lattice_name = "lattice") -> OrderedDict

Translates a SciBmad `Lattice`, `Branch` or `Beamline` to a PALS tree, a nested dictionary
that can be written to a YAML file (see `write_pals`).

Each branch becomes a PALS `BeamLine` that starts with a `BeginningEle` holding the
reference species and energy. Unnamed branches and lattices are given default names.
All `DefExpr`s are evaluated using the `Context` of the lattice. Parameter groups with no
PALS equivalent are written as extensions with names starting with `SciBmad_`.

## Example
```julia
qf = Quadrupole(name="qf", L=0.5, Kn1=0.36)
d = Drift(name="d", L=1)
fodo = Beamline([qf, d], species_ref=Species("electron"), E_ref=18e9)
pals = to_pals(Lattice([fodo], name="fodo_lattice"))
```
"""
function to_pals(lattice::Lattice)
    tr = PALSTranslation(lattice.context)
    branches = lattice.branches
    reserve_element_names!(tr, (bl for br in branches for bl in br.beamlines))
    lattice_name = unique_name!(tr, isempty(lattice.name) ? "lattice" : pals_name(lattice.name))
    branch_names = [unique_name!(tr, isempty(br.name) ? "b$i" : pals_name(br.name)) for (i, br) in enumerate(branches)]
    return lattice_to_pals!(tr, lattice_name, branch_names, [br.beamlines for br in branches])
end

function to_pals(branch::Branch; lattice_name::AbstractString = "lattice")
    tr = PALSTranslation(branch.context)
    reserve_element_names!(tr, branch.beamlines)
    lattice_name = unique_name!(tr, pals_name(lattice_name))
    branch_name = unique_name!(tr, isempty(branch.name) ? "branch" : pals_name(branch.name))
    return lattice_to_pals!(tr, lattice_name, [branch_name], [branch.beamlines])
end

function to_pals(beamline::Beamline; name::AbstractString = "beamline", lattice_name::AbstractString = "lattice")
    tr = PALSTranslation(beamline.context)
    reserve_element_names!(tr, (beamline,))
    lattice_name = unique_name!(tr, pals_name(lattice_name))
    branch_name = unique_name!(tr, pals_name(name))
    return lattice_to_pals!(tr, lattice_name, [branch_name], [[beamline]])
end

"""
    write_pals(filename::AbstractString, x::Union{Lattice,Branch,Beamline}; kwargs...)

Writes the SciBmad `Lattice`, `Branch` or `Beamline` `x` to the PALS YAML file `filename`.
PALS files conventionally have the extension `.pals.yaml`. Keyword arguments are passed to
`to_pals`.

Strings are written without quotation marks where that is unambiguous, and BeamLine
`line`s and other lists of names are written in the concise flow form `[a, b, c]`.
"""
function write_pals(filename::AbstractString, x::Union{Lattice,Branch,Beamline}; kwargs...)
    open(io -> write_yaml(io, to_pals(x; kwargs...)), filename, "w")
    return
end
