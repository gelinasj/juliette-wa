using Pkg
Pkg.add("JSON")
using JSON

const EVAL_PROGRAMS_DIR = "eval-programs"

# Represents the information being analyzed regarding eval calls
struct EvalInfo
    callCount :: Int64
    stackTraces :: Dict{StackTraces.StackTrace, Int}
end

# Overrides eval and runs each eval program to count the number of times eval is used
evalInfo = EvalInfo(0, Dict())
function Core.eval(m::Module, @nospecialize(e))
    newTrace = stacktrace()
    newCallCount = evalInfo.callCount + 1
    evalInfo.stackTraces[newTrace] = get!(evalInfo.stackTraces, newTrace, 0) + 1
    global evalInfo = EvalInfo(newCallCount, evalInfo.stackTraces)
    ccall(:jl_toplevel_eval_in, Any, (Any, Any), m, e)
end

function storeEvalInfo(info :: EvalInfo) :: Nothing
    fd = open("C:/Users/gelin/Documents/computer-science/research/julia/juliette-wa/src/analysis/output.json", "a")
    JSON.print(fd, evalInfoToJson(info), 2)
    close(fd)
end

function evalInfoToJson(info :: EvalInfo)
    json = Dict()
    json["eval_count"] = info.callCount
    json["stack_traces"] = stackTracesToJson(info.stackTraces)
    json
end

function stackTracesToJson(stackTraces :: Dict{StackTraces.StackTrace, Int})
    sortedStackTraces = sort!(collect(stackTraces), by = pair -> pair.second, rev = true)
    function stacktraceToJson((trace, count), acc)
        append!([Dict(["trace_count" => count, "stack_trace" => map(string, trace)])], acc)
    end
    foldr(stacktraceToJson, sortedStackTraces; init = [])
end
