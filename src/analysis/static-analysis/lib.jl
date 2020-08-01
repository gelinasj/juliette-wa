#**********************************************************************
# Lightweight static analysis of eval/invokelatest
#**********************************************************************
# 
# Read files in [src] directory and counts the number of occuences
#   of "eval(" and "invokelatest("
# 
#**********************************************************************

#--------------------------------------------------
# Imports
#--------------------------------------------------

include("../../utils/lib.jl")
include("parse-eval.jl")

###################################################
# Data
###################################################

#--------------------------------------------------
# Constants
#--------------------------------------------------

# regex-patterns for calls to eval/invokelatest
#   (\W means non-word character and ^ means beginning of input --
#    to exclude cases such as "my_eval(")
CALL_PATTERN(name :: String) = Regex("(\\W|^)$(name)\\(") # r"(\W|^)eval\("
const PATTERN_EVAL = CALL_PATTERN("eval")
const PATTERN_INVOKELATEST = CALL_PATTERN("invokelatest")
const PATTERN_EVAL_MACRO = r"@eval "

#--------------------------------------------------
# Data Types
#--------------------------------------------------

EvalArgStat = Dict{EvalCallInfo, UInt}

# Single file statistics
struct Stat
    eval         :: UInt # number of calls to eval
    invokelatest :: UInt # number of calls to invokelatest
    evalArgStat  :: EvalArgStat # stat of AST heads of evaled expressions
end
Stat() = Stat(0, 0, EvalArgStat())
Stat(ev :: Int, il :: Int) = Stat(ev, il, EvalArgStat())

FilesStat = Dict{String, Stat}

# Single package statistics
mutable struct PackageStat
    pkgName          :: String
    hasSrc           :: Bool
    totalFiles       :: UInt # number of source files
    failedFiles      :: UInt # number of files that failed to process
    interestingFiles :: UInt # number of files with eval/invokelatest
    filesStat        :: FilesStat # fileName => statistics
    pkgStat          :: Stat # package summary statistics
end
# default constructor
PackageStat(pkgName :: String, hasSrc :: Bool) = 
    PackageStat(pkgName, hasSrc, 0, 0, 0, FilesStat(), Stat())

#--------------------------------------------------
# Show
#--------------------------------------------------

#Base.show(io :: IO, evalInfo :: EvalCallInfo) = print(io, evalInfo.astHead)

string10(x :: UInt) = string(x, base=10)

Base.show(io :: IO, un :: UInt) = print(io, string10(un))

Base.show(io :: IO, stat :: Stat) = print(io,
    "{ev: $(stat.eval), il: $(stat.invokelatest)}\n" *
    "[evalArgs: $(stat.evalArgStat)]")

function Base.show(io :: IO, stat :: FilesStat)
    for info in stat
        println(io, "* $(info[1]) => $(info[2])")
    end
end

#--------------------------------------------------
# Stat Arithmetic
#--------------------------------------------------

Base.:+(x :: EvalArgStat, y :: EvalArgStat) = merge(+, x, y)

Base.zero(::Type{Stat}) = Stat()

Base.:+(x :: Stat, y :: Stat) =
    Stat(x.eval + y.eval, x.invokelatest + y.invokelatest,
         x.evalArgStat + y.evalArgStat)

###################################################
# Algorithms
###################################################

#--------------------------------------------------
# Single File
#--------------------------------------------------

Base.sum(stat :: Stat) :: UInt = stat.eval + stat.invokelatest

# Checks if statistics is "interesting", i.e. non-zero
nonVacuous(stat :: Stat) :: Bool = sum(stat) > 0
    #stat.invokelatest > 0

# Some measure of interest (most interesting if there are
#   both eval and invokelatest)
interestFactor(stat :: Stat) :: UInt = let
    Z = zero(UInt)
    hasEval   = stat.eval > Z
    hasInvoke = stat.invokelatest > Z
    val = sum(stat)
    xor(hasEval, hasInvoke) ?
        val :
        (hasEval || hasInvoke ? 1000+val : Z)
end

function mkOccurDict(data :: Vector{T}) :: Dict{T, UInt} where T
    foldl(
        (dict, elem) -> 
            (haskey(dict, elem) ? dict[elem] += 1 : dict[elem] = 1; dict),
        data; init=Dict{T, UInt}()
    )
end

# Computes statistics for source code [text]
function computeStat(text :: String) :: Stat
    ev = count(PATTERN_EVAL, text) + count(PATTERN_EVAL_MACRO, text)
    il = count(PATTERN_INVOKELATEST, text)
    # get more details about eval if possible
    if ev > 0
        try
            evalInfos = gatherEvalInfo(parseJuliaCode(text))
            evArgStat = mkOccurDict(evalInfos)
            Stat(sum((values(evArgStat))), il, evArgStat) # parsing is more precise
        catch
            Stat(ev, il)
        end
    else
        Stat(ev, il)
    end
end

#--------------------------------------------------
# Single Package
#--------------------------------------------------

# String → Bool
isJuliaFile(fname :: String) :: Bool = endswith(fname, ".jl")

# String, PackageStat, String → Nothing
# Reads [filePath] located in [pkgPath]
#   and updates [pkgStat] accordingly with eval/invokelatest stats
function processFile(pkgPath::String, pkgStat::PackageStat, filePath::String)
    try
        stat = computeStat(read(filePath, String))
        if nonVacuous(stat)
            pkgStat.interestingFiles += 1
            # cut pkgPath from file name for readability
            pkgStat.filesStat[filePath[length(pkgPath)+1:end]] = stat
        end
    catch e
        println(stderr, e)
        pkgStat.failedFiles += 1
    end
end

# String, String → PackageStat
# Walks [src] directory of package [pkgName] located at [pkgPath]
function processPkg(pkgPath :: String, pkgName :: String)
    # we assume that correct Julia packages have [src] folder
    srcPath = joinpath(pkgPath, "src")
    # init statistics
    pkgStat = PackageStat(pkgName, isdir(srcPath))
    pkgStat.hasSrc || return pkgStat # exit if no [src]
    # recursively walk all files in [src]
    for (root, _, files) in walkdir(srcPath)
        # we are only interested in Julia files
        files = filter(isJuliaFile, files)
        pkgStat.totalFiles += length(files)
        for file in files
            filePath = joinpath(root, file)
            processFile(pkgPath, pkgStat, filePath)
        end
    end
    # package summary statistics
    if pkgStat.interestingFiles > 0
        pkgStat.pkgStat = foldl(+, values(pkgStat.filesStat))
    end
    pkgStat
end

#--------------------------------------------------
# Packages
#--------------------------------------------------

isGoodPackage(pkgStat :: PackageStat) :: Bool = pkgStat.hasSrc

getInterestFactor(pkgStat :: PackageStat) :: UInt =
    interestFactor(pkgStat.pkgStat)

# String → (Vector{PackageStat}, Vector{PackageStat})
# Processes every folder in [path] as a package folder
# and computes its statistics for it.
# Returns failed packages and stats for successfully processed packages
function processPkgsDir(path :: String)
    paths = map(name -> (joinpath(path, name), name), readdir(path))
    dirs  = filter(d -> isdir(d[1]), paths)
    pkgsStats = map(d -> processPkg(d[1], d[2]), dirs)
    goodPkgs  = filter(isGoodPackage,  pkgsStats)
    badPkgs   = filter(!isGoodPackage, pkgsStats)
    # sort packages information from most interesting to less interesting
    (badPkgs, sort(goodPkgs, by=getInterestFactor, rev=true))
end
