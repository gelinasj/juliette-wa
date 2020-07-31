using Test

include("lib.jl")

@testset "nonVacuous" begin
    @test nonVacuous(Stat(0, 0)) == false
    @test nonVacuous(Stat(1, 0)) == true
    @test nonVacuous(Stat(0, 1)) == true
    @test nonVacuous(Stat(5, 2)) == true
end

@testset "evalName" begin
    @test isEvalName(:eval)
    @test isEvalName(:(eval(:(3))).args[1])
    @test isEvalName(:(Core.eval))
    @test isEvalName(:(Core.eval(:("x"))).args[1])

    @test isEvalMacroName(Symbol("@eval"))
end

@testset "isEvalCall" begin
    @test isEvalCall(:(eval(3)))
    @test isEvalCall(:(Core.eval(Main, 3)))
    @test isEvalCall(:(@eval 5))
    @test isEvalCall(:(@eval(Main, 4+2)))
    @test isEvalCall(Meta.parse("@eval"))
end

@testset "countEval" begin
    # hand-written
    @test countEval(parseJuliaFile("test/test-0.jl")) == 5
    # from GasModels.jl (reduced src/core/export.jl)
    @test countEval(parseJuliaFile("test/test-1.jl")) == 3
    # from Symata.jl (reduced src/math_functions.jl)
    @test countEval(parseJuliaFile("test/test-2.jl")) == 18
    # from CUDA.jl (reduced src/device/intrinsics/atomics.jl)
    @test countEval(parseJuliaFile("test/test-3.jl")) == 9
    # from Genie.jl (reduced src/renderers/Html.jl)
    @test countEval(parseJuliaFile("test/test-4.jl")) == 9
end

@testset "argDescr" begin
    @test argDescr(5) == :value
    @test argDescr(:(const F = 1)) == :const
    @test argDescr(:(f() = 0)) == :function
    @test argDescr(:(x = 666)) == :(=)
    @test argDescr(:(eval(:( f() = 0 ))).args[2]) == :function
end

@testset "getEvalInfo" begin
    @test getEvalInfo(:(eval(:( f() = 0 )))) == EvalCallInfo(:function)
    @test getEvalInfo(:(eval(:( y = 1 )))) == EvalCallInfo(:(=))
    @test getEvalInfo(:(eval())) == EvalCallInfo(:nothing)
    @test getEvalInfo(:(eval(3))) == EvalCallInfo(:value)
    @test getEvalInfo(:(Core.eval(Main, 3))) == EvalCallInfo(:value)
    @test getEvalInfo(:(@eval y = 1)) == EvalCallInfo(:(=))
    @test getEvalInfo(:(@eval(Main, y = 1))) == EvalCallInfo(:(=))
end
