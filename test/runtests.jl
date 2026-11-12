using SciBmadUtils
using Beamlines
using OrderedCollections
using Makie
using YAML
using Test

# Returns the entry named `name` in the facility of the PALS tree `pals`
function facility_entry(pals, name)
    for item in pals["PALS"]["facility"]
        haskey(item, name) && return item[name]
    end
    error("No facility entry named $name")
end

@testset "SciBmadUtils.jl" begin
    @testset "Elements" begin
        a = 0.36
        qf = Quadrupole(name="qf", L=0.5, Kn1=DefExpr(()->a), tilt1=0.1)
        d = Drift(name="d", L=1, x1_limit=-0.02, x2_limit=0.02, aperture_shape=ApertureShape.Rectangular)
        qd = Quadrupole(name="qd", L=0.5, Kn1L=-0.18, x_offset=1e-3, tilt=0.01)
        b = SBend(name="b", L=2.0, g_ref=0.01, e1=0.1, edge1_int=0.05)
        bk = SBend(name="bk", L=2.0, g_ref=0.01, Kn0=0.01)
        p = Patch(name="p", dx=0.1, dz_rot=0.02, dt=1e-9)
        m = Marker(name="m", description="a marker", alias="mm")
        rf = RFCavity(name="rf", L=1, voltage=1e6, rf_frequency=5e8, phi0=0.3, traveling_wave=true)
        crab = CrabCavity(name="crab", L=0.2, voltage=1e5, harmon=10)
        hk = HKicker(name="hk", Kn0=1e-4, ignore_params=[BMultipoleParams])
        el = Multipole(name="el", En1=2.0, etilt1=0.2)
        bl = Beamline([qf, d, qd, b, bk, p, m, rf, crab, hk, el], species_ref=Species("electron"), E_ref=18e9)
        pals = to_pals(bl)

        @test facility_entry(pals, "qf") == OrderedDict(
            "kind" => "Quadrupole", "length" => 0.5,
            "MagneticMultipoleP" => OrderedDict("Kn1" => 0.36, "tilt1" => 0.1),
        )
        # DefExprs are evaluated when translating
        a = 0.5
        @test facility_entry(to_pals(bl), "qf")["MagneticMultipoleP"]["Kn1"] == 0.5

        @test facility_entry(pals, "d")["ApertureP"] == OrderedDict(
            "x_min" => -0.02, "x_max" => 0.02, "shape" => "RECTANGULAR", "aperture_shifts_with_body" => true,
        )
        @test facility_entry(pals, "qd")["BodyShiftP"] == OrderedDict("x_offset" => 1e-3, "z_rot" => 0.01)
        @test facility_entry(pals, "qd")["MagneticMultipoleP"] == OrderedDict("Kn1L" => -0.18)

        @test facility_entry(pals, "b")["kind"] == "Bend"
        @test facility_entry(pals, "b")["BendP"] == OrderedDict(
            "g_ref" => 0.01, "e1" => 0.1, "edge1_int" => 0.05, "Kn0_from_g_ref" => false,
        )
        @test !haskey(facility_entry(pals, "bk")["BendP"], "Kn0_from_g_ref")

        @test facility_entry(pals, "p")["PatchP"] == OrderedDict(
            "SciBmad_dt" => 1e-9, "x_offset" => 0.1, "z_rot" => 0.02, "user_sets_length" => true,
        )
        @test facility_entry(pals, "m")["MetaP"] == OrderedDict("alias" => "mm", "description" => "a marker")
        @test facility_entry(pals, "rf")["RFP"] == OrderedDict(
            "frequency" => 5e8, "voltage" => 1e6, "phase" => 0.3, "cavity_type" => "TRAVELING_WAVE",
        )
        @test facility_entry(pals, "crab")["kind"] == "CrabCavity"
        @test facility_entry(pals, "crab")["RFP"] == OrderedDict("harmon" => 10, "voltage" => 1e5)
        @test facility_entry(pals, "hk")["kind"] == "Kicker"
        @test facility_entry(pals, "hk")["SciBmad_ignore_params"] == ["MagneticMultipoleP"]
        @test facility_entry(pals, "el")["ElectricMultipoleP"] == OrderedDict("En1" => 2.0, "tilt1" => 0.2)

        # SciBmad extensions are declared
        @test haskey(pals["PALS"]["extension_labels"]["prefixes"], "SciBmad_")
    end

    @testset "Lattice structure" begin
        d = Drift(name="d", L=1)
        u = Drift(L=0.3)
        q = Quadrupole(name="q.1", L=0.5, Kn1=0.3)
        bl1 = Beamline([d, u, q, u, Drift(L=0.4), Drift(name="d", L=2)], species_ref=Species("proton"), pc_ref=1e9)
        bl2 = Beamline([d, q], dE_ref=1e6)
        lat = Lattice([Branch([bl1, bl2], name="ring")], name="my_lattice")
        pals = to_pals(lat)
        facility = pals["PALS"]["facility"]

        @test pals["PALS"]["version"] === nothing
        @test !haskey(pals["PALS"], "extension_labels")
        @test facility_entry(pals, "ring_begin") == OrderedDict(
            "kind" => "BeginningEle",
            "ReferenceP" => OrderedDict("species_ref" => "proton", "pc_ref" => 1e9),
        )
        @test facility_entry(pals, "ring_ref_change") == OrderedDict(
            "kind" => "ReferenceChange", "ReferenceChangeP" => OrderedDict("dE_ref" => 1e6),
        )
        # Invalid characters are replaced, unnamed elements are given names, copies of
        # the same unnamed element share a name, and a later element with the same name
        # but different parameters only gives what differs.
        @test facility_entry(pals, "ring")["line"] == [
            "ring_begin", "d", "drift", "q_1", "drift", "drift_1",
            OrderedDict("d" => OrderedDict("length" => 2)),
            "ring_ref_change", "d", "q_1",
        ]
        @test facility_entry(pals, "my_lattice") == OrderedDict("kind" => "Lattice", "branches" => ["ring"])
        # Elements are defined first, then the BeamLines, then the Lattice
        @test first(keys(last(facility))) == "my_lattice"

        # Parameter groups missing from a later element with the same name are unset
        d2 = Drift(name="d", L=1)
        bl = Beamline([Drift(name="d", L=1, x_offset=0.1), d2])
        line = facility_entry(to_pals(bl; name="line"), "line")["line"]
        @test line[3] == OrderedDict("d" => OrderedDict("BodyShiftP" => OrderedDict("x_offset" => nothing)))

        # Branch names that clash with element names are made unique
        bl = Beamline([Drift(name="b1", L=1)])
        @test to_pals(Lattice([bl]))["PALS"]["facility"][end]["lattice"]["branches"] == ["b1_1"]
    end

    @testset "write_pals" begin
        bl = Beamline([Drift(name="d", L=1), Quadrupole(name="q", L=0.5, Kn1=0.3)],
                      species_ref=Species("electron"), E_ref=1e9)
        lat = Lattice([bl], name="lat")
        mktempdir() do dir
            file = joinpath(dir, "lat.pals.yaml")
            write_pals(file, lat)
            @test read(file, String) == """
                PALS:
                  version: null
                  facility:
                    - b1_begin:
                        kind: BeginningEle
                        ReferenceP:
                          species_ref: electron
                          E_tot_ref: 1.0e9
                    - d:
                        kind: Drift
                        length: 1
                    - q:
                        kind: Quadrupole
                        length: 0.5
                        MagneticMultipoleP:
                          Kn1: 0.3
                    - b1:
                        kind: BeamLine
                        line: [b1_begin, d, q]
                    - lat:
                        kind: Lattice
                        branches: [b1]
                """

            # Long lines are continued, inline element overrides are flow mappings,
            # and strings are quoted only when needed. All must read back unchanged.
            d = Drift(name="d", L=1)
            m = Marker(name="m", description="a: \"quoted\" string", label="true", alias="plain text")
            ap = Drift(name="ap", L=1, x1_limit=-0.01, x2_limit=Inf)
            bl = Beamline([fill(d, 40); Drift(name="d", L=2); m; ap; Drift(L=0)])
            write_pals(file, bl)
            text = read(file, String)
            @test YAML.load_file(file; dicttype=OrderedDict{String,Any}) == to_pals(bl)
            @test all(length(l) <= 100 for l in split(text, "\n"))
            @test occursin("{d: {length: 2}}", text)
            @test occursin("description: \"a: \\\"quoted\\\" string\"", text)
            @test occursin("label: \"true\"", text)
            @test occursin("alias: plain text", text)
        end
    end

    @testset "Lattice layout" begin
        @testset "lat_layout_shapes" begin
            qf = Quadrupole(name="QF", L=0.5, Kn1=0.4)
            qd = Quadrupole(name="QD", L=0.5, Kn1=-0.4)
            d  = Drift(L=1.0)
            b  = SBend(name="B", L=2.0, angle=0.1)
            m  = Marker(name="M")
            hk = HKicker(name="HK")
            bl = Beamline([qf, d, b, d, qd, m, hk])
            les = lat_layout_shapes(bl)
            # Drifts and markers are not drawn by default
            @test [le.name for le in les] == ["QF", "B", "QD", "HK"]
            @test [le.s_start for le in les] ≈ [0.0, 1.5, 4.5, 5.0]
            @test [le.s_end for le in les] ≈ [0.5, 3.5, 5.0, 5.0]
            @test les[1].shape == DEFAULT_LAYOUT_SHAPES["Quadrupole"]
            @test les[1].y_bottom == -les[1].y_top == -DEFAULT_LAYOUT_SHAPES["Quadrupole"].size
            @test les[4].shape.shape == :down_triangle

            # polarity puts focusing quads above and defocusing quads below the center line
            lesp = lat_layout_shapes(bl; polarity=true)
            @test lesp[1].y_bottom == 0 && lesp[1].y_top > 0
            @test lesp[3].y_top == 0 && lesp[3].y_bottom < 0
            @test lesp[2].y_bottom == -lesp[2].y_top     # bends unaffected

            # Overrides by kind and by name (name takes precedence)
            shapes = Dict("Marker" => LayoutShape(color=:blue), "QD" => LayoutShape(draw=false),
                          "Quadrupole" => LayoutShape(shape=:box, color=:red))
            leso = lat_layout_shapes(bl; shapes=shapes)
            @test [le.name for le in leso] == ["QF", "B", "M", "HK"]
            @test leso[1].shape.color == :red && leso[1].shape.shape == :box

            # Branch and Lattice
            br = Branch([Beamline([qf, d]), Beamline([b, d, qd])])
            lesb = lat_layout_shapes(br)
            @test [le.s_start for le in lesb] ≈ [0.0, 1.5, 4.5]
            @test [le.name for le in lat_layout_shapes(Lattice([br]))] == ["QF", "B", "QD"]
        end

        @testset "lat_layout" begin
            qf = Quadrupole(name="QF", L=0.5, Kn1=0.4)
            qd = Quadrupole(name="QD", L=0.5, Kn1=-0.4)
            d  = Drift(L=1.0)
            b  = SBend(L=2.0, angle=0.1)
            hk = HKicker(name="HK")
            bl = Beamline([qf, d, b, d, qd, hk])

            fig = Figure()
            ax  = Axis(fig[2, 1])
            lines!(ax, [0.0, 5.0], [1.0, 2.0])
            axl = lat_layout(fig[1, 1], bl; link=ax)
            @test axl isa Axis
            # center line, fills, outlines, zero-length element fill and outline, labels
            @test length(axl.scene.plots) == 6
            @test any(p -> p isa Makie.Text, axl.scene.plots)

            axl2 = lat_layout(fig[3, 1], bl; labels=false, polarity=true)
            @test !any(p -> p isa Makie.Text, axl2.scene.plots)

            ax3 = Axis(fig[4, 1])
            @test lat_layout!(ax3, Branch([bl])) === ax3

            @test_throws ErrorException lat_layout(fig[5, 1], bl; shapes=Dict("SBend" => LayoutShape(shape=:hexagon)))
        end

        @testset "Shapes and colors" begin
            all_shapes = [:box, :xbox, :x, :circle, :oval, :diamond, :bowtie, :vertical_bowtie,
                          :vertical_bar, :up_triangle, :down_triangle, :right_triangle, :left_triangle,
                          :star_5, :star_6, :var_box,
                          [(0, 0), (2, 0), (1, 3)], "M 0 0 L 10 0 C 10 5 5 10 0 10 Z M 20 0 L 30 0 L 25 10 Z"]
            for shape in all_shapes
                o = SciBmadUtils._unit_outline(shape)
                pts = [p for poly in [o.fills; o.strokes] for p in poly]
                @test !isempty(o.strokes)
                @test all(p -> -1e-12 <= p[1] <= 1 + 1e-12 && -1e-12 <= p[2] <= 1 + 1e-12, pts)
            end
            @test isempty(SciBmadUtils._unit_outline(:x).fills)
            @test isempty(SciBmadUtils._unit_outline(:vertical_bar).fills)
            @test length(SciBmadUtils._unit_outline(:bowtie).fills) == 2
            @test length(SciBmadUtils._unit_outline(:star_5).fills[1]) == 10
            @test length(SciBmadUtils._unit_outline(:star_6).fills[1]) == 12
            # The SVG path has two subpaths and SVG y points down: the triangle vertex (25, 10) is at the bottom
            svg = SciBmadUtils._unit_outline("M 0 0 L 10 0 C 10 5 5 10 0 10 Z M 20 0 L 30 0 L 25 10 Z")
            @test length(svg.fills) == 2
            @test (5/6, 0.0) in svg.fills[2]

            # Every shape, on both finite and zero-length elements, with fill and line colors
            eles = [Quadrupole(name="Q$i", L=(isodd(i) ? 0.5 : 0.0)) for i in 1:2length(all_shapes)]
            bl = Beamline(reduce(vcat, [[e, Drift(L=1.0)] for e in eles]))
            shapes = Dict("Q$i" => LayoutShape(shape=all_shapes[cld(i, 2)], fill_color=:yellow, line_color=:blue, height_param=:L)
                          for i in 1:2length(all_shapes))
            fig = Figure(size=(800, 300))
            axl = lat_layout(fig[1, 1], bl; shapes=shapes)
            polys = filter(p -> p isa Poly, axl.scene.plots)
            @test all(p -> all(==(Makie.to_color(:yellow)), p.color[]), polys)
            segs = filter(p -> p isa LineSegments, axl.scene.plots)
            @test all(p -> all(==(Makie.to_color(:blue)), p.color[]), segs)

            # var_box: height set by an element parameter, on the side given by its sign
            qf = Quadrupole(name="QF", L=0.5, Kn1=0.4)
            qd = Quadrupole(name="QD", L=0.5, Kn1=-0.2)
            sx = Sextupole(name="SX", L=0.2, Kn2=3.0)
            blv = Beamline([qf, Drift(L=1.0), qd, Drift(L=1.0), sx])
            vshapes = Dict("Quadrupole" => LayoutShape(shape=:var_box, height_param=:Kn1, size=0.5),
                           "Sextupole" => LayoutShape(shape=:var_box, height_param=:Kn1, size=0.5))
            lesv = lat_layout_shapes(blv; shapes=vshapes, polarity=true)
            @test (lesv[1].y_bottom, lesv[1].y_top) == (0.0, 0.2)
            @test (lesv[2].y_bottom, lesv[2].y_top) == (-0.1, 0.0)
            @test (lesv[3].y_bottom, lesv[3].y_top) == (0.0, 0.0)   # Sextupole has Kn1 = 0
            fshapes = Dict("Quadrupole" => LayoutShape(shape=:var_box, height_param=e -> e.Kn1 * e.L, size=1.0))
            lesf = lat_layout_shapes(blv; shapes=fshapes)
            @test lesf[1].y_top ≈ 0.2 && lesf[2].y_bottom ≈ -0.1
            @test_throws ErrorException lat_layout_shapes(blv; shapes=Dict("Quadrupole" => LayoutShape(shape=:var_box)))
            axv = lat_layout(Figure()[1, 1], blv; shapes=vshapes)
            @test any(p -> p isa Poly, axv.scene.plots)

            # Zero-length elements are as wide as they are tall on screen
            bl0 = Beamline([Drift(L=10.0), HKicker(name="HK"), Drift(L=10.0)])
            fig = Figure(size=(800, 200))
            axl = lat_layout(fig[1, 1], bl0)
            Makie.update_state_before_display!(fig)
            pts = filter(p -> p isa Poly, axl.scene.plots)[end][1][][1]
            lims, vp = axl.finallimits[], axl.scene.viewport[]
            w_px = (maximum(p[1] for p in pts) - minimum(p[1] for p in pts)) * Makie.widths(vp)[1] / Makie.widths(lims)[1]
            h_px = (maximum(p[2] for p in pts) - minimum(p[2] for p in pts)) * Makie.widths(vp)[2] / Makie.widths(lims)[2]
            @test w_px ≈ h_px rtol=1e-3
        end
    end
end
