#!/usr/bin/env julia --project=.

InFile1="test-dataset/scenario_1/case.con" # Contingency information
InFile2="test-dataset/scenario_1/case.inl" # Unit Inertia and Governor Response Data File
InFile3="test-dataset/scenario_1/case.raw" # Power Flow Raw Data File
InFile4="test-dataset/scenario_1/case.rop" # Generator Cost Data File
TimeLimitInSeconds=600 # 10 min.
ScoringMethod=2
NetworkModel="IEEE 14"

println("  $(InFile1)") # Print the contents of specified file.
println("  $(InFile2)")
println("  $(InFile3)")
println("  $(InFile4)")
println("  $(TimeLimitInSeconds)")
println("  $(ScoringMethod)")
println("  $(NetworkModel)")

include("MyJulia2.jl") # Insert the contents of MyJulia2.jl here.

compute_solution2(InFile1, InFile2, InFile3, InFile4, TimeLimitInSeconds, ScoringMethod, NetworkModel, output_dir="test-dataset/scenario_1")
 # Calls the function named "compute_solution2"
