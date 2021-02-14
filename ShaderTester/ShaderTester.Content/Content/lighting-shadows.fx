#if HLSL
#define NUM_LIGHTS 10
#else
#define NUM_LIGHTS 6
#endif

#define MAX_SHADOWS 4

float4x4 World;
float4x4 ViewProjection;

float4 MasterColor;

float4 GlowAmount;

Texture2D DiffuseTexture;
Texture2D NormalMap;
Texture2D SpecularMap;

// Only used by the shadow map construction shaders.
// Represents which light is active.
int ShadowMapLightIndex;

int LightCount;
int ShadowMapCount;

float3 AmbientLightColor;


// Light Types:
// 0 - point light
// 1 - directional light
float1 LightType[NUM_LIGHTS];
float3 LightPosition[NUM_LIGHTS];
float3 LightColor[NUM_LIGHTS];
float3 LightSpecularColor[NUM_LIGHTS];
float3 LightAttenuation[NUM_LIGHTS];
float4x4 LightViewProjection[NUM_LIGHTS];
float1 LightSpecularExponent[NUM_LIGHTS];

Texture2DArray ShadowMap;

sampler ShadowMapSampler = sampler_state { Texture = <ShadowMap>; MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = LINEAR; AddressU = CLAMP; AddressV = CLAMP; };

float1 SampleShadowMap(float2 p, uint index)
{
    // return ShadowMap.SampleCmpLevelZero( cmpSampler, input.lpos.xy, input.lpos.z );
    return ShadowMap.Sample(ShadowMapSampler, float3(p, index));
}

sampler texsampler = sampler_state
{
    Texture = <DiffuseTexture>;
};

sampler normalMapSampler = sampler_state
{
    Texture = <NormalMap>;
};

sampler specularMapSampler = sampler_state
{
    Texture = <SpecularMap>;
};

struct VertexShaderInput
{
    float4 Position : POSITION0;
    float4 Color : COLOR0;
    float2 TexCoords : TEXCOORD0;
};

struct VertexShaderOutput
{
    float4 Position : POSITION0;
    float4 Color : COLOR0;
    float2 TexCoords : TEXCOORD0;
    float4 WorldPos : TEXCOORD1;

    float4 LightPos[MAX_SHADOWS] : TEXCOORD2;
};

struct PS_RenderOutput
{
    float4 Color : SV_Target0;
    float4 Glow : SV_Target1;
};

struct VS_ShadowOutput
{
    float4 Position : POSITION0;
    float2 TexCoords : TEXCOORD0;
    float Depth : TEXCOORD1;
};


float3 ColorToVector(float3 color);
float3 VectorToColor(float3 v);


float3 SampleNormal(float2 texCoords)
{
    float3 result = NormalMap.Sample(normalMapSampler, texCoords);

    return ColorToVector(result);
}

////////////////////////////////////////////////////////////////////
//  Standard Vertex Shader
////////////////////////////////////////////////////////////////////

VertexShaderOutput vs_Render(VertexShaderInput input)
{
    VertexShaderOutput output;

    output.WorldPos = mul(input.Position, World);

    output.Position = mul(output.WorldPos, ViewProjection);
    output.TexCoords = input.TexCoords;

    output.Color = input.Color * MasterColor;

    for (int i = 0; i < MAX_SHADOWS; i++)
    {
        output.LightPos[i] = mul(output.WorldPos, LightViewProjection[i]);
    }

    return output;
}


////////////////////////////////////////////////////////////////////
//  Shadow Mapping Shaders
////////////////////////////////////////////////////////////////////

float4 GetPositionFromLight(float4 worldPosition, float lightIndex)
{
    return mul(worldPosition, LightViewProjection[lightIndex]);
}

float4 VectorToCamera(float4 worldPosition)
{
    return float4(0, 0, -1, 1);
}

// Renders shadows and specular highlights.
PS_RenderOutput ps_RenderWithShadowsSpecular(VertexShaderOutput input) : SV_Target0
{
    float4 texel = DiffuseTexture.Sample(texsampler, input.TexCoords);
    float3 normal = SampleNormal(input.TexCoords);
    float4 specTexel = SpecularMap.Sample(specularMapSampler, input.TexCoords);
    float3 diffuseColor = AmbientLightColor;
    float4 specularColor = float4(0, 0, 0, 0);
    PS_RenderOutput result;

    if (texel.a == 0)
    {
        discard;
    }

    [unroll] for (int i = 0; i < NUM_LIGHTS && i < LightCount; i++)
    {
        float1 attenuation;
        float1 normaldot;
        float3 lightDiffuseColor = LightColor[i];
        float3 lightDir;

        if (LightType[i] == 0)
        {
            float3 lightVector = LightPosition[i] - input.WorldPos;
            float lightDistance = length(lightVector);

            lightDir = normalize(lightVector);

            attenuation = 1 / (
                LightAttenuation[i].x
                + LightAttenuation[i].y * lightDistance
                + LightAttenuation[i].z * lightDistance * lightDistance);
            normaldot = saturate(dot(lightDir, normal));
        }
        else if (LightType[i] == 1)
        {
            lightDir = normalize(LightPosition[i]);
            attenuation = 1;
            normaldot = saturate(dot(lightDir, normal));
        }

        // Shadow calculations
        if (i < ShadowMapCount)
        {
            float4 lightingPosition = input.LightPos[i];  //GetPositionFromLight(input.WorldPos, i);

            float2 shadowTextureCoords =
                0.5 * lightingPosition.xy / lightingPosition.w + float2(0.5, 0.5);

            shadowTextureCoords.y = 1.0f - shadowTextureCoords.y;

            float shadowdepth = SampleShadowMap(shadowTextureCoords, i);

            float ourdepth = 1 - (lightingPosition.z / lightingPosition.w);

            // Check the shadowdepth against the depth of this pixel
            // a fudge factor is added to account for floating-point error
            if (shadowdepth - 0.02 > ourdepth)
            {
                // we're in shadow, cut the light
                attenuation = 0;
            };
        }

        diffuseColor += lightDiffuseColor * attenuation * normaldot;

        if (LightSpecularExponent[i] > 1)
        {
            // Phong relfection is ambient + light-diffuse + spec highlights.
            // I = Ia*ka*Oda + fatt*Ip[kd*Od(N.L) + ks(R.V)^n]
            // Ref: http://www.whisqu.se/per/docs/graphics8.htm
            // and http://en.wikipedia.org/wiki/Phong_shading
            // Get light direction for this fragment

            // Using Blinn half angle modification for performance over correctness
            float3 h = normalize(VectorToCamera(input.WorldPos) + lightDir);

            float specLighting = pow(saturate(dot(h, normal)), LightSpecularExponent[i]) * attenuation;

            specularColor += float4(specTexel.xyz * LightSpecularColor[i] * specLighting, 0);
            specularColor.a = specTexel.a;
        }
    }

    diffuseColor = saturate(diffuseColor) * texel.xyz * input.Color.xyz;

    float alpha = texel.a * input.Color.a;

    result.Color = float4(saturate(diffuseColor.xyz + specularColor.xyz), alpha);
    result.Glow = specularColor + (result.Color * GlowAmount);

    return result;
}

// Renders shadows without specular highlights.
float4 ps_RenderWithShadowsNoSpecular(VertexShaderOutput input) : SV_Target0
{
    float4 texel = DiffuseTexture.Sample(texsampler, input.TexCoords);
    float3 normal = SampleNormal(input.TexCoords);
    float3 resultColor = AmbientLightColor;

    [unroll] for (int i = 0; i < NUM_LIGHTS && i < LightCount; i++)
    {
        float3 lightVector = LightPosition[i] - input.WorldPos;
        float3 lightDir = normalize(lightVector);
        float3 lightDiffuse = LightColor[i];
        float lightDistance = length(lightVector);
        float attenuation = 1 / (
            LightAttenuation[i].x
            + LightAttenuation[i].y * lightDistance
            + LightAttenuation[i].z * lightDistance * lightDistance);
        float normaldot = saturate(dot(lightDir, normal));

        // Shadow calculations
        float4 lightingPosition = input.LightPos[i];  //GetPositionFromLight(input.WorldPos, i);

        float2 shadowTextureCoords =
            0.5 * lightingPosition.xy / lightingPosition.w + float2(0.5, 0.5);

        shadowTextureCoords.y = 1.0f - shadowTextureCoords.y;

        float shadowdepth = SampleShadowMap(shadowTextureCoords, i);

        float ourdepth = 1 - (lightingPosition.z / lightingPosition.w);

        // Check the shadowdepth against the depth of this pixel
        // a fudge factor is added to account for floating-point error
        if (shadowdepth - 0.02 > ourdepth)
        {
            // we're in shadow, cut the light
            attenuation = 0;
        };

        resultColor += lightDiffuse * attenuation * normaldot;
    }

    resultColor = saturate(resultColor);

    return float4(resultColor * texel.xyz * input.Color.xyz, texel.a * input.Color.a);
}

////////////////////////////////////////////////////////////////////
//  Lighting No Shadows
////////////////////////////////////////////////////////////////////


float4 ps_LightNoShadows(VertexShaderOutput input) : SV_Target0
{
    float4 texel = DiffuseTexture.Sample(texsampler, input.TexCoords);
    float3 normal = SampleNormal(input.TexCoords);
    float3 resultColor = AmbientLightColor;

    [unroll] for (uint i = 0; i < NUM_LIGHTS; i++)
    {
        float3 lightVector = LightPosition[i] - input.WorldPos;
        float3 lightDir = normalize(lightVector);
        float lightDistance = length(lightVector);
        float attenuation = 1 /
            (LightAttenuation[i].x
                + LightAttenuation[i].y * lightDistance
                + LightAttenuation[i].z * lightDistance * lightDistance);
        float normaldot = saturate(dot(lightDir, normal));

        resultColor += LightColor[i] * attenuation * normaldot;
    }

    resultColor = saturate(resultColor);

    return float4(resultColor * texel.xyz * input.Color.xyz, texel.a * input.Color.a);

}


////////////////////////////////////////////////////////////////////
//  No Lighting
////////////////////////////////////////////////////////////////////


float4 ps_NoLighting(VertexShaderOutput input) : SV_Target0
{
    return DiffuseTexture.Sample(texsampler, input.TexCoords) * input.Color;
}

///////////////////////////
//  Creating Shadow Maps
///////////////////////////

VS_ShadowOutput vs_CreateShadowMap(VertexShaderInput input)
{
    VS_ShadowOutput output;

    float4 posWorld = mul(input.Position, World);

    output.Position = mul(posWorld, LightViewProjection[ShadowMapLightIndex]);
    output.TexCoords = input.TexCoords;
    output.Depth.x = 1 - output.Position.z / output.Position.w;

    return output;
}

float4 ps_CreateShadowMap(VS_ShadowOutput input) : SV_Target0
{
    float4 texel = DiffuseTexture.Sample(texsampler, input.TexCoords);
    float depth = input.Depth.x;

    return float4(depth, depth, depth, texel.a);
}


////////////////////////////////////////////////////////////////////
//  DEBUG SHADERS
////////////////////////////////////////////////////////////////////

float4 DEBUG_ps_Normal(VertexShaderOutput input) : SV_Target0
{
    float4 texel = DiffuseTexture.Sample(texsampler, input.TexCoords);
    float3 normal = SampleNormal(input.TexCoords);
    float3 resultColor = AmbientLightColor;

    normal = VectorToColor(normal);

    return float4(normal, texel.a);
}

float4 DEBUG_ps_LightDir(VertexShaderOutput input) : SV_Target0
{
    float4 texel = DiffuseTexture.Sample(texsampler, input.TexCoords);
    float3 normal = SampleNormal(input.TexCoords);
    float3 resultColor = AmbientLightColor;
    float resultAlpha;

    [unroll] for (int i = 0; i < 1; i++)
    {
        float3 lightVector = LightPosition[i] - input.WorldPos;
        float3 lightDir = normalize(lightVector);
        float lightDistance = length(lightVector);
        float attenuation = 1 /
            (LightAttenuation[i].x
                + LightAttenuation[i].y * lightDistance
                + LightAttenuation[i].z * lightDistance * lightDistance);
        float normaldot = saturate(dot(lightDir, normal));

        resultColor = VectorToColor(lightDir);

        resultAlpha = texel.a * attenuation;
    }

    //resultColor = saturate(resultColor);

    return float4(resultColor, resultAlpha);
}

float4 DEBUG_ps_LightDistance(VertexShaderOutput input) : SV_Target0
{
    float4 texel = DiffuseTexture.Sample(texsampler, input.TexCoords);
    float3 normal = SampleNormal(input.TexCoords);
    float3 resultColor = AmbientLightColor;
    float resultAlpha;

    [unroll] for (int i = 0; i < 1; i++)
    {
        float3 lightVector = LightPosition[i] - input.WorldPos;
        float3 lightDir = normalize(lightVector);
        float lightDistance = length(lightVector);
        float attenuation = 1 /
            (LightAttenuation[i].x
                + LightAttenuation[i].y * lightDistance
                + LightAttenuation[i].z * lightDistance * lightDistance);

        return float4(attenuation, attenuation, attenuation, texel.a);
    }
    
    return float4(0, 0, 0, 0);
}

float4 DEBUG_ps_ShadowTexCoords(VertexShaderOutput input) : SV_Target0
{
    float4 texel = DiffuseTexture.Sample(texsampler, input.TexCoords);
    float3 normal = SampleNormal(input.TexCoords);
    float3 resultColor = AmbientLightColor;

    [unroll] for (int i = 0; i < NUM_LIGHTS; i++)
    {
        float3 lightVector = LightPosition[i] - input.WorldPos;
        float3 lightDir = normalize(lightVector);
        float3 lightDiffuse = LightColor[i];
        float lightDistance = length(lightVector);
        float attenuation = 1 /
            (LightAttenuation[i].x
                + LightAttenuation[i].y * lightDistance
                + LightAttenuation[i].z * lightDistance * lightDistance);
        float normaldot = saturate(dot(lightDir, normal));

        // Shadow calculations
        float4 lightingPosition = GetPositionFromLight(input.WorldPos, i);

        float2 shadowTextureCoords =
            0.5 * lightingPosition.xy / lightingPosition.w + float2(0.5, 0.5);

        shadowTextureCoords.y = 1.0f - shadowTextureCoords.y;

        //return float4(VectorToColor(shadowTextureCoords, ))
        float shadowdepth = SampleShadowMap(shadowTextureCoords, i).r;

        float ourdepth = 1 - (lightingPosition.z / lightingPosition.w);

        return float4(
            VectorToColor(float3(
                shadowTextureCoords.xy, shadowdepth)),
            texel.a
            );

        // Check the shadowdepth against the depth of this pixel
        // a fudge factor is added to account for floating-point error
        if (shadowdepth - 0.03 > ourdepth)
        {
            // we're in shadow, cut the light
            attenuation = 0;
        };

        resultColor += lightDiffuse * attenuation * normaldot;
    }

    resultColor = saturate(resultColor);

    return float4(resultColor * texel.xyz * input.Color.xyz, texel.a * input.Color.a);

}


//////////////////////////////////////////////////////////////////////////
//  Utility Functions
//////////////////////////////////////////////////////////////////////////

float3 ColorToVector(float3 color)
{
    color -= 0.5;
    color *= 2;
    color.y *= -1;
    color.z *= -1;

    return color;
}

float3 VectorToColor(float3 v)
{
    v.z *= -1;
    v /= 2;
    v += 0.5;

    return v;
}

//////////////////////////////////////////////////////////////////////////
//  Techniques
//////////////////////////////////////////////////////////////////////////

technique RenderWithShadowsAndSpecular
{
    pass Pass1
    {
        VertexShader = compile vs_5_0 vs_Render();
        PixelShader = compile ps_5_0 ps_RenderWithShadowsSpecular();
    }
}

technique RenderWithShadows
{
    pass Pass1
    {
        VertexShader = compile vs_5_0 vs_Render();
        PixelShader = compile ps_5_0 ps_RenderWithShadowsNoSpecular();
    }
}

technique ShadowMap
{
    pass Pass1
    {
        VertexShader = compile vs_5_0 vs_CreateShadowMap();
        PixelShader = compile ps_5_0 ps_CreateShadowMap();
    }
}


//////////////////////////////////////
//  No Shadows
//////////////////////////////////////
technique RenderLightNoShadows
{
    pass Pass1
    {
        VertexShader = compile vs_5_0 vs_Render();
        PixelShader = compile ps_5_0 ps_LightNoShadows();
    }
}

//////////////////////////////////////
//  No Lighting
//////////////////////////////////////
technique RenderNoLighting
{
    pass Pass1
    {
        VertexShader = compile vs_5_0 vs_Render();
        PixelShader = compile ps_5_0 ps_NoLighting();
    }
}

//////////////////////////////////////
//  Debug Shaders
//////////////////////////////////////

technique ShadowTexCoords
{
    pass Pass1
    {
        VertexShader = compile vs_5_0 vs_Render();
        PixelShader = compile ps_5_0 DEBUG_ps_ShadowTexCoords();
    }
}

technique DebugNormal
{
    pass Pass1
    {
        VertexShader = compile vs_5_0 vs_Render();
        PixelShader = compile ps_5_0 DEBUG_ps_Normal();
    }
}

technique DebugLightDistance
{
    pass Pass1
    {
        VertexShader = compile vs_5_0 vs_Render();
        PixelShader = compile ps_5_0 DEBUG_ps_LightDistance();
    }
}

technique DebugLightDir
{
    pass Pass1
    {
        VertexShader = compile vs_5_0 vs_Render();
        PixelShader = compile ps_5_0 DEBUG_ps_LightDir();
    }
}


// Reference material:


// Phong reflection is ambient + light-diffuse + spec highlights.
// I = Ia*ka*Oda + fatt*Ip[kd*Od(N.L) + ks(R.V)^n]
// Ref: http://www.whisqu.se/per/docs/graphics8.htm
// and http://en.wikipedia.org/wiki/Phong_shading

// Get light direction for this fragment
//float3 lightDir = normalize(input.WorldPos - LightPosition); // per pixel diffuse lighting

// Note: Non-uniform scaling not supported
//float diffuseLighting = saturate(dot(input.Normal, -lightDir));

// Introduce fall-off of light intensity
//diffuseLighting *= (LightDistanceSquared / dot(LightPosition - input.WorldPos, LightPosition - input.WorldPos));

// Using Blinn half angle modification for perofrmance over correctness
//float3 h = normalize(normalize(CameraPos - input.WorldPos) - lightDir);
//float specLighting = pow(saturate(dot(h, input.Normal)), SpecularPower);

//return float4(saturate(
//	AmbientLightColor +
//	(texel.xyz * DiffuseColor * LightDiffuseColor * diffuseLighting * 0.6) + // Use light diffuse vector as intensity multiplier
//	(SpecularColor * LightSpecularColor * specLighting * 0.5) // Use light specular vector as intensity multiplier
//	), texel.w);


