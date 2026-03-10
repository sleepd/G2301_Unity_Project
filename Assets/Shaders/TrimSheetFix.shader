Shader "Custom/TrimSheet_HDRP_Fix"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1,1,1,1)
        [MainTexture] _BaseColorMap("BaseColor Map", 2D) = "white" {}

        [Normal] _NormalMap("Normal Map", 2D) = "bump" {}
        _NormalScale("Normal Scale", Range(0, 2)) = 1.0

        _Metallic("Metallic", Range(0, 1)) = 0.0
        _Smoothness("Smoothness", Range(0, 1)) = 0.35
        _SpecularStrength("Specular Strength", Range(0, 1)) = 0.25
        _DirectLightStrength("Direct Light Strength", Range(0, 4)) = 1.0

        _WrapBias("Wrap Bias (Fix Black Edge)", Range(0, 0.5)) = 0.1
        _AmbientStrength("Ambient Strength", Range(0, 0.5)) = 0.05
    }

    SubShader
    {
        Tags { "RenderPipeline"="HDRenderPipeline" "RenderType"="Opaque" }

        Pass
        {
            Name "ForwardOnly"
            Tags { "LightMode"="ForwardOnly" }

            Blend One Zero
            ZWrite On
            ZTest LEqual
            Cull Back

            HLSLPROGRAM
            #pragma target 4.5
            #pragma only_renderers d3d11 playstation xboxone xboxseries vulkan metal switch
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON
            #pragma multi_compile_fragment _ DEBUG_DISPLAY

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/ShaderVariables.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"

            struct Attributes
            {
                float3 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float2 uv0 : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float3 tangentWS : TEXCOORD3;
                float3 bitangentWS : TEXCOORD4;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseColorMap_ST;
                float4 _NormalMap_ST;
                float _NormalScale;
                float _Metallic;
                float _Smoothness;
                float _SpecularStrength;
                float _DirectLightStrength;
                float _WrapBias;
                float _AmbientStrength;
            CBUFFER_END

            TEXTURE2D(_BaseColorMap);
            SAMPLER(sampler_BaseColorMap);
            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            Varyings Vert(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                float3 positionWS = TransformObjectToWorld(input.positionOS);
                output.positionCS = TransformWorldToHClip(positionWS);
                output.positionWS = positionWS;
                output.uv0 = input.uv;

                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                float3 tangentWS = TransformObjectToWorldDir(input.tangentOS.xyz);
                tangentWS = normalize(tangentWS);
                normalWS = normalize(normalWS);
                float3 bitangentWS = normalize(cross(normalWS, tangentWS) * input.tangentOS.w);

                output.normalWS = normalWS;
                output.tangentWS = tangentWS;
                output.bitangentWS = bitangentWS;
                return output;
            }

            float4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);

                float2 baseUV = TRANSFORM_TEX(input.uv0, _BaseColorMap);
                float2 normalUV = TRANSFORM_TEX(input.uv0, _NormalMap);
                float3 normalTS = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, normalUV).xyz * 2.0 - 1.0;
                normalTS.xy *= _NormalScale;
                normalTS.z = sqrt(saturate(1.0 - dot(normalTS.xy, normalTS.xy)));

                float3 normalWS = normalize(
                    normalTS.x * input.tangentWS +
                    normalTS.y * input.bitangentWS +
                    normalTS.z * input.normalWS
                );

                float3 lightDirWS = float3(0.0, 1.0, 0.0);
                float3 lightColor = float3(1.0, 1.0, 1.0);

                if (_DirectionalShadowIndex >= 0)
                {
                    DirectionalLightData mainLight = _DirectionalLightDatas[_DirectionalShadowIndex];
                    lightDirWS = -mainLight.forward.xyz;
                    // HDRP light color can carry very large HDR intensity; keep tint but normalize energy here.
                    lightColor = normalize(max(mainLight.color.xyz, 1e-4.xxx));
                }

                float rawNdotL = dot(normalWS, normalize(lightDirWS));
                float wrappedNdotL = saturate((rawNdotL + _WrapBias) / (1.0 + _WrapBias));

                float3 albedo = SAMPLE_TEXTURE2D(_BaseColorMap, sampler_BaseColorMap, baseUV).rgb * _BaseColor.rgb;
                float3 ambient = _AmbientStrength.xxx;

                float3 V = normalize(GetWorldSpaceViewDir(input.positionWS));
                float3 L = normalize(lightDirWS);
                float3 H = normalize(L + V);

                float ndoth = saturate(dot(normalWS, H));
                float specPower = exp2(2.0 + _Smoothness * 10.0);
                float specTerm = pow(ndoth, specPower);

                float3 dielectricF0 = float3(0.04, 0.04, 0.04);
                float3 f0 = lerp(dielectricF0, albedo, _Metallic);

                float3 diffuse = albedo * (1.0 - _Metallic) * wrappedNdotL * lightColor * _DirectLightStrength;
                float3 specular = f0 * specTerm * wrappedNdotL * lightColor * (_SpecularStrength * _DirectLightStrength);
                float3 finalColor = diffuse + specular + albedo * ambient;

                return float4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
}
