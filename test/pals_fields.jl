@testset "Solenoids" begin
    elements = [
        Solenoid(name="normalized", L=0.5, Ksol=0.2),
        Solenoid(name="field", L=0.5, Bsol=0.3),
        Solenoid(name="integrated_normalized", L=0.5, KsolL=0.4),
        Solenoid(name="integrated_field", L=0.5, BsolL=0.6),
        Solenoid(name="mixed", L=0.5, Ksol=0.2, Kn1=0.3, Ks2L=0.4),
        Solenoid(name="zero_thin", KsolL=0.0),
        Solenoid(name="ignored_sol", L=0.5, Ksol=0.2, ignore_params=[BMultipoleParams]),
        Solenoid(name="ignored_mixed", L=0.5, Ksol=0.2, Kn1=0.3, ignore_params=[BMultipoleParams]),
    ]
    bl = Beamline(elements, species_ref=Species("electron"), pc_ref=1e9)
    pals = to_pals(bl)
    for (name, key, value) in [("normalized", "Ksol", 0.2), ("field", "Bsol", 0.3),
                               ("integrated_normalized", "Ksol", 0.8), ("integrated_field", "Bsol", 1.2)]
        entry = facility_entry(pals, name)
        @test entry["SolenoidP"] == OrderedDict(key => value)
        @test !haskey(entry, "MagneticMultipoleP")
    end
    mixed = facility_entry(pals, "mixed")
    @test mixed["SolenoidP"] == OrderedDict("Ksol" => 0.2)
    @test mixed["MagneticMultipoleP"] == OrderedDict("Kn1" => 0.3, "Ks2L" => 0.4)
    @test !haskey(facility_entry(pals, "zero_thin"), "SolenoidP")
    @test facility_entry(pals, "ignored_sol")["SciBmad_ignore_params"] == ["SolenoidP"]
    @test facility_entry(pals, "ignored_mixed")["SciBmad_ignore_params"] == ["MagneticMultipoleP", "SolenoidP"]
    @test_throws "nonzero integrated solenoid at zero length" to_pals(Beamline([Solenoid(KsolL=0.2)]))
    @test_throws "nonzero integrated solenoid at zero length" to_pals(Beamline([Solenoid(BsolL=0.2)]))

    # All deferred strengths and lengths must be resolved in the lattice context.
    deferred = Solenoid(name="deferred", L=DefExpr(c -> c.len), KsolL=DefExpr(c -> c.strength))
    lat = Lattice([Beamline([deferred])], context=Context(len=0.25, strength=0.5))
    @test facility_entry(to_pals(lat), "deferred")["SolenoidP"]["Ksol"] == 2.0

    mktempdir() do dir
        file = joinpath(dir, "solenoids.pals.yaml")
        write_pals(file, bl)
        @test YAML.load_file(file; dicttype=OrderedDict{String,Any}) == pals
    end
end

@testset "Field-bearing drifts" begin
    bl = Beamline([
        Drift(name="plain", L=0.2),
        Drift(name="magnetic", L=0.2, Kn1=0.3, Ks2L=0.4),
        Drift(name="electric", L=0.3, En0=1e4, Es2L=2e3, etilt2=0.1),
        Drift(name="solenoidal", L=0.5, BsolL=0.6),
        Drift(name="combined", L=0.4, Ksol=0.2, Kn1=0.3, En1=1e3),
        Drift(name="zero_field", L=0.2, Kn1=0.0),
        Drift(name="thin", Kn1L=0.2),
    ], species_ref=Species("proton"), pc_ref=1e9)
    pals = to_pals(bl)
    @test facility_entry(pals, "plain")["kind"] == "Drift"
    @test facility_entry(pals, "zero_field")["kind"] == "Drift"
    for (name, kind, length) in [("magnetic", "Multipole", 0.2), ("electric", "Multipole", 0.3),
                                 ("solenoidal", "Solenoid", 0.5), ("combined", "Solenoid", 0.4)]
        entry = facility_entry(pals, name)
        @test entry["kind"] == kind
        @test entry["length"] == length
    end
    @test facility_entry(pals, "magnetic")["MagneticMultipoleP"] == OrderedDict("Kn1" => 0.3, "Ks2L" => 0.4)
    @test facility_entry(pals, "electric")["ElectricMultipoleP"] == OrderedDict("En0" => 1e4, "Es2L" => 2e3, "tilt2" => 0.1)
    @test facility_entry(pals, "solenoidal")["SolenoidP"] == OrderedDict("Bsol" => 1.2)
    @test facility_entry(pals, "solenoidal")["TrackingP"]["SciBmad"]["tracking_method"] == "DriftKick"
    @test facility_entry(pals, "combined")["MagneticMultipoleP"]["Kn1"] == 0.3
    @test facility_entry(pals, "combined")["ElectricMultipoleP"]["En1"] == 1e3
    @test facility_entry(pals, "thin")["kind"] == "Multipole"
    @test !haskey(facility_entry(pals, "thin"), "length")
    # Exporting must not change the source kind or strengths.
    @test bl.line[2].kind == "Drift"
    @test bl.line[4].BsolL == 0.6
end

@testset "Beamlines 0.14 API and tracking methods" begin
    bl = Beamline([
        Quadrupole(name="default", L=0.2, Kn1=0.3),
        Quadrupole(name="custom", L=0.2, Kn1=0.3, tracking_method=MatrixKick(order=6)),
        Marker(name="marker"),
        LatElement(name="untyped", L=0.2),
    ])
    pals = to_pals(bl)
    @test bl.line[1] isa LatElement
    @test !haskey(facility_entry(pals, "default"), "TrackingP")
    @test !haskey(facility_entry(pals, "marker"), "TrackingP")
    @test !haskey(facility_entry(pals, "untyped"), "TrackingP")
    @test facility_entry(pals, "custom")["TrackingP"]["SciBmad"] ==
        OrderedDict("tracking_method" => "MatrixKick", "order" => 6, "opt_scheme" => true)
    @test lat_layout_shapes(bl)[1].ele isa LatElement
end
