include("code-2-lib/distributed.jl") # Insert the contents of distributed.jl here.
add_procs() # Calls the fucntin add_procs() from distributed.jl library

@everywhere using Pkg # Using the built-in package manager in julia
@everywhere Pkg.activate(".") # Activating the package manager for required usage

include("solution2-solver.jl") # Insert the contents of solution2-solver.jl here.

function MyJulia2(InFile1::String, InFile2::String, InFile3::String, InFile4::String, TimeLimitInSeconds::Int64, ScoringMethod::Int64, NetworkModel::String) # Calls the function named MyJulia2 with given arguments
    println("running MyJulia2") # Print the statement
    println("  $(InFile1)") # Print the contents of file
    println("  $(InFile2)")
    println("  $(InFile3)")
    println("  $(InFile4)")
    println("  $(TimeLimitInSeconds)")
    println("  $(ScoringMethod)")
    println("  $(NetworkModel)")

    compute_solution2(InFile1, InFile2, InFile3, InFile4, TimeLimitInSeconds, ScoringMethod, NetworkModel) # Calls the functin named compute_solution2 with given arguments
end
