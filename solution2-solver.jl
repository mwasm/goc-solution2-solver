using Distributed # Standard library for distributed memory parallel computing

@everywhere using Ipopt # Library for non-linear optimization of continuous systems

include("code-2-lib/parsers.jl") # Insert the contents of parsers.jl here
include("code-2-lib/lib.jl") # Insert the contents of lib.jl here.

function compute_solution2(con_file::String, inl_file::String, raw_file::String, rop_file::String, time_limit::Int, scoring_method::Int, network_model::String; output_dir::String="", scenario_id::String="none") # Function named "compute_solution2"
    time_data_start = time() # To note the start time
    PowerModels.silence() # Suppresses information and warning messages output by PowerModels
    goc_data = parse_goc_files(con_file, inl_file, raw_file, rop_file, scenario_id=scenario_id) # Parse the input files
    network = build_pm_model(goc_data) # Calls "build_pm_model" function to make model based on input data

    sol = read_solution1(network, output_dir=output_dir) # Reads the base solution
    PowerModels.update_data!(network, sol) # To update network with the values from sol

    check_network_solution(network) # Checks feasibility criteria of network solution, produces an error if a problem is found

    network_tmp = deepcopy(network) # Copies all fields from "network"
    balance = compute_power_balance_deltas!(network_tmp) # Compute power balance deltas for active & reactive power

    if balance.p_delta_abs_max > 0.01 || balance.q_delta_abs_max > 0.01 # Check the delta limit for active & reactive power
        error(LOGGER, "solution1 power balance requirements not satified (all power balance values should be below 0.01). $(balance)")
    end
    load_time = time() - time_data_start # Find difference between the start & end time

    ###### Prepare Solution 2 ######

    time_contingencies_start = time() # To note the contingencies start time

    gen_cont_total = length(network["gen_contingencies"]) # Finds how many generator contingencies
    branch_cont_total = length(network["branch_contingencies"])  # Finds how many branch contingencies
    cont_total = gen_cont_total + branch_cont_total # Finds total contingencies

    cont_order = contingency_order(network) # To retrieve the order of contingency

    workers = Distributed.workers() # Retrieve the workers

    process_data = [] # An empty dic.

    cont_per_proc = cont_total/length(workers) # Number of contingencies per procs

    for p in 1:length(workers) 
        cont_start = trunc(Int, ceil(1+(p-1)*cont_per_proc))
        cont_end = min(cont_total, trunc(Int,ceil(p*cont_per_proc)))
        pd = (
            pid = p,
            processes = length(workers),
            con_file = con_file,
            inl_file = inl_file,
            raw_file = raw_file,
            rop_file = rop_file,
            scenario_id = scenario_id,
            output_dir = output_dir,
            cont_range = cont_start:cont_end,
        )
        push!(process_data, pd) # Push pd to process_data dic.
    end

    for (i,pd) in enumerate(process_data)
        info(LOGGER, "worker task $(pd.pid): $(length(pd.cont_range)) / $(pd.cont_range)")
    end

    solution2_files = pmap(solution2_solver, process_data, retry_delays = zeros(3)) # Parallel mapping 
    sort!(solution2_files) # In-place sorting 
    #println("pmap result: $(solution2_files)")

    time_contingencies = time() - time_contingencies_start # Calculates time difference
    info(LOGGER, "contingency eval time: $(time_contingencies)")
    info(LOGGER, "time per contingency: $(time_contingencies/cont_total)")

    info(LOGGER, "combine $(length(solution2_files)) solution2 files")
    combine_files(solution2_files, "solution2.txt"; output_dir=output_dir) # Adds solution2.txt to output directory
    remove_files(solution2_files)


    println("")

    data = [
        "----",
        "scenario id",
        "bus",
        "branch",
        "gen_cont",
        "branch_cont",
        "runtime (sec.)",
    ]
    println(join(data, ", "))

    data = [
        "DATA_SSS",
        goc_data.scenario,
        length(network["bus"]),
        length(network["branch"]),
        length(network["gen_contingencies"]),
        length(network["branch_contingencies"]),
        time_contingencies,
    ]
    println(join(data, ", "))
end


@everywhere function solution2_solver(process_data)
    #println(process_data)
    time_data_start = time()
    PowerModels.silence()
    goc_data = parse_goc_files(
        process_data.con_file, process_data.inl_file, process_data.raw_file,
        process_data.rop_file, scenario_id=process_data.scenario_id)
    network = build_pm_model(goc_data)

    sol = read_solution1(network, output_dir=process_data.output_dir)
    PowerModels.update_data!(network, sol)
    correct_voltage_angles!(network)

    time_data = time() - time_data_start

    for (i,bus) in network["bus"]
        if haskey(bus, "evhi")
            bus["vmax"] = bus["evhi"]
        end
        if haskey(bus, "evlo")
            bus["vmin"] = bus["evlo"]
        end
    end

    for (i,branch) in network["branch"]
        if haskey(branch, "rate_c")
            branch["rate_a"] = branch["rate_c"]
        end
    end

    contingencies = contingency_order(network)[process_data.cont_range]

    for (i,branch) in network["branch"]
        g, b = PowerModels.calc_branch_y(branch)
        tr, ti = PowerModels.calc_branch_t(branch)
        branch["g"] = g
        branch["b"] = b
        branch["tr"] = tr
        branch["ti"] = ti
    end

    bus_gens = gens_by_bus(network)

    network["delta"] = 0
    for (i,bus) in network["bus"]
        bus["vm_base"] = bus["vm"]
        bus["vm_start"] = bus["vm"]
        bus["va_start"] = bus["va"]
        bus["vm_fixed"] = length(bus_gens[i]) != 0

    end

    for (i,gen) in network["gen"]
        gen["pg_base"] = gen["pg"]
        gen["pg_start"] = gen["pg"]
        gen["qg_start"] = gen["qg"]
        gen["pg_fixed"] = false
        gen["qg_fixed"] = false
    end

    #nlp_solver = JuMP.with_optimizer(Ipopt.Optimizer, tol=1e-6, mu_init=1e-6, hessian_approximation="limited-memory", print_level=0)
    nlp_solver = JuMP.with_optimizer(Ipopt.Optimizer, tol=1e-6, print_level=0)
    #nlp_solver = JuMP.with_optimizer(Ipopt.Optimizer, tol=1e-6)
    #nlp_solver = JuMP.with_optimizer(Ipopt.Optimizer, tol=1e-6, hessian_approximation="limited-memory")


    pad_size = trunc(Int, ceil(log(10,process_data.processes)))
    padded_pid = lpad(string(process_data.pid), pad_size, "0")
    solution_filename = "solution2-$(padded_pid).txt"

    if length(process_data.output_dir) > 0
        solution_path = joinpath(process_data.output_dir, solution_filename)
    else
        solution_path = solution_filename
    end
    if isfile(solution_path)
        warn(LOGGER, "removing existing solution2 file $(solution_path)")
        rm(solution_path)
    end
    open(solution_path, "w") do sol_file
        # creates an empty file in the case of workers without contingencies
    end

    #network_tmp = deepcopy(network)
    for cont in contingencies
        if cont.type == "gen"
            info(LOGGER, "working on: $(cont.label)")
            time_start = time()
            network_tmp = deepcopy(network)
            debug(LOGGER, "contingency copy time: $(time() - time_start)")
            network_tmp["cont_label"] = cont.label

            cont_gen = network_tmp["gen"]["$(cont.idx)"]
            cont_gen["contingency"] = true
            cont_gen["gen_status"] = 0
            pg_lost = cont_gen["pg"]

            time_start = time()
            result = run_fixpoint_pf_v2_2!(network_tmp, pg_lost, ACRPowerModel, nlp_solver, iteration_limit=5)
            debug(LOGGER, "second-stage contingency solve time: $(time() - time_start)")

            result["solution"]["label"] = cont.label
            result["solution"]["feasible"] = (result["termination_status"] == LOCALLY_SOLVED)
            result["solution"]["cont_type"] = "gen"
            result["solution"]["cont_comp_id"] = cont.idx

            result["solution"]["gen"]["$(cont.idx)"]["pg"] = 0.0
            result["solution"]["gen"]["$(cont.idx)"]["qg"] = 0.0

            correct_contingency_solution!(network, result["solution"])
            open(solution_path, "a") do sol_file
                sol2 = write_solution2_contingency(sol_file, network, result["solution"])
            end

            network_tmp["gen"]["$(cont.idx)"]["gen_status"] = 1
        elseif cont.type == "branch"
            info(LOGGER, "working on: $(cont.label)")
            time_start = time()
            network_tmp = deepcopy(network)
            debug(LOGGER, "contingency copy time: $(time() - time_start)")
            network_tmp["cont_label"] = cont.label
            network_tmp["branch"]["$(cont.idx)"]["br_status"] = 0


            time_start = time()
            result = run_fixpoint_pf_v2_2!(network_tmp, 0.0, ACRPowerModel, nlp_solver, iteration_limit=5)
            debug(LOGGER, "second-stage contingency solve time: $(time() - time_start)")

            result["solution"]["label"] = cont.label
            result["solution"]["feasible"] = (result["termination_status"] == LOCALLY_SOLVED)
            result["solution"]["cont_type"] = "branch"
            result["solution"]["cont_comp_id"] = cont.idx

            correct_contingency_solution!(network, result["solution"])
            open(solution_path, "a") do sol_file
                sol2 = write_solution2_contingency(sol_file, network, result["solution"])
            end

            network_tmp["branch"]["$(cont.idx)"]["br_status"] = 1
        else
            @assert("contingency type $(cont.type) not known")
        end
    end

    return solution_path
end

