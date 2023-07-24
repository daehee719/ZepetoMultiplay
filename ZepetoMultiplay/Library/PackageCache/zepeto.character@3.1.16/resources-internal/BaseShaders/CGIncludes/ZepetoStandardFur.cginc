#pragma shader_feature _ COLORGRADING_OFF //Colorgrading

#pragma shader_feature _ RIMLIGHT_DIRECTIONALFRESNEL_OFF //DIRECTIONALFRESNEL
#pragma shader_feature_local _METALLICGLOSSMAP
//#include "ZepetoStandardFurLighting.cginc"
//#include "UnityPBSLighting.cginc"
#include "ToneMapping.cginc"

	half4		_Color;

	sampler2D	_MainTex;
	float4		_MainTex_ST;

	sampler2D   _BumpMap;
	half        _BumpScale;

	sampler2D   _MetallicGlossMap;
	half        _Metallic;
	half		_Glossiness;
	half		_GlossMapScale;
	half		_GlossMapBias;

	sampler2D	_FurMap;
	half		_FurAo;
	half		_FurLength;
	half4		_FurAoColor;
	half		_FurDensity;
	half4		_Gravity;
	half		_EdgeDensity;

	half4		_RimColor;
	half		_RimPower;
	half		_RimLightMode;

	struct Input
	{
		half2 custom_MainTex_uv; //uv_MainTex
		half2 uv_FurMap;
		half3 viewDir;
		float3 worldNormal; INTERNAL_DATA
	}; 

	inline half3 GetRimLight(half3 viewDir, half3 normal,half3 albedo)
	{
		float rim = saturate(abs(dot(normalize(viewDir), normal)));
		// //handle rim light
		half3 emission = 0;
		if (_RimLightMode != 0) {				
			if (_RimLightMode == 3)
				emission = _RimColor.rgb * pow (1 - rim, _RimPower);
			else if (_RimLightMode == 2)
				emission = UNITY_LIGHTMODEL_AMBIENT.rgb * pow (1 - rim, _RimPower);
			else
				emission = albedo * pow (1 - rim, _RimPower);      	
		}
		return emission;
	}

void vert (inout appdata_full v, out Input o)
	{
		UNITY_INITIALIZE_OUTPUT(Input,o);
		const half spacing = 0.05;

		o.custom_MainTex_uv = TRANSFORM_TEX(v.texcoord.xy, _MainTex);
		half4 FurControl = tex2Dlod(_FurMap, half4(o.custom_MainTex_uv.xy,0,0)); //Fur mask offset

		half tangentSign = v.tangent.w * unity_WorldTransformParams.w;
		half3 N = normalize(v.normal);
		half3 T = normalize(v.tangent.xyz);
		half3 B = normalize(cross(N, T) * tangentSign);
		float3x3 TBN = float3x3(T, B, N);
		TBN = transpose(TBN); //Tangent

		fixed3 nm = UnpackNormal(tex2Dlod(_BumpMap, half4(o.custom_MainTex_uv.xy,0,0)));
		half3 tnormal = nm * half3(_BumpScale, _BumpScale, 1);
		half3 worldNormal = mul(TBN, tnormal); //normal

		half3 displacement = mul(unity_WorldToObject, _Gravity.xyz * pow(FUR_OFFSET * 1.5, 3) * _FurLength).xyz; 
		worldNormal.xyz += displacement * FUR_OFFSET * FurControl.b;
		half3 n = normalize(worldNormal) * FUR_OFFSET * spacing * _FurLength * FurControl.g; //Gravity

		half3 wpos = v.vertex.xyz + n; //fur offset
		v.vertex.xyz = wpos;
	}
void surf (Input IN, inout SurfaceOutputStandard o)
	{
		half4 color = tex2D(_MainTex, IN.custom_MainTex_uv) * _Color;
		half4 FurDensity = tex2D(_FurMap, IN.uv_FurMap * _FurDensity);
		half4 EdgeDensity = tex2D(_FurMap, IN.uv_FurMap * (_FurDensity - (_EdgeDensity * _FurDensity * 0.9)));
		half4 Density = lerp(EdgeDensity, FurDensity, saturate(dot(o.Normal, IN.viewDir)));
		half4 FurMask = tex2D(_FurMap, IN.custom_MainTex_uv);
		
		if (color.a <= 0 || Density.r * FurMask.g < FUR_OFFSET)
		{
			discard;
		}

		o.Albedo = color.rgb;

		half3 nm = UnpackScaleNormal(tex2D(_BumpMap, IN.custom_MainTex_uv), _BumpScale);
		o.Normal = nm * pow(half3(lerp(0.5, Density.r, _FurLength), lerp(0.5, Density.r, _FurLength), 1), 3) * half3(2, 2, 1);

		half FurAo = _FurAo * pow(_FurLength, 0.4);
		o.Albedo *= lerp(1, saturate(_FurAoColor + (1 - FurMask.g)), FurAo * pow((1 - FUR_OFFSET), 3));

		half2 mg;
		#ifdef _METALLICGLOSSMAP
			mg = tex2D(_MetallicGlossMap, IN.custom_MainTex_uv).ra;
			mg.g = mg.g * _GlossMapScale + _GlossMapBias;
		#else
			mg.r = _Metallic;
			mg.g = _Glossiness;		
		#endif

		o.Metallic = mg.r;
		
		o.Smoothness = mg.g;
		o.Smoothness *= lerp(1, saturate(_FurAoColor + (1 - FurMask.g)), FurAo * pow((1 - FUR_OFFSET), 3));
		
		half3 normal = normalize(o.Normal);
		half3 emission = GetRimLight(IN.viewDir, normal, o.Albedo);

		o.Emission = emission;
		#if !defined(RIMLIGHT_DIRECTIONALFRESNEL_OFF)
		o.Emission *= saturate(dot(WorldNormalVector (IN, o.Normal).rgb, _WorldSpaceLightPos0.xyz));
		#endif
		
		o.Alpha = 0.8 - FUR_OFFSET;
	}
void tonemapping (Input IN, SurfaceOutputStandard o, inout fixed4 color)
	{
		#if defined(COLORGRADING_OFF)
		color;
		#else
		color = ApplyColorGrading(color);
		#endif
	}