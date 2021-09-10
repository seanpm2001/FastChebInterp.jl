# evaluation of multidimensional Chebyshev polynomials
# (using Clenshaw recurrences) and their derivatives.

"""
    interpolate(x, c::Array{T,N}, ::Val{dim}, i1, len)

Low-level interpolation function, which performs a
multidimensional Clenshaw recurrence by recursing on
the coefficient (`c`) array dimension `dim` (from `N` to `1`).   The
current dimension (via column-major order) is accessed
by `c[i1 + (i-1)*Δi]`, i.e. `i1` is the starting index and
`Δi = len ÷ size(c,dim)` is the stride.   `len` is the
product of `size(c)[1:dim]`. The interpolation point `x`
should lie within [-1,+1] in each coordinate.
"""
@fastmath function interpolate(x::SVector{N}, c::Array{<:Any,N}, ::Val{dim}, i1, len) where {N,dim}
    n = size(c,dim)
    @inbounds xd = x[dim]
    if dim == 1
        c₁ = c[i1]
        if n ≤ 2
            n == 1 && return c₁ + one(xd) * zero(c₁)
            return muladd(xd, c[i1], c₁)
        end
        @inbounds bₖ = muladd(2xd, c[i1+(n-1)], c[i1+(n-2)])
        @inbounds bₖ₊₁ = oftype(bₖ, c[i1+(n-1)])
        for j = n-3:-1:1
            @inbounds bⱼ = muladd(2xd, bₖ, c[i1+j]) - bₖ₊₁
            bₖ, bₖ₊₁ = bⱼ, bₖ
        end
        return muladd(xd, bₖ, c₁) - bₖ₊₁
    else
        Δi = len ÷ n # column-major stride of current dimension

        # we recurse downward on dim for cache locality,
        # since earlier dimensions are contiguous
        dim′ = Val{dim-1}()

        c₁ = interpolate(x, c, dim′, i1, Δi)
        if n ≤ 2
            n == 1 && return c₁ + one(xd) * zero(c₁)
            c₂ = interpolate(x, c, dim′, i1+Δi, Δi)
            return c₁ + xd*c₂
        end
        cₙ₋₁ = interpolate(x, c, dim′, i1+(n-2)*Δi, Δi)
        cₙ = interpolate(x, c, dim′, i1+(n-1)*Δi, Δi)
        bₖ = muladd(2xd, cₙ, cₙ₋₁)
        bₖ₊₁ = oftype(bₖ, cₙ)
        for j = n-3:-1:1
            cⱼ = interpolate(x, c, dim′, i1+j*Δi, Δi)
            bⱼ = muladd(2xd, bₖ, cⱼ) - bₖ₊₁
            bₖ, bₖ₊₁ = bⱼ, bₖ
        end
        return muladd(xd, bₖ, c₁) - bₖ₊₁
    end
end

"""
    (interp::ChebPoly)(x)

Evaluate the Chebyshev polynomial given by `interp` at the point `x`.
"""
@fastmath function (interp::ChebPoly{N})(x::SVector{N,<:Real}) where {N}
    x0 = @. (x - interp.lb) * 2 / (interp.ub - interp.lb) - 1
    all(abs.(x0) .≤ 1) || throw(ArgumentError("$x not in domain"))
    return interpolate(x0, interp.coefs, Val{N}(), 1, length(interp.coefs))
end

(interp::ChebPoly{N})(x::AbstractVector{<:Real}) where {N} = interp(SVector{N}(x))
(interp::ChebPoly{1})(x::Real) = interp(SVector{1}(x))


"""
    Jinterpolate(x, c::Array{T,N}, ::Val{dim}, i1, len)

Similar to `interpolate` above, but returns a tuple `(v,J)` of the
interpolated value `v` and the Jacobian `J` with respect to `x[1:dim]`.
"""
@fastmath function Jinterpolate(x::SVector{N}, c::Array{<:Any,N}, ::Val{dim}, i1, len) where {N,dim}
    n = size(c,dim)
    @inbounds xd = x[dim]
    if dim == 1
        c₁ = c[i1]
        if n ≤ 2
            n == 1 && return c₁ + one(xd) * zero(c₁), hcat(SVector(zero(c₁) / oneunit(xd)))
            return muladd(xd, c[i1], c₁), hcat(SVector(c[i1]))
        end
        @inbounds cₙ₋₁ = c[i1+(n-2)]
        @inbounds cₙ = c[i1+(n-1)]
        bₖ′ = 2cₙ
        bₖ = muladd(xd, bₖ′, cₙ₋₁)
        bₖ₊₁ = oftype(bₖ, cₙ)
        bₖ₊₁′ = zero(bₖ₊₁)
        for j = n-3:-1:1
            @inbounds cⱼ = c[i1+j]
            bⱼ = muladd(2xd, bₖ, cⱼ) - bₖ₊₁
            bⱼ′ = muladd(2xd, bₖ′, 2bₖ) - bₖ₊₁′
            bₖ, bₖ₊₁ = bⱼ, bₖ
            bₖ′, bₖ₊₁′ = bⱼ′, bₖ′
        end
        return muladd(xd, bₖ, c₁) - bₖ₊₁, hcat(SVector(muladd(xd, bₖ′, bₖ) - bₖ₊₁′))
    else
        Δi = len ÷ n # column-major stride of current dimension

        # we recurse downward on dim for cache locality,
        # since earlier dimensions are contiguous
        dim′ = Val{dim-1}()

        c₁,Jc₁ = Jinterpolate(x, c, dim′, i1, Δi)
        if n ≤ 2
            n == 1 && return c₁ + one(xd) * zero(c₁), hcat(Jc₁, SVector(zero(c₁) / oneunit(xd)))
            c₂,Jc₂ = Jinterpolate(x, c, dim′, i1+Δi, Δi)
            return muladd(xd, c₂, c₁), hcat(muladd(xd, Jc₂, Jc₁), SVector(c[i1]))
        end
        cₙ₋₁,Jcₙ₋₁ = Jinterpolate(x, c, dim′, i1+(n-2)*Δi, Δi)
        cₙ,Jcₙ = Jinterpolate(x, c, dim′, i1+(n-1)*Δi, Δi)
        bₖ′ = 2cₙ
        bₖ = muladd(xd, bₖ′, cₙ₋₁)
        Jbₖ = muladd(2xd, Jcₙ, Jcₙ₋₁)
        bₖ₊₁ = oftype(bₖ, cₙ)
        bₖ₊₁′ = zero(bₖ₊₁)
        Jbₖ₊₁ = oftype(Jbₖ, Jcₙ)
        for j = n-3:-1:1
            cⱼ,Jcⱼ = Jinterpolate(x, c, dim′, i1+j*Δi, Δi)
            bⱼ = muladd(2xd, bₖ, cⱼ) - bₖ₊₁
            bⱼ′ = muladd(2xd, bₖ′, 2bₖ) - bₖ₊₁′
            Jbⱼ = muladd(2xd, Jbₖ, Jcⱼ) - Jbₖ₊₁
            bₖ, bₖ₊₁ = bⱼ, bₖ
            bₖ′, bₖ₊₁′ = bⱼ′, bₖ′
            Jbₖ, Jbₖ₊₁ = Jbⱼ, Jbₖ
        end
        return muladd(xd, bₖ, c₁) - bₖ₊₁, hcat(muladd(xd, Jbₖ, Jc₁) - Jbₖ₊₁, SVector(muladd(xd, bₖ′, bₖ) - bₖ₊₁′))
    end
end


"""
    chebjacobian(c::ChebPoly, x)

Return a tuple `(v, J)` where `v` is the value `c(x)` of the Chebyshev
polynomial `c` at `x`, and `J` is the Jacobian of this value with respect to `x`.

That is, if `v` is a vector, then `J` is a matrix of `length(v)` × `length(x)`
giving the derivatives of each component.  If `v` is a scalar, then `J`
is a 1-row matrix; in this case you may wish to call `chebgradient` instead.
"""
function chebjacobian(c::ChebPoly{N}, x::SVector{N,<:Real}) where {N}
    x0 = @. (x - c.lb) * 2 / (c.ub - c.lb) - 1
    all(abs.(x0) .≤ 1) || throw(ArgumentError("$x not in domain"))
    v, J = Jinterpolate(x0, c.coefs, Val{N}(), 1, length(c.coefs))
    return v, J .* 2 ./ (c.ub .- c.lb)'
end

chebjacobian(c::ChebPoly{N}, x::AbstractVector{<:Real}) where {N} = chebjacobian(c, SVector{N}(x))
chebjacobian(c::ChebPoly{1}, x::Real) = chebjacobian(c, SVector{1}(x))

"""
    chebgradient(c::ChebPoly, x)

Return a tuple `(v, ∇v)` where `v` is the value `c(x)` of the Chebyshev
polynomial `c` at `x`, and `∇v` is the gradient of this value with respect to `x`.

(Requires `c` to be a scalar-valued polynomial; if `c` is vector-valued, you
should use `chebjacobian` instead.)

If `x` is a scalar, returns a scalar `∇v`, i.e. `(v, ∂v/∂x).
"""
function chebgradient(c::ChebPoly, x)
    v, J = chebjacobian(c, x)
    length(v) == 1 || throw(DimensionMismatch())
    return v, vec(J)
end

function chebgradient(c::ChebPoly{1}, x::Real)
    v, ∇v = chebgradient(c, SVector{1}(x))
    return v, ∇v[1]
end
