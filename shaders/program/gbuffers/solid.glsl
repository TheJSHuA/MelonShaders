/* 
    Melon Shaders by June
    https://juniebyte.cf
*/

#include "/lib/settings.glsl"
#include "/lib/util.glsl"

// FRAGMENT SHADER //

#ifdef FRAG

/* DRAWBUFFERS:01 */
layout (location = 0) out vec4 albedoOut; // albedo output
layout (location = 1) out vec4 lmNormalMatSpecOut; // lightmap, normal map, material mask, and specular map output

// uniforms
uniform sampler2D texture;
uniform sampler2D normals;
uniform sampler2D specular;

uniform float rainStrength;
uniform float sunAngle;
uniform float viewWidth;
uniform float viewHeight;

uniform mat4 gbufferModelViewInverse;

// inputs from vertex
in float id;
in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in mat3 tbn;
in vec3 viewPos;
in vec3 normal;

in vec2 mintex;
in vec2 maxtex;

#include "/lib/dirLightmap.glsl"
#include "/lib/xbrz.glsl"

vec3 toLinear(vec3 srgb) {
    return mix(
        srgb * 0.07739938080495356, // 1.0 / 12.92 = ~0.07739938080495356
        pow(0.947867 * srgb + 0.0521327, vec3(2.4)),
        step(0.04045, srgb)
    );
}

vec4 getTangentNormals(vec2 coord) {
    vec4 normal = texture2D(normals, coord) * 2.0 - 1.0;
    return normal;
}

void main() {
    // correct floating point precision errors
    int correctedId = int(id + 0.5);

    // get specular

    vec4 specularData = texture2D(specular, texcoord);

    // get albedo

    #ifdef XBRZ_UPSCALE
    #ifndef WEATHER
    vec2 textureResolution = textureSize(texture, 0);
    vec4 albedo = four_xBRZ(textureResolution, texcoord, texture, mintex, maxtex);
    #else
    vec4 albedo = texture2D(texture, texcoord);
    #endif
    #else
    vec4 albedo = texture2D(texture, texcoord);
    #endif

    float luminance = luma(albedo);

    albedo *= glcolor;
    albedo.rgb = toLinear(albedo.rgb);
    // emissive handling
    if (EMISSIVE_MAP == 0) {
        if      (correctedId == 50 )  albedo.rgb *= clamp01(pow(luminance, 6))*60.0;
        else if (correctedId == 51 )  albedo.rgb *= clamp01(pow(luminance, 6))*75.0;
        else if (correctedId == 83 )  albedo.rgb *= clamp01(pow(luminance, 8))*62.5;
        else if (correctedId == 100)  albedo.rgb *= clamp01(pow(luminance, 8))*100.0;
        else if (correctedId == 105)  albedo.rgb *= clamp01(pow(luminance, 4))*100.0;
        else if (correctedId == 110)  albedo.rgb *= clamp01(pow(luminance, 8))*50.0;
        else if (correctedId == 120)  albedo.rgb *= 25;
        else if (correctedId == 122)  albedo.rgb *= 12.5;
    } else if (EMISSIVE_MAP == 1 && specularData.b > 0.0) {
        albedo.rgb *= clamp(specularData.b * (100*EMISSIVE_MAP_STRENGTH), 1.0, 100.0*EMISSIVE_MAP_STRENGTH);
    } else if (EMISSIVE_MAP == 2 && specularData.a < 1.0) {
        albedo.rgb *= clamp(specularData.a * (100*EMISSIVE_MAP_STRENGTH), 1.0, 100.0*EMISSIVE_MAP_STRENGTH);
    }

    #ifdef SPIDEREYES
    albedo.rgb *= 375.0;
    #endif


    // determine material mask
    
    float matMask = 0.0;
    // subsurf scattering id is 20, 21 and 23
    if (correctedId == 20 || correctedId == 21 || correctedId == 23) {
        matMask = 1.0;
    } else if (correctedId == 50||correctedId == 51||correctedId == 83||correctedId == 100||correctedId == 105||correctedId == 110||correctedId == 120||correctedId == 122) {
        // emissive material mask
        matMask = 4.0;
    } else if ((EMISSIVE_MAP == 1 && specularData.b > 0.0) || (EMISSIVE_MAP == 2 && specularData.a < 1.0)) {
        matMask = 4.0;
    }
    
    // get normals

    #ifdef NO_NORMALMAP
    vec3 normalData = normal;
    #else
    vec3 normalData = getTangentNormals(texcoord).xyz;
    normalData = normalize(normalData * tbn);
    #endif

    // get lightmap
    vec2 lm = lmcoord.xy;
    #ifdef DIRECTIONAL_LIGHTMAP
    mat3 lmtbn = getLightmapTBN(viewPos);

    lm.x = directionalLightmap(lm.x, normalData, lmtbn);
    lm.y = directionalLightmap(lm.y, normalData, lmtbn);
    #endif

    // output everything

    albedoOut = albedo;
    lmNormalMatSpecOut = vec4(
        encodeLightmaps(clamp01(lm)), 
        encodeNormals(clamp(normalData, -1.0, 1.0)), 
        encodeLightmaps(vec2(matMask/10.0, 1.0)), 
        encodeVec3(specularData.rgb)
    );
}

#endif

// VERTEX SHADER //

#ifdef VERT

// outputs to fragment
out vec2 lmcoord;
out vec2 texcoord;
out vec4 glcolor;
out mat3 tbn;
out float id;

out vec2 mintex;
out vec2 maxtex;

// uniforms
attribute vec3 mc_Entity;
attribute vec4 at_tangent;
attribute vec3 mc_midTexCoord;

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;

out vec3 normal;
out vec3 viewPos;

#include "/lib/noise.glsl"

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	glcolor = gl_Color;
    id = mc_Entity.x;

    #ifdef WIND
    vec4 position = gbufferModelViewInverse * gl_ModelViewMatrix * gl_Vertex;
    if ((mc_Entity.x == 20.0 && gl_MultiTexCoord0.t < mc_midTexCoord.t) || mc_Entity.x == 23) {
        position.xz += (sin(frameTimeCounter*cellular(position.xyz + cameraPosition)*4)/16)*WIND_STRENGTH;
    }
    gl_Position = gl_ProjectionMatrix * gbufferModelView * position;
    #else
    gl_Position = ftransform();
    #endif

    viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;

    normal   = normalize(gl_NormalMatrix * gl_Normal);
    vec3 tangent  = normalize(gl_NormalMatrix * (at_tangent.xyz));
    tbn = transpose(mat3(tangent, normalize(cross(tangent, normal)), normal));

    vec2 textureSize = abs(texcoord - mc_midTexCoord.xy);

    mintex = mc_midTexCoord.xy - textureSize;
	maxtex = mc_midTexCoord.xy + textureSize;
}

#endif