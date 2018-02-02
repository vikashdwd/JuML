struct Covariate{T<:AbstractFloat} <: AbstractCovariate{T}
    name::String
    data::AbstractVector{T}
end

Base.length(covariate::AbstractCovariate{T}) where {T<:AbstractFloat} = length(covariate.data)

function Covariate(data::AbstractVector{T}) where {T<:AbstractFloat}
    Covariate{T}("", data)
end

function Covariate(name::String, data::AbstractVector{T}) where {T<:Integer}
    Covariate{Float32}(name, convert(Vector{Float32}, data))
end

function Covariate(data::AbstractVector{T}) where {T<:Integer}
    Covariate{Float32}("", convert(Vector{Float32}, data))
end

function slice(covariate::Covariate{T}, fromobs::Integer, toobs::Integer, slicelength::Integer) where {T<:AbstractFloat}
    slice(covariate.data, fromobs, toobs, slicelength)
end