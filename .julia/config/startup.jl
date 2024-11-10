#!/usr/bin/env -S julia --threads auto --color=yes --gcthreads 3 --compile=all

module Startup

using PrecompileTools

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
                @eval using DataToolkit
            catch e
                @warn "error while importing OhMyREPL, Revise, Julia Formatter, or JET:" e
            end
        end
    end
end

end
