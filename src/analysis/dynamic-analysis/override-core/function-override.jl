include("../../../utils/lib.jl")
include("../../static-analysis/lib/analysis.jl")
include("ast-parse-helpers.jl")

##############################
# Domain Object Definitions
##############################

# Represents a counter
Count = Int64

# Represents an ast head distribution
AstInfo = Vector{EvalCallInfo}

# Represents the a function name distribution
FunctionInfo = Dict{String, Count}

# Represents the distribution of function definition types
mutable struct FuncDefTracker
    newFuncCount      :: Count
    funcRedefCount    :: Count
    miscCount         :: Count
    bodylessFuncCount :: Count
end
# Initializes a base representation of function type tracker
FuncDefTracker() = FuncDefTracker(0,0,0,0)

# Represents the information collected regarding eval function calls
mutable struct EvalInfo
    evalCallInfos :: Vector{EvalCallInfo}
    astHeads     :: AstInfo
    funcDefTypes :: FuncDefTracker
end

# Represents the information collected regarding invokelatest function calls
mutable struct InvokeLatestInfo
    funcNames  :: FunctionInfo
end

# Represents the information collected regarding the stacktrace of a function call
mutable struct StackTraceInfo{T}
    count     :: Count
    auxillary :: T
end
# Initializes a base representation of stacktrace information
StackTraceInfo(funcSpecificData) = StackTraceInfo(0, funcSpecificData)

# Represents the information collected regarding overriden function calls
mutable struct FuncMetadata{T, U}
    callCount        :: Count
    stackTraces      :: Dict{Vector{StackTraces.StackFrame}, StackTraceInfo{U}}
    funcSpecificData :: T
end
# Initializes a base representation of function metadata
FuncMetadata(funcSpecificData;
        initialTrace=Dict{Vector{StackTraces.StackFrame}, StackTraceInfo{Nothing}}()
    ) = FuncMetadata(0, initialTrace, funcSpecificData)

# Represents the information being analyzed when running packages
mutable struct OverrideInfo
    identifier          :: String
    # Determines if frame particular classification
    # (ie. source-file, internal-file, external-file)
    stackFramePredicate :: Function
    evalInfo            :: FuncMetadata{EvalInfo}
    invokeLatestInfo    :: FuncMetadata{InvokeLatestInfo}
end
# Initializes a base representation of override information
OverrideInfo(identifier :: String, functionDataFilter :: Function) =
    OverrideInfo(identifier, functionDataFilter,
        FuncMetadata(EvalInfo(EvalCallInfo[], Vector{EvalCallInfo}(), FuncDefTracker());
            initialTrace=Dict{Vector{StackTraces.StackFrame},StackTraceInfo{AstInfo}}()),
        FuncMetadata(InvokeLatestInfo(Dict());
            initialTrace=Dict{Vector{StackTraces.StackFrame},StackTraceInfo{FunctionInfo}}())
    )

##################################
# Initialization of global vars
##################################

# Location of julia packages
PACKAGE_DIR = joinpath(DEPOT_PATH[1], "packages")
# Location of package being analyzed
DYNAMIC_ANALYSIS_PACKAGE_DIR = joinpath(PACKAGE_DIR, ENV["DYNAMIC_ANALYSIS_PACKAGE_NAME"])

# Determines if the given stack frame occurs in the given directory
frameInDirectory(dir, frame) = findfirst(dir, string(frame.file)) != nothing

# Determines if given stack frame is from package source code
isSourceCode(stackFrame) = frameInDirectory(DYNAMIC_ANALYSIS_PACKAGE_DIR, stackFrame)
# Determines if given stack frame is from external library code
isExternalLibCode(stackFrame) = !isSourceCode(stackFrame) && frameInDirectory(PACKAGE_DIR, stackFrame)
# Determines if given stack frame is from internal julia library code
isInternalLibCode(stackFrame) = !(isSourceCode(stackFrame) || isExternalLibCode(stackFrame))

# Initialize empty dataCollection
overrideCollection = [
    OverrideInfo("source", isSourceCode),
    OverrideInfo("internal-lib", isInternalLibCode),
    OverrideInfo("external-lib", isExternalLibCode)
]

########################
# Overriden Functions
########################

function isTopLevel(s::Vector{StackTraces.StackFrame}, startIdx :: Int)
    idx = startIdx
    while idx < length(s) && s[idx].func == Symbol("macro expansion")
        idx += 1
    end
    return s[idx].func == Symbol("top-level scope")
end

# Overrides eval to store metadata about calls to the function
function Core.eval(m::Module, @nospecialize(e))
    isInFunc = !isTopLevel(stacktrace(), 2)
    #println("$(getproperty.(stacktrace(), :func)) $isInFunc")
    # aux functions
    updateEvalInfoWrap(evalInfo :: EvalInfo, stackinfo) = updateEvalInfo(evalInfo, e, m, stackinfo)
    updateTraceAuxillary(astHeads :: AstInfo) = updateAstInfo(astHeads, e, isInFunc)
    # action
    exprs = extractExprs(e)
    for expr = exprs
        updateFuncMetadata(
            overrideCollection, ((overrideInfo) -> overrideInfo.evalInfo),
            3, updateEvalInfoWrap;
            auxTuple=((() -> Vector{EvalCallInfo}()), updateTraceAuxillary))
    end

    # Original eval code
    try
    	ccall(:jl_toplevel_eval_in, Any, (Any, Any), m, e)
    catch e
        if !(isa(e,ErrorException) && e.msg == "error in method definition: function Core.eval must be explicitly imported to be extended")
          throw(e)
        end
    end
end

# Overrides invokelatest to store metadata about calls to the function
function Base.invokelatest(@nospecialize(f), @nospecialize args...; kwargs...)
    # aux functions
    updateInvokeLatestInfo(invokeLatestInfo :: InvokeLatestInfo, stackinfo) =
        updateDictCount(invokeLatestInfo.funcNames, string(f))
    updateTraceAuxillary(funcNames :: FunctionInfo) =
        updateDictCount(funcNames, string(f))
    # action
    updateFuncMetadata(
        overrideCollection, ((overrideInfo) -> overrideInfo.invokeLatestInfo),
        4, updateInvokeLatestInfo;
        auxTuple=((() -> Dict{String,Int64}()), updateTraceAuxillary))

    # Original invokelatest code
    if isempty(kwargs)
        return Core._apply_latest(f, args)
    end
    # We use a closure (`inner`) to handle kwargs.
    inner() = f(args...; kwargs...)
    Core._apply_latest(inner)
end

##############################
# Function Override Helpers
##############################

# Adds one to the value of the key, creates keys with value of 1 if it does not already exist
updateDictCount(dict :: Dict{T, Count}, key :: T) where {T} =
    dict[key] = get!(dict, key, 0) + 1

# Updates the information for a new call to a function being analyzed
function updateFuncMetadata(
        overrideCollection :: Vector{OverrideInfo}, getFuncMetadata :: Function,
        stackFrameIndex :: Count, updateFuncSpecificData :: Function;
        auxTuple=((() -> nothing), ((aux) -> nothing)) :: Tuple{Function, Function})
    callingtrace = stacktrace()[stackFrameIndex + 1]
    for overrideInfo = overrideCollection
        metadata = getFuncMetadata(overrideInfo)
        if overrideInfo.stackFramePredicate(callingtrace)
            (defaultTraceAuxillary, updateTraceAuxillary) = auxTuple
            updateStackTraces(
                metadata.stackTraces, stackFrameIndex + 1,
                defaultTraceAuxillary, updateTraceAuxillary
            )
            metadata.callCount += 1
            updateFuncSpecificData(metadata.funcSpecificData, callingtrace)
        end
    end
end

# Updates the metadata information for a stack trace
function updateStackTraces(
        stackTraces :: Dict{Vector{StackTraces.StackFrame}, StackTraceInfo{U}},
        stackFrameIndex :: Count,
        defaultTraceAuxillary :: Function, updateTraceAuxillary :: Function
    ) where {U}
    st = stacktrace()
    stackFrame = st[stackFrameIndex+1:min(length(st),stackFrameIndex+4)]
    defaultStackTraceInfo = StackTraceInfo(defaultTraceAuxillary())
    stackTraceInfo = get!(stackTraces, stackFrame, defaultStackTraceInfo)
    stackTraceInfo.count += 1
    updateTraceAuxillary(stackTraceInfo.auxillary)
end

# Updates the ast information to increment the ast type of the given expression
function updateEvalInfo(evalInfo :: EvalInfo, e, m :: Module, stackinfo)
    isInFunc = stackinfo.func != Symbol("top-level scope")
    append!(evalInfo.evalCallInfos, argDescr(e, EvalArgContext(isInFunc, false)))
    astIdentifier = updateAstInfo(evalInfo.evalCallInfos, e, isInFunc)
    if astIdentifier == :function
        # a lambda function (()->1)
        if isLambdaFunc(e)
            evalInfo.funcDefTypes.newFuncCount += 1
        # a variable bound to a lambda function (f=()->1)
        elseif isLambdaBinding(e)
            updateMiscCount(evalInfo, e, "Lambda binding used")
        # function without body (function f end)
        elseif isAstWithBody(e, :function) && isa(e.args[1], Symbol)
            evalInfo.funcDefTypes.bodylessFuncCount += 1
        # a normal or abreviated definitio ((function f() 1 end) or (f()=1))
        else
            try
                Core.isdefined(getFuncNameAndModule(e, m)...) ?
                    evalInfo.funcDefTypes.funcRedefCount += 1 :
                    evalInfo.funcDefTypes.newFuncCount += 1
            catch err
                updateMiscCount(evalInfo, e, "Issue with functin definition parse: (err: $(string(err)))")
            end
        end
    end
end

# Updates the ast information to increment the ast type of the given expression
function updateAstInfoHelp(astHeads :: AstInfo, astIdentifier :: Symbol)
    updateDictCount(astHeads, astIdentifier)
    astIdentifier
end
updateAstInfo(astHeads :: AstInfo, e, isInFunc :: Bool) =
    append!(astHeads, argDescr(e, EvalArgContext(isInFunc, false)))

# Updates misc count and prints expression that is misc function definition
function updateMiscCount(evalInfo, e, msg)
    # @info msg
    # dump(e)
    evalInfo.funcDefTypes.miscCount += 1
end
