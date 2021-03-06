include("../jl-transpiler/main.jl")

# Includes given file [fname]
# If there is an error on loading, rethrows that error
# (e.g. if [MethodError] happens in the file [fname],
#  [include(fname)] will wrap it into [LoadError],
#  so [e] will be [LoadError(..., error=MethodError(...))],
#  and the [load] function will rethrow the inner error)
function load(fname :: String)
  try
    include(fname)
  catch e
    if isa(e, LoadError)
      throw(e.error)
    else
      throw(e)
    end
  end
end

# prettify_juliette: converts the given juilette expression to human readable format
function prettify_juliette(raw_juliette :: String, dir_prefix :: String) :: String
    tmpfile = ".pretty_tmpfile.txt"
    fd = open(tmpfile, "w+")
    write(fd, raw_juliette)
    close(fd)
    prettified_juliette = read(pipeline(`racket $(dir_prefix)pretty-print-sexpr.rkt`; stdin=tmpfile), String)[2:end]
    rm(tmpfile, force=true)
    return prettified_juliette
end

# transpile_and_prettify: transpiles theh given file and returns the
# prettified string
function transpile_and_prettify(filepath :: String, dir_prefix="./" :: String) :: String
    fd = open(filepath)
    juliacode = read(fd, String)
    close(fd)
    raw_juliette_expr = transpile(juliacode)
    return prettify_juliette(raw_juliette_expr, dir_prefix)
end

# get_methodvalue: gets the name of the given method
get_methodvalue(value) = string(value)

function REDEX_PROLOG(dir_prefix="../" :: String) :: String
"#lang racket
(require redex)

; import surface language
(require \"$(dir_prefix)redex/core/wa-surface.rkt\")
; import full language
(require \"$(dir_prefix)redex/core/wa-full.rkt\")
; import optimizations
(require \"$(dir_prefix)redex/optimizations/wa-optimized.rkt\")"
end
