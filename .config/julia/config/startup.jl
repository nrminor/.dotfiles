#!/usr/bin/env -S julia --threads auto --color=yes --gcthreads 3 --compile=all

module Startup

try using PrecompileTools
    catch _ using Pkg && Pkg.add("PrecompileTools")
end

@setup_workload begin
    @compile_workload begin

        @eval using Chairmarks
        @eval using LanguageServer
        @eval using Plots
        @eval using Preferences

        atreplinit() do repl
            try
                @eval using Pkg
                @eval using OhMyREPL
                @eval using Revise
                @eval using JuliaFormatter
                @eval using JET
            catch e
                @warn "error while importing OhMyREPL, Revise, Julia Formatter, or JET:" e
            end
        end
    end
end


try using OhMyREPL, Revise, JuliaFormatter finally using Pkg end

end

