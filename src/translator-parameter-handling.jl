#= Translation of SciBmad parameter groups to PALS parameter groups. =#

"""
    Internal: pals_group(group::AbstractParams) -> OrderedDict

Returns the PALS parameter group corresponding to the SciBmad parameter group `group`,
whose `DefExpr`s must already be evaluated. Parameters with default values are left out
so the returned dictionary may be empty.

This method handles groups whose parameters translate one-to-one: the PALS name of each
parameter is looked up in `SCIBMAD_NAME_TO_PALS_NAME`.
"""
function pals_group(group::T) where {T<:Union{AlignmentParams,PatchParams,BendParams,MetaParams}}
    names = SCIBMAD_NAME_TO_PALS_NAME[Base.typename(T).wrapper]
    acc = OrderedDict{String,Any}()
    for name in fieldnames(T)
        value = getfield(group, name)
        isdefault(value) && continue
        acc[get(names, name, String(name))] = pals_value(value)
    end
    return acc
end

function pals_group(aperture::ApertureParams)
    acc = OrderedDict{String,Any}()
    limits = (
        (aperture.x1_limit, "x_min"),
        (aperture.x2_limit, "x_max"),
        (aperture.y1_limit, "y_min"),
        (aperture.y2_limit, "y_max"),
    )
    for (value, name) in limits
        isfinite(value) && (acc[name] = pals_value(value))
    end

    # With no finite limits there is no aperture
    isempty(acc) && return acc

    shape = APERTURE_SHAPE_TO_PALS[aperture.aperture_shape]
    isnothing(shape) || (acc["shape"] = shape)

    location = APERTURE_AT_TO_PALS[aperture.aperture_at]
    isnothing(location) || (acc["location"] = location)

    # The PALS default is false but the SciBmad default is true
    aperture.aperture_shifts_with_body && (acc["aperture_shifts_with_body"] = true)
    return acc
end

function pals_group(rf::RFParams)
    acc = OrderedDict{String,Any}()
    if rf.rate_meaning != RateMeaning.Indeterminate
        acc[RATE_MEANING_TO_PALS[rf.rate_meaning]] = pals_value(rf.rate)
    end
    isdefault(rf.voltage) || (acc["voltage"] = pals_value(rf.voltage))
    isdefault(rf.phi0) || (acc["phase"] = pals_value(rf.phi0))   # Both in radians

    zero_phase = PHASE_REF_TO_PALS[rf.zero_phase]
    isnothing(zero_phase) || (acc["zero_phase"] = zero_phase)

    rf.traveling_wave && (acc["cavity_type"] = "TRAVELING_WAVE")
    return acc
end

function pals_group(group::BMultipoleParams)
    acc = OrderedDict{String,Any}()
    for bm in group
        bm.order == 0 && continue # Solenoidal order belongs in SolenoidP.
        if !isdefault(bm.n)
            key = BMULTIPOLE_STRENGTH_INVERSE_MAP[(true, bm.order, bm.normalized, bm.integrated)]
            acc[String(key)] = pals_value(bm.n)
        end
        if !isdefault(bm.s)
            key = BMULTIPOLE_STRENGTH_INVERSE_MAP[(false, bm.order, bm.normalized, bm.integrated)]
            acc[String(key)] = pals_value(bm.s)
        end
        if !isdefault(bm.tilt)
            acc[String(BMULTIPOLE_TILT_INVERSE_MAP[bm.order])] = pals_value(bm.tilt)
        end
    end
    return acc
end

"""
    Internal: pals_solenoid(group::BMultipoleParams, length) -> OrderedDict

PALS stores solenoids separately and has no integrated solenoid parameter.
Convert the independently stored strength to Ksol or Bsol using the element length.
"""
function pals_solenoid(group::BMultipoleParams, length)
    acc = OrderedDict{String,Any}()
    for bm in group
        bm.order == 0 || continue
        iszero(bm.s) && iszero(bm.tilt) ||
            error("PALS cannot represent a skew or tilted solenoidal multipole")
        strength = bm.n
        if bm.integrated
            if iszero(length)
                iszero(strength) || error("PALS cannot represent a nonzero integrated solenoid at zero length")
            else
                strength /= length
            end
        end
        isdefault(strength) || (acc[bm.normalized ? "Ksol" : "Bsol"] = pals_value(strength))
    end
    return acc
end

# Beamlines 0.14 assigns tracking methods in its element constructors rather than
# using SciBmadStandard(). Compare against the exported kind so a remapped drift retains a different
# source tracking method (for example DriftKick on a PALS Solenoid).
function default_tracking_method(kind::String, length)
    iszero(length) && return Exact()
    if kind in ("Solenoid", "RFCavity", "CrabCavity")
        return SolenoidKick()
    elseif kind in ("SBend", "Bend")
        return BendKick()
    elseif kind == "Quadrupole"
        return MatrixKick()
    elseif kind in ("Sextupole", "Octupole", "Multipole", "Drift", "VKicker", "HKicker", "Kicker")
        return DriftKick()
    elseif kind in ("Marker", "BPM", "Patch", "Map")
        return Exact()
    elseif kind == "BeamBeam"
        return Implicit()
    end
    return nothing
end

function pals_group(group::EMultipoleParams)
    acc = OrderedDict{String,Any}()
    for em in group
        if !isdefault(em.n)
            key = EMULTIPOLE_STRENGTH_INVERSE_MAP[(true, em.order, em.integrated)]
            acc[String(key)] = pals_value(em.n)
        end
        if !isdefault(em.s)
            key = EMULTIPOLE_STRENGTH_INVERSE_MAP[(false, em.order, em.integrated)]
            acc[String(key)] = pals_value(em.s)
        end
        if !isdefault(em.etilt)
            # SciBmad etiltN is PALS tiltN in ElectricMultipoleP
            key = String(EMULTIPOLE_TILT_INVERSE_MAP[em.order])
            acc[replace(key, r"^etilt" => "tilt")] = pals_value(em.etilt)
        end
    end
    return acc
end

# Function valued parameter groups cannot be represented in PALS. They are written as
# SciBmad extensions so that their presence is not lost.
function pals_group(group::Union{MapParams,FourPotentialParams,EMFieldParams})
    acc = OrderedDict{String,Any}()
    for name in fieldnames(typeof(group))
        value = getfield(group, name)
        isnothing(value) && continue
        acc[String(name)] = value isa Union{Bool,Real,AbstractString} ? pals_value(value) : repr(value)
    end
    return acc
end

"""
    Internal: pals_tracking(method) -> OrderedDict

Returns the `SciBmad` part of the PALS `TrackingP` group for the tracking method `method`.
"""
function pals_tracking(method)
    acc = OrderedDict{String,Any}("tracking_method" => String(nameof(typeof(method))))
    for name in fieldnames(typeof(method))
        value = getfield(method, name)
        acc[String(name)] = value isa Union{Bool,Real,AbstractString} ? pals_value(value) : repr(value)
    end
    return acc
end

"""
    Internal: element_to_pals(ele::LatElement, context::Context) -> OrderedDict

Returns the PALS definition of the element `ele`, not including its name, with all
`DefExpr`s evaluated in `context`. Inherited parameter groups are included.
`BeamlineParams` and `InitialBeamlineParams` are not part of the definition: the reference
parameters are written by `beamline_reference`.
"""
function element_to_pals(ele::LatElement, context::Context)
    pdict = flattened_pdict(ele)
    info = OrderedDict{String,Any}()

    up = deval(pdict[UniversalParams], context)
    kind = String(up.kind)
    if haskey(pdict, RFParams) && pdict[RFParams].is_crabcavity
        kind = "CrabCavity"
    end
    if isempty(kind)
        # PALS requires a kind
        kind = isdefault(up.L) ? "Marker" : "Drift"
    end
    info["kind"] = get(SCIBMAD_KIND_TO_PALS_KIND, kind, kind)
    isdefault(up.L) || (info["length"] = pals_value(up.L))

    for (T, name) in PARAMS_TO_PALS_GROUP
        haskey(pdict, T) || continue
        group = pals_group(deval(pdict[T], context))
        isempty(group) || (info[name] = group)
    end

    if haskey(pdict, BMultipoleParams)
        solenoid = pals_solenoid(deval(pdict[BMultipoleParams], context), up.L)
        isempty(solenoid) || (info["SolenoidP"] = solenoid)
    end

    # PALS Drift cannot carry fields. A Solenoid may carry other multipoles too.
    if info["kind"] == "Drift"
        if haskey(info, "SolenoidP")
            info["kind"] = "Solenoid"
        elseif haskey(info, "MagneticMultipoleP") || haskey(info, "ElectricMultipoleP")
            info["kind"] = "Multipole"
        end
    end

    # SciBmad bends have no field unless a dipole multipole is set, whereas the PALS
    # default is to compute the dipole field from g_ref.
    if haskey(info, "BendP") && haskey(info["BendP"], "g_ref")
        mm = get(info, "MagneticMultipoleP", Dict())
        if !any(k -> haskey(mm, k), ("Kn0", "Bn0", "Kn0L", "Bn0L"))
            info["BendP"]["Kn0_from_g_ref"] = false
        end
    end

    # The length of a SciBmad patch is set by the user
    if haskey(pdict, PatchParams) || info["kind"] == "Patch"
        get!(info, "PatchP", OrderedDict{String,Any}())["user_sets_length"] = true
    end

    if !isnothing(up.tracking_method) && up.tracking_method != default_tracking_method(info["kind"], up.L)
        info["TrackingP"] = OrderedDict{String,Any}("SciBmad" => pals_tracking(up.tracking_method))
    end

    if haskey(pdict, IgnoreParams)
        ignored = String[]
        for T in pdict[IgnoreParams].ignore_params
            if T == ApertureParams && haskey(info, "ApertureP")
                info["ApertureP"]["aperture_active"] = false
            else
                i = findfirst(p -> p.first == T, PARAMS_TO_PALS_GROUP)
                if T == BMultipoleParams
                    haskey(info, "MagneticMultipoleP") && push!(ignored, "MagneticMultipoleP")
                    haskey(info, "SolenoidP") && push!(ignored, "SolenoidP")
                else
                    push!(ignored, isnothing(i) ? String(nameof(T)) : PARAMS_TO_PALS_GROUP[i].second)
                end
            end
        end
        isempty(ignored) || (info["SciBmad_ignore_params"] = ignored)
    end

    return info
end
