//
// Copyright (c) 2021, NVIDIA CORPORATION. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
//  * Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
//  * Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
//  * Neither the name of NVIDIA CORPORATION nor the names of its
//    contributors may be used to endorse or promote products derived
//    from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
// CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
// EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
// PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
// OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#pragma once

#include <optix.h>
#include <cuda/random.h>
#include <cuda/helpers.h>
#include <sutil/vec_math.h>

// #include <float.h>

__device__
inline void CoordinateSystem(const float3& a, float3& b, float3& c) {
    
//    if (abs(a.x) > abs(a.y))
//        b = float3(-a.z, 0, a.x) /
//              sqrt(max(FLT_EPSILON, a.x * a.x + a.z * a.z));
//    else
//        b = float3(0, a.z, -a.y) /
//              sqrt(max(FLT_EPSILON, a.y * a.y + a.z * a.z));
    
    if (abs(a.x) > abs(a.y))
        b = float3{-a.z, 0, a.x};
    else
        b = float3{0, a.z, -a.y};
    
    b = normalize(b);
    c = cross(a, b);
}

inline float3 SphericalDirection(float sinTheta, float cosTheta, float phi) {
    return float3{sinTheta * cosf(phi), sinTheta * sinf(phi), cosTheta};
}

inline float3 SphericalDirection(float sinTheta, float cosTheta, float phi,
                                 const float3 &x, const float3 &y, const float3 &z) {
    return sinTheta * cos(phi) * x + sinTheta * sin(phi) * y + cosTheta * z;
}

struct HenyeyGreenstein {
    float g;
    __device__ HenyeyGreenstein(float g) : g(g) {}
    
    float p(const float3 &wo, const float3 &wi) const;
    float Sample_p(const float3 &wo, float3 &wi, const float2 &uu) const;
};

// Media Inline Functions
inline float PhaseHG(float cosTheta, float g) {
    float gg = g * g;
    float denom = 1 + gg + 2 * g * cosTheta;
    return (0.25 / M_PIf) * (1 - gg) / (denom * sqrt(denom));
}

// HenyeyGreenstein Method Definitions
inline float HenyeyGreenstein::p(const float3 &wo, const float3 &wi) const {
    //ProfilePhase _(Prof::PhaseFuncEvaluation);
    return PhaseHG(dot(wo, wi), g);
}

inline float HenyeyGreenstein::Sample_p(const float3 &wo, float3 &wi, const float2 &uu) const {
    // Compute $\cos \theta$ for Henyey--Greenstein sample
    float cosTheta;
    if (abs(g) < 1e-3)
        cosTheta = 1 - 2 * uu.x;
    else {
        float gg = g * g;
        float sqrTerm = (1 - gg) / (1 + g - 2 * g * uu.x);
        cosTheta = -(1 + gg - sqrTerm * sqrTerm) / (2 * g);
    }

    // Compute direction _wi_ for Henyey--Greenstein sample
    float sinTheta = sqrt(fmax(0.0f, 1.0f - cosTheta * cosTheta));
    float phi = 2 * M_PIf * uu.y;
    
    float3 v1, v2;
    CoordinateSystem(wo, v1, v2);
    wi = SphericalDirection(sinTheta, cosTheta, phi, v1, v2, wo);

    return PhaseHG(cosTheta, g);
}

#ifndef M_PI
    #define M_PI 3.14159265358979323846
#endif

static uint32_t waveLength[] = {645, 510, 440}; // RGB

class RayleighPhaseFunction {
 
    inline float cuberoot(float x) const {
        return (x < 0.0f) ?
            -pow(-x, (float) (1.0f/3.0f)) 
            : pow(x, (float) (1.0f/3.0f));
    }

    float3 lambda3_transmitance(float3 lambda, float height) {
        return float3 {
            lambda_transmitance(waveLength[0], height),
            lambda_transmitance(waveLength[1], height),
            lambda_transmitance(waveLength[2], height),
        };
    }

    float lambda_transmitance(float lambda, float height) {
        float eta = 1.1;

        float tmp = eta * eta - 1;
        float rho = exp(-height/7794.0f);

        float N_s = 1;
        float K = 2 * M_PI * M_PI * tmp * tmp / (3 * N_s);

        float pre = K * rho;
        // K * 4 * M_PI * rho;

        float lambda2 = lambda * lambda;
        return pre / (lambda2 * lambda2);
    }

    inline float sample(const float3& wo, float3& wi, float2& uu) const {
        float2 sample = uu;

        float z = 2 * (2*sample.x - 1),
              tmp = sqrt(z*z+1),
              A = cuberoot(z+tmp),
              B = cuberoot(z-tmp),
              cosTheta = A + B,
              sinTheta = sqrtf(fmaxf(1.0f-cosTheta*cosTheta, 1e-16)),
              phi = 2*M_PI*sample.y,
              cosPhi = std::cos(phi),
              sinPhi = std::sin(phi);

        float3 dir{
            sinTheta * cosPhi,
            sinTheta * sinPhi,
            cosTheta
        };

        float3 v1, v2;
        CoordinateSystem(wo, v1, v2);
        wi = SphericalDirection(sinTheta, cosTheta, phi, v1, v2, wo);

        return 1.0f;
    }

    float sample_p(const float3& wo, float3& wi, float2& uu) const {
        RayleighPhaseFunction::sample(wo, wi, uu);
        //pdf = RayleighPhaseFunction::p(wo, wi);
        return 1.0f;
    }

    inline float p(const float3 &wo, const float3 &wi) const {
        float mu = dot(wo, wi);
        return (3.0f/(16.0f*M_PI)) * (1+mu*mu);
    }
};
