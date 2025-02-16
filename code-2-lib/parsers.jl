@everywhere using PowerModels # Uses Julia package for Steady-State Power Network Optimization.

##### Generic Helper Functions #####

function remove_comment(string)
    return split(string, "/")[1] # Split str into an array of substrings on occurrences of the delimiter (eg ,)
end


##### GOC Initialization File Parser (.ini) #####

function parse_goc_files(ini_file; scenario_id="") # Function to parse the input files
    files, scenario_id = find_goc_files(ini_file, scenario_id=scenario_id) # Calls the function named "find_goc_files"
    return parse_goc_files(files["con"], files["inl"], files["raw"], files["rop"], ini_file=ini_file, scenario_id=scenario_id) # Returns the output of function "parse_goc_files"
end

function find_goc_files(ini_file; scenario_id="")
    files = Dict(
        "rop" => "x",
        "raw" => "x",
        "con" => "x",
        "inl" => "x"
    )

    if !endswith(ini_file, ".ini") # Checks for the format of file
        warn(LOGGER, "given init file does not end with .ini, $(ini_file)") # Gives warning if the file format is not correct
    end

    open(ini_file) do io # Opens the ini_file
        for line in readlines(io) 
            line = strip(line) # Strip fucntion is used to trim both leading & trailing white space.
            #println(line)
            if startswith(line, "[INPUTS]")
                # do nothing
            elseif startswith(line, "ROP")
                files["rop"] = strip(split(line,"=")[2]) # Split returns a list of the words in the string, using sep as the delimiter string
            elseif startswith(line, "RAW")
                files["raw"] = strip(split(line,"=")[2])
            elseif startswith(line, "CON")
                files["con"] = strip(split(line,"=")[2])
            elseif startswith(line, "INL")
                files["inl"] = strip(split(line,"=")[2])
            else
                warn(LOGGER, "unknown input given in ini file: $(line)") # Warning if none of the conditions satisfied
            end
        end
    end

    #println(files)

    ini_dir = dirname(ini_file)

    #println(ini_dir)
    scenario_dirs = [file for file in readdir(ini_dir) if isdir(joinpath(ini_dir, file))]
    scenario_dirs = sort(scenario_dirs) # Sort the scenario_dirs
    #println(scenario_dirs)

    if length(scenario_id) == 0 # Checks the length of scenario_id if it is equal to zero
        scenario_id = scenario_dirs[1] # Assigns the value of scenario_dirs[1] to scenario_id
        info(LOGGER, "no scenario specified, selected directory \"$(scenario_id)\"") # If scenario_id is zero then no scenario is specified.
    else
        if !(scenario_id in scenario_dirs) # Checks whether scenario_id is in scenario_dirs
            error(LOGGER, "$(scenario_id) not found in $(scenario_dirs)") # Error message if scenario_id not found.
        end
    end

    for (id, path) in files
        if path == "."
            files[id] = ini_dir # Assigns ini_dir to files[id]
        elseif path == "x"
            files[id] = joinpath(ini_dir, scenario_id) # Join path components into a full path. 
        else
            error(LOGGER, "unknown file path directive $(path) for file $(id)") # Error (unknown file path) if none of the above conditions fulfilled
        end
    end

    files["raw"] = joinpath(files["raw"], "case.raw")
    files["rop"] = joinpath(files["rop"], "case.rop")
    files["inl"] = joinpath(files["inl"], "case.inl")
    files["con"] = joinpath(files["con"], "case.con")

    return files, scenario_id
end


@everywhere function parse_goc_files(con_file, inl_file, raw_file, rop_file; ini_file="", scenario_id="none") # Function that performs the parsing of goc files
    files = Dict(
        "rop" => rop_file,
        "raw" => raw_file,
        "con" => con_file,
        "inl" => inl_file
    )

    info(LOGGER, "Parsing Files") # To notify the current situation of the program
    info(LOGGER, "  raw: $(files["raw"])") # raw: raw_file
    info(LOGGER, "  rop: $(files["rop"])") # rop: rop_file
    info(LOGGER, "  inl: $(files["inl"])") # inl: inl_file
    info(LOGGER, "  con: $(files["con"])") # con: con_file

    info(LOGGER, "skipping power models data warnings") # Informs what things are skipped
    pm_logger_level = getlevel(getlogger(PowerModels)) # "getlogger" returns the current root/global logger (to record events) 
    setlevel!(getlogger(PowerModels), "error")
    network_model = PowerModels.parse_file(files["raw"], import_all=true) # Parse the raw file
    setlevel!(getlogger(PowerModels), pm_logger_level)

    gen_cost = parse_rop_file(files["rop"]) # parsing the rop file
    response = parse_inl_file(files["inl"]) # parsing the inl file
    contingencies = parse_con_file(files["con"]) # parsing the con file

    return (ini_file=ini_file, scenario=scenario_id, network=network_model, cost=gen_cost, response=response, contingencies=contingencies, files=files) # Returns these values
end


function parse_goc_opf_files(ini_file; scenario_id="") # Function to parse the opf files
    files = Dict(
        "rop" => "x",
        "raw" => "x",
    )

    if !endswith(ini_file, ".ini") # Chcks the file format
        warn(LOGGER, "given init file does not end with .ini, $(ini_file)") # Gives warning due to wrong file format
    end

    open(ini_file) do io # Open the ini_file and allow read/write permissions
        for line in readlines(io) # For loop to read lines
            line = strip(line) # Removes leading and trailing characters from line
            #println(line)
            if startswith(line, "[INPUTS]") # Returns true if line starts with INPUTS.
                # do nothing
            elseif startswith(line, "ROP") # Returns true if line starts with ROP.
                files["rop"] = strip(split(line,"=")[2]) # Split: splits the characters on a new line
            elseif startswith(line, "RAW") # Returns true if line starts with RAW.
                files["raw"] = strip(split(line,"=")[2]) # Split: splits the characters on a new line
            else
                warn(LOGGER, "unknown input given in ini file: $(line)") # Warning if none of the above conditions satisfied
            end
        end
    end

    #println(files)

    ini_dir = dirname(ini_file) # Assigns the directory name of ini_file to ini_dir

    #println(ini_dir)
    scenario_dirs = [file for file in readdir(ini_dir) if isdir(joinpath(ini_dir, file))] # Reads the ini_dir and if directory is present then joins the path with file
    scenario_dirs = sort(scenario_dirs) # To sort the scenario_dirs
    #println(scenario_dirs)

    if length(scenario_id) == 0 # Checks the length of scenario_id if it is equal to zero
        scenario_id = scenario_dirs[1] # Assigns the value of scenario_dirs[1] to scenario_id
        info(LOGGER, "no scenario specified, selected directory \"$(scenario_id)\"") # If scenario_id is zero then no scenario is specified
    else
        if !(scenario_id in scenario_dirs) # Checks whether scenario_id is in scenario_dirs
            error(LOGGER, "$(scenario_id) not found in $(scenario_dirs)") # Error message if scenario_id not found.
        end
    end

    for (id, path) in files
        if path == "."
            files[id] = ini_dir  # Assigns ini_dir to files[id]
        elseif path == "x"
            files[id] = joinpath(ini_dir, scenario_id) # Join path components into a full path. 
        else
            error(LOGGER, "unknown file path directive $(path) for file $(id)") # Error (unknown file path) if none of the above conditions fulfilled
        end
    end

    files["raw"] = joinpath(files["raw"], "case.raw")
    files["rop"] = joinpath(files["rop"], "case.rop")

    info(LOGGER, "Parsing Files")
    info(LOGGER, "  raw: $(files["raw"])")
    info(LOGGER, "  rop: $(files["rop"])")

    network_model = PowerModels.parse_file(files["raw"], import_all=true) # Parsing the raw file to know details about network model
    gen_cost = parse_rop_file(files["rop"]) # Parsing the rop file to get gen_cost

    return (ini_file=ini_file, scenario=scenario_id, network=network_model, cost=gen_cost, files=files) # Returns the specified values
end


##### Unit Inertia and Governor Response Data File Parser (.inl) #####

@everywhere function parse_inl_file(file::String) # Function to parse the .inl file
    open(file) do io # Open the file for read/write access
        return parse_inl_file(io) # Return the parsed file
    end
end

@everywhere function parse_inl_file(io::IO) # Function including the details for parsing the inl file
    inl_list = []
    for line in readlines(io) 
        #line = remove_comment(line)

        if startswith(strip(line), "0") # Checks if the line starts with zero  
            debug(LOGGER, "inl file sentinel found")
            break
        end
        line_parts = split(line, ",") # Split the line based on commas
        @assert length(line_parts) >= 7 # Assert macro allows the users to optionally specify their own error message, instead of just printing the failed expression

        inl_data = Dict(
            "i"    => parse(Int, line_parts[1]),
            "id"   => strip(line_parts[2]),
            "h"    => strip(line_parts[3]),
            "pmax" => strip(line_parts[4]),
            "pmin" => strip(line_parts[5]),
            "r"    => parse(Float64, line_parts[6]),
            "d"    => strip(line_parts[7])
        )

        @assert inl_data["r"] >= 0.0 # Assert macro allows the users to optionally specify their own error message, instead of just printing the failed expression

        #println(inl_data)
        push!(inl_list, inl_data) # Inserts inl_data at the end of inl_list
    end
    return inl_list 
end




##### Generator Cost Data File Parser (.rop) #####

@everywhere rop_sections = [
    "mod" => "Modification Code",
    "bus_vm" => "Bus Voltage Attributes",
    "shunt_adj" => "Adjustable Bus Shunts",
    "load" => "Bus Loads",
    "load_adj" => "Adjustable Bus Load Tables",
    "gen" => "Generator Dispatch Units",
    "disptbl" => "Active Power Dispatch Tables",
    "gen_reserve" => "Generator Reserve Units",
    "qg" => "Generation Reactive Capability",
    "branch_x" => "Adjustable Branch Reactance",
    "ctbl" => "Piecewise Linear Cost Curve Tables",
    "pwc" => "Piecewise Quadratic Cost Curve Tables",
    "pec" => "Polynomial & Exponential Cost Curve Tables",
    "reserve" => "Period Reserves",
    "branch_flow" => "Branch Flows",
    "int_flow" => "Interface Flows",
    "lin_const" => "Linear Constraint Dependencies",
    "dc_const" => "Two Terminal DC Line Constraint Dependencies",
]

@everywhere function parse_rop_file(file::String) # Calls the function named parse_rop_file
    open(file) do io # Opens the file for read/write operations
        return parse_rop_file(io) 
    end
end

@everywhere function parse_rop_file(io::IO) # Function including the details for parsing the rop file
    active_section_idx = 1
    active_section = rop_sections[active_section_idx]

    section_data = Dict()
    section_data[active_section.first] = []

    line_idx = 1
    lines = readlines(io) # Read from io
    while line_idx < length(lines) # Compare the length of lines and line index
        #line = remove_comment(lines[line_idx])
        line = lines[line_idx]
        if startswith(strip(line), "0") # Checks if the stripped line starts with zero
            debug(LOGGER, "finished reading rop section $(active_section.second) with $(length(section_data[active_section.first])) items")
            active_section_idx += 1 # active_section_idx = active_section_idx + 1
            if active_section_idx > length(rop_sections) # If statement to make comparison b/w rop_sections & active_section_idx
                debug(LOGGER, "finished reading known rop sections") 
                break
            end
            active_section = rop_sections[active_section_idx] 
            section_data[active_section.first] = []
            line_idx += 1
            continue
        end

        if active_section.first == "gen" # Checks if the first entity in active_section is gen.
            push!(section_data[active_section.first], _parse_rop_gen(line)) # Inserts _parse_rop_gen(line) into the section_data file
        elseif active_section.first == "disptbl" # Checks if the first entity in active_section is disptbl.
            push!(section_data[active_section.first], _parse_rop_pg(line)) # Inserts _parse_rop_gen(line) into the section_data file
        elseif active_section.first == "ctbl" # Checks if the first entity in active_section is ctbl.
            pwl_line_parts = split(line, ",") # Splits the line based on commas
            @assert length(pwl_line_parts) >= 3

            num_pwl_lines = parse(Int, pwl_line_parts[3])
            @assert num_pwl_lines > 0 # Assert macro allows the users to optionally specify their own error message, instead of just printing the failed expression

            pwl_point_lines = lines[line_idx+1:line_idx+num_pwl_lines]
            #pwl_point_lines = remove_comment.(pwl_point_lines)
            push!(section_data[active_section.first], _parse_rop_pwl(pwl_line_parts, pwl_point_lines)) # Inserts _parse_rop_pwl into the section_data file
            line_idx += num_pwl_lines # line_idx = line_idx + num_pwl_lines
        else
            info(LOGGER, "skipping data line: $(line)") # If none of the above statements satisfied the this info appears.
        end
        line_idx += 1 # line_idx = line_idx + 1
    end
    return section_data # Returns the content of section_data
end

@everywhere function _parse_rop_gen(line) # Calls the function named _parse_rop_gen
    line_parts = split(line, ",") # Splits the line based on comma
    @assert length(line_parts) >= 4 # Assert macro allows the users to optionally specify their own error message, instead of just printing the failed expression

    data = Dict(
        "bus"     => parse(Int, line_parts[1]),
        "genid"   => strip(line_parts[2]),
        "disp"    => strip(line_parts[3]),
        "disptbl" => parse(Int, line_parts[4]),
    )

    @assert data["disptbl"] >= 0 # Assert macro allows the users to optionally specify their own error message, instead of just printing the failed expression

    return data
end

@everywhere function _parse_rop_pg(line)
    line_parts = split(line, ",")
    @assert length(line_parts) >= 7

    data = Dict(
        "tbl"      => parse(Int, line_parts[1]),
        "pmax"     => strip(line_parts[2]),
        "pmin"     => strip(line_parts[3]),
        "fuelcost" => strip(line_parts[4]),
        "ctyp"     => strip(line_parts[5]),
        "status"   => strip(line_parts[6]),
        "ctbl"     => parse(Int, line_parts[7]),
    )

    @assert data["tbl"] >= 0
    @assert data["ctbl"] >= 0

    return data
end

@everywhere function _parse_rop_pwl(pwl_parts, point_lines)
    @assert length(pwl_parts) >= 2

    points = []

    for point_line in point_lines
        point_line_parts = split(point_line, ",") # Splits the point_line based on commas
        @assert length(point_line_parts) >= 2 # Assert macro allows to optionally specify our own error message, instead of just printing the failed expression
        x = parse(Float64, point_line_parts[1])
        y = parse(Float64, point_line_parts[2])

        push!(points, (x=x, y=y))
    end

    data = Dict(
        "ltbl"   =>  parse(Int, pwl_parts[1]),
        "label"  => strip(pwl_parts[2]),
        "points" => points
    )

    @assert data["ltbl"] >= 0

    return data
end





##### Contingency Description Data File (.con) #####

# OPEN BRANCH FROM BUS *I TO BUS *J CIRCUIT *1CKT
@everywhere branch_contigency_structure = [
    1 => "OPEN",
    2 => "BRANCH",
    3 => "FROM",
    4 => "BUS",
    #5 => "I",
    6 => "TO",
    7 => "BUS",
    #8 => "J",
    9 => "CIRCUIT",
    #10 => "CKT"
]

#=
# OPEN BRANCH FROM BUS *I TO BUS *J CIRCUIT *1CKT
@everywhere branch_contigency_structure_alt = [
    1 => "OPEN",
    2 => "BRANCH",
    3 => "FROM",
    4 => "BUS",
    #5 => "I",
    6 => "TO",
    7 => "BUS",
    #8 => "J",
    9 => "CKT",
    #10 => "CKT"
]
=#

# REMOVE UNIT *ID FROM BUS *I
# Generator contigency details
@everywhere generator_contigency_structure = [
    1 => "REMOVE",
    2 => "UNIT",
    #3 => "ID",
    4 => "FROM",
    5 => "BUS",
    #6 => "I"
]


@everywhere function parse_con_file(file::String) # Calls the parse_con_file
    open(file) do io # Open the file for read/write purposes
        return parse_con_file(io) # Returns the parsed file
    end
end

@everywhere function parse_con_file(io::IO) # Function that describe details regarding how to parse the contingency file
    con_lists = []

    tokens = []

    for line in readlines(io) # Reads from the io file
        #line_tokens = split(strip(remove_comment(line)))
        line_tokens = split(strip(line)) 
        #println(line_tokens)
        append!(tokens, line_tokens) # Inserts line_tokens at the end of tokens
    end

    #println(tokens)

    token_idx = 1
    while token_idx <= length(tokens) # Infinite loop until token_idx > length(tokens)
        token = tokens[token_idx] # Assigns tokens[token_idx] to token
        if token == "END"
            debug(LOGGER, "end of contingency file found") # Notify the end of contingency file
            break
        elseif token == "CONTINGENCY" # Checks if token is equal to CONTINGENCY
            # start reading contingencies

            contingency_name = tokens[token_idx+1] # Increments the token index to read the next contingency
            debug(LOGGER, "reading contingency $(contingency_name)") # Notify the contingency name

            token_idx += 2 # token_idx = token_idx + 2
            token = tokens[token_idx]
            remaining_tokens = length(tokens) - token_idx # Finds the remaining tokens

            if token == "OPEN" # branch contingency case
                # OPEN BRANCH FROM BUS *I TO BUS *J CIRCUIT *1CKT

                @assert remaining_tokens >= 9
                branch_tokens = tokens[token_idx:token_idx+9] # Informs how many tokens are there for a branch
                #println(branch_tokens)

                #if !all(branch_tokens[idx] == val for (idx, val) in branch_contigency_structure) && !all(branch_tokens[idx] == val for (idx, val) in branch_contigency_structure_alt)
                if any(branch_tokens[idx] != val for (idx, val) in branch_contigency_structure) # If there is contradiction b/w branch contingency structure and branch tokens
                    error(LOGGER, "incorrect branch contingency structure: $(branch_tokens)")
                end

                bus_i = parse(Int, branch_tokens[5])
                @assert bus_i >= 0

                bus_j = parse(Int, branch_tokens[8])
                @assert bus_j >= 0

                ckt = branch_tokens[10]

                branch_contingency = Dict(
                    "label" => contingency_name,
                    "component" => "branch",
                    "action" => "open",
                    "i" => bus_i,
                    "j" => bus_j,
                    "ckt" => ckt,
                )

                push!(con_lists, branch_contingency) # Inserts branch contingency in contingency list

                token_idx += 9 # token_idx = token_idx + 9
            elseif token == "REMOVE"
                # REMOVE UNIT *ID FROM BUS *I

                @assert remaining_tokens >= 5
                generator_tokens = tokens[token_idx:token_idx+5]
                #println(generator_tokens)

                if any(generator_tokens[idx] != val for (idx, val) in generator_contigency_structure) # checks if there is contradiction b/w  generator contingency structure and generator tokens
                    error(LOGGER, "incorrect generator contingency structure: $(generator_tokens)")
                end

                gen_id = generator_tokens[3]

                bus_i = parse(Int, generator_tokens[6])
                @assert bus_i >= 0

                generator_contingency = Dict(
                    "label" => contingency_name,
                    "component" => "generator",
                    "action" => "remove",
                    "id" => gen_id,
                    "i" => bus_i,
                )

                push!(con_lists, generator_contingency) # Inserts generator contingencies into the contingency list

                token_idx += 5 # token_idx = token_idx + 5
            elseif token == "END"
                warn(LOGGER, "no action provided for contingency $(contingency_name)") # If no action is mentioned in the file for a contingency
                token_idx -= 1
            else
                warn(LOGGER, "unrecognized token $(token)") # For unexpected tokens
            end

            token_idx += 1
            token = tokens[token_idx]
            if token != "END"
                error(LOGGER, "expected END token at end of CONTINGENCY, got $(token)")
            end
        else
            warn(LOGGER, "unrecognized token $(token)")
        end
        token_idx += 1
    end

    return con_lists
end




@everywhere function parse_solution1_file(file::String) # Calls function named parse_solution1_file
    open(file) do io # Opens the file for read/write operations
        return parse_solution1_file(io)
    end
end

@everywhere function parse_solution1_file(io::IO) # Function containing details how to parse the solutin1 file
    bus_data_list = []
    gen_data_list = []

    lines = readlines(io) # Reads the input

    # skip bus list header section
    idx = 1

    separator_count = 0
    skip_next = false

    while idx <= length(lines)
        line = lines[idx]
        if length(strip(line)) == 0
            warn(LOGGER, "skipping blank line in solution1 file ($(idx))")
        elseif skip_next
            skip_next = false
        elseif startswith(strip(line), "--")
            separator_count += 1
            skip_next = true
        else
            if separator_count == 1
                parts = split(line, ",")
                @assert length(parts) >= 4
                bus_data = (
                    bus = parse(Int, parts[1]),
                    vm = parse(Float64, parts[2]),
                    va = parse(Float64, parts[3]),
                    bcs = parse(Float64, parts[4])
                )
                push!(bus_data_list, bus_data) # Inserts bus data at the end of bus_data_list
            elseif separator_count == 2
                parts = split(line, ",")
                @assert length(parts) >= 4
                gen_data = (
                    bus = parse(Int, parts[1]),
                    id = strip(strip(parts[2]), ['\'', ' ']),
                    pg = parse(Float64, parts[3]),
                    qg = parse(Float64, parts[4])
                )
                push!(gen_data_list, gen_data) # Inserts the gen_data at the end of gen_data_list
            else
                warn(LOGGER, "skipping line in solution1 file ($(idx)): $(line)")
            end
        end
        idx += 1
    end

    return (bus=bus_data_list, gen=gen_data_list) # Returns bus and gen data
end


