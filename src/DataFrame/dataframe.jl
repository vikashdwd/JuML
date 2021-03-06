import JSON

abstract type AbstractDataFrame end

abstract type StatVariate end

abstract type AbstractFactor{T<:Unsigned} <: StatVariate end

abstract type AbstractCovariate{T<:AbstractFloat} <: StatVariate end

abstract type AbstractBoolVariate <: StatVariate end

struct DataFrame <: AbstractDataFrame
    length::Int64
    factors::AbstractVector{<:AbstractFactor}
    covariates::AbstractVector{<:AbstractCovariate}
    boolvariates::AbstractVector{<:AbstractBoolVariate}
end

mutable struct CovariateStats
    obscount::Int64
    nancount::Int64
    nanpcnt::Float64
    sum::Float64
    sum2::Float64
    mean::Float64
    std::Float64
    min::Float64
    max::Float64
end

mutable struct LevelStats
    level::String
    freq::Int64
    freqpcnt::Float64
end

mutable struct FactorStats
    obscount::Int64
    missingfreq::Int64
    missingpcnt::Float64
    levelstats::Vector{LevelStats}
end

function Base.length(dataframe::AbstractDataFrame)
    dataframe.length
end

getlevels(factor::AbstractFactor{T}) where {T<:Unsigned} = factor.levels

getname(factor::AbstractFactor{T}) where {T<:Unsigned} = factor.name

getname(covariate::AbstractCovariate{T}) where {T<:AbstractFloat} = covariate.name

getname(boolvar::AbstractBoolVariate) = boolvar.name

function widenfactors(factors::Vector{<:AbstractFactor})
    if all(map((factor -> issubtype(typeof(factor), AbstractFactor{UInt8})), factors))
        factors
    elseif all(map((factor -> issubtype(typeof(factor), AbstractFactor{UInt8}) || issubtype(typeof(factor), AbstractFactor{UInt16})), factors))
        [issubtype(typeof(factor), AbstractFactor{UInt16}) ? factor : WiderFactor{UInt8, UInt16}(factor) for factor in factors]
    else
        [issubtype(typeof(factor), AbstractFactor{UInt32}) ? factor : (issubtype(typeof(factor), AbstractFactor{UInt16}) ? WiderFactor{UInt16, UInt32}(factor) : WiderFactor{UInt8, UInt32}(factor)) for factor in factors]
    end
end

function DataFrame(path::String; preload::Bool = true)
    path = abspath(path)
    headerpath = isfile(path) ? path : joinpath(path, "header.txt")
    headerjson = open(headerpath) do f 
        readstring(f)
    end
    header = JSON.parse(headerjson)
    factors = Vector{AbstractFactor}()
    covariates = Vector{AbstractCovariate}()
    datacols = header["datacolumns"]
    len = 0
    for datacol in datacols
        datatype = datacol["datatype"]
        len = datacol["length"]
        name = datacol["name"]
        datpath = joinpath(dirname(headerpath), datacol["filename"])

        if datatype == "Float32"
            if preload
                push!(covariates, Covariate{Float32}(name, len, datpath))
            else
                push!(covariates, FileCovariate{Float32}(name, len, datpath))
            end
        end

        if datatype == "UInt8"
            levels = [string(level) for level in datacol["levels"]]
            if length(levels) == 0
                levels = Vector{String}()
            end
            if preload
                push!(factors, Factor{UInt8}(name, len, levels, datpath)) 
            else
                push!(factors, FileFactor{UInt8}(name, len, levels, datpath)) 
            end
        end

        if datatype == "UInt16"
            levels = [string(level) for level in datacol["levels"]]
            if length(levels) == 0
                levels = Vector{String}()
            end
            if preload
                push!(factors, Factor{UInt16}(name, len, levels, datpath))  
            else
                push!(factors, FileFactor{UInt16}(name, len, levels, datpath))   
            end
        end

        if datatype == "UInt32"
            levels = [string(level) for level in datacol["levels"]]
            if length(levels) == 0
                levels = Vector{String}()
            end
            if preload
                push!(factors, Factor{UInt32}(name, len, levels, datpath))  
            else
                push!(factors, FileFactor{UInt32}(name, len, levels, datpath))   
            end       
        end
    end
    DataFrame(len, factors, covariates, AbstractBoolVariate[])
end

function Base.getindex(df::AbstractDataFrame, name::String)
    for factor in df.factors
        if getname(factor) == name
            return factor
        end
    end
    for cov in df.covariates
        if getname(cov) == name
            return cov
        end
    end
end

function Base.summary(factor::AbstractFactor{T}) where {T<:Unsigned}
    io = IOBuffer()
    factorstats = getstats(factor)
    println(io, @sprintf("%-16s%15d", "Obs Count", factorstats.obscount))
    println(io, @sprintf("%-16s%15s%15s", "Level", "Frequency", "Frequency(%)"))
    println(io, @sprintf("%-16s%15d%15G", MISSINGLEVEL, factorstats.missingfreq, factorstats.missingpcnt))
    for levelstats in factorstats.levelstats
        println(io, @sprintf("%-16s%15d%15G", levelstats.level, levelstats.freq, levelstats.freqpcnt))
    end
    print(String(take!(io)))
end

function Base.summary(boolvar::AbstractBoolVariate)
    io = IOBuffer()
    len = length(boolvar)
    slices = slice(factor, 1, len, SLICELENGTH)
    truefreq = fold(0, slices) do acc, slice
        res = acc
        for v in slice
            if v    
                res += 1
            end
        end
        res
    end
    println(io, @sprintf("%-15s%12d", "Obs Count", len))
    println(io, @sprintf("%-15s%12d", "True Freq", truefreq))
    println(io, @sprintf("%-15s%12G", "True Freq (%)", 100.0 * truefreq / len))
    print(String(take!(io)))
end

function getstats(factor::AbstractFactor{T}) where {T<:Unsigned}
    len = length(factor)
    levels = getlevels(factor)
    levelcount = length(levels)
    init = zeros(Int64, levelcount + 1)
    slices = slice(factor, 1, len, SLICELENGTH)
    freq = fold(init, slices) do frq, slice
        for levelindex in slice
            frq[levelindex + 1] += 1 
        end
        frq
    end
    missingfreq = freq[1]
    missingpcnt = 100.0 * missingfreq / len
    levelstats = [LevelStats(levels[i], freq[i + 1], 100.0 * freq[i + 1] / len) for i in 1:levelcount]  
    FactorStats(len, missingfreq, missingpcnt, levelstats)
end

function getstats(covariate::AbstractCovariate{T}) where {T<:AbstractFloat}
    len = length(covariate)
    init = CovariateStats(0, 0, NaN64, NaN64, NaN64, NaN64, NaN64, NaN64, NaN64)
    slices = slice(covariate, 1, len, SLICELENGTH)
    stats = fold(init, slices) do s, slice
        for v in slice
            if isnan(v)
                s.nancount += 1
            else
                if isnan(s.sum)
                    s.sum = v
                    s.sum2 = v * v
                    s.min = v
                    s.max = v
                else
                    s.sum += v
                    s.sum2 += v * v
                    if v < s.min
                        s.min = v
                    end
                    if v > s.max
                        s.max = v
                    end
                end
            end
        end
        s
    end
    stats.obscount = len
    stats.nanpcnt = 100.0 * stats.nancount / len
    stats.mean = stats.sum / (len - stats.nancount)
    stats.std = sqrt(((stats.sum2 - stats.sum * stats.sum / (len - stats.nancount)) / (len - stats.nancount - 1)))
    stats
end

function Base.summary(covariate::AbstractCovariate{T}) where {T<:AbstractFloat}
    io = IOBuffer()
    stats = getstats(covariate)
    println(io, @sprintf("%-15s%12d", "Obs Count", stats.obscount))
    println(io, @sprintf("%-15s%12d", "NaN Freq", stats.nancount))
    println(io, @sprintf("%-15s%12G", "NaN %", stats.nanpcnt))
    println(io, @sprintf("%-15s%12G", "Min", stats.min))
    println(io, @sprintf("%-15s%12G", "Max", stats.max))
    println(io, @sprintf("%-15s%12G", "Mean", stats.mean))
    println(io, @sprintf("%-15s%12G", "Std", stats.std))
    print(String(take!(io)))
end

function Base.show(io::IO, covariate::AbstractCovariate{T}) where {T<:AbstractFloat}
    slices = slice(covariate, 1, HEADLENGTH, HEADLENGTH)
    slice1, _ = tryread(slices)
    len = length(covariate)
    if !isnull(slice1)
        datahead = join([isnan(v) ? "." : string(v) for v in get(slice1)], " ")
        dataend = len > HEADLENGTH ? "  ..." : ""
        println(io, "Covariate $(getname(covariate)) with $(len) obs: $(datahead)$dataend")
    else
        println(io, "Covariate $(getname(covariate)) with $(len) obs")
    end
end

function Base.show(io::IO, boolvar::AbstractBoolVariate) 
    slices = slice(boolvar, 1, HEADLENGTH, HEADLENGTH)
    slice1, _ = tryread(slices)
    len = length(boolvar)
    if !isnull(slice1)
        datahead = join([string(v) for v in get(slice1)], " ")
        dataend = len > HEADLENGTH ? "  ..." : ""
        println(io, "BoolVar $(getname(boolvar)) with $(len) obs: $(datahead)$dataend")
    else
        println(io, "BoolVar $(getname(boolvar)) with $(len) obs")
    end
end

function Base.show(io::IO, factor::AbstractFactor{T}) where {T<:Unsigned}
    slices = slice(factor, 1, HEADLENGTH, HEADLENGTH)
    slice1, _ = tryread(slices)
    len = length(factor)
    levels = getlevels(factor)
    levelcount = length(levels)
    if !isnull(slice1)
        datahead = join([index == 0 ? MISSINGLEVEL : levels[index] for index in get(slice1)], " ")
        dataend = len > HEADLENGTH ? "  ..." : ""
        println(io, "Factor $(getname(factor)) with $(len) obs and $(levelcount) levels: $(datahead)$dataend")
    else
        println(io, "Factor $(getname(factor)) with $(len) obs and $(levelcount) levels")
    end
end

function Base.convert(::Type{Vector{T}}, covariate::AbstractCovariate{T}) where {T<:AbstractFloat}
    v, _ = tryread(slice(covariate, 1, length(covariate), length(covariate)))
    get(v)
end

function isordinal(factor::AbstractFactor{T}) where {T<:Unsigned}
    false
 end

