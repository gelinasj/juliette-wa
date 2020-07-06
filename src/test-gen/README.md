# Julia to Juliette Conversion

## Transpile Julia

A Julia file in the current directory can be transpiled
in one of the following way (commands must be run from the
current directory):

* `julia julia-to-juliette.jl <file name> <args>` - transpiles the given
  file to a target file with the same name but `.rkt` extension
  * Arguments: the argument parameters are optional and any combination of the arguments can be used being that they are separate by spaces
    * `-o` - if this argument is provided then the transpiled juliette program will be run using the languages defined optimiations
    * `-m` - if this argument is provided then the transpiled juliette program will display the resulting method table when run
  * Examples: following are a set of potential run commands
    * `julia julia-to-juliette.jl codefile`
      * Transpiles the `codefile.jl` file to a `codefile.rkt` file
    * `julia julia-to-juliette.jl fname -m -o`
      * Transpiles the `fname.jl` file to a `fname.rkt` file where the juliette is run optimized and a resulting method table is shown after being run

## Assumptions

Source programs don't use global variables
and don't throw method ambiguity errors.
The former is not supported by the calculus,
and latter is not supported by the testing framework.

Source programs are allowed to have:

* global method definitions;
* method calls;
* integers, floats, strings;
* `eval` and `invokelatest`;
* interpolated local variables inside `eval`.
