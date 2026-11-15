-- open77_creator: the creator's own GPU surfaces (Open77.ui.registerEffect), used from
-- ui/creator.rcss as `decorator: fx(<name> a b c d <colour>)`. Each is a pixel function over the
-- element's box; tools/check_effects.py compiles them outside the game.
CreatorEffects = {}

-- cc-frame(cut px, border px, fill alpha, light speed): a panel with the top-left and bottom-right
-- corners cut, a night-ink fill lit from the top, a hairline in the decorator colour, a light that
-- runs around the frame and a faint scan that sweeps down.
CreatorEffects["cc-frame"] = [[
float CcFrameDistance(float2 px, float2 size, float cut)
{
    float2 q = abs(px - size * 0.5) - size * 0.5;
    float d = max(q.x, q.y);
    float tl = (cut - px.x) - px.y;
    float br = (px.x - (size.x - cut)) - (size.y - px.y);
    d = max(d, tl * 0.70710678);
    d = max(d, br * 0.70710678);
    return d;
}
float4 Effect(EffectInput e)
{
    float cut = e.params.x > 0 ? e.params.x : 20.0;
    float border = e.params.y > 0 ? e.params.y : 1.0;
    float fillAlpha = e.params.z > 0 ? e.params.z : 0.8;
    float speed = e.params.w;
    float d = CcFrameDistance(e.px, e.size, cut);
    float inside = 1.0 - smoothstep(-0.5, 0.5, d);
    float rim = (1.0 - smoothstep(border - 0.5, border + 0.5, -d)) * inside;
    float3 tint = e.color.a > 0 ? e.color.rgb / e.color.a : float3(0.13, 0.85, 0.89);
    float lit = saturate(1.0 - e.uv.y * 1.15 - e.uv.x * 0.2);
    float3 fill = lerp(float3(0.016, 0.035, 0.055), float3(0.030, 0.070, 0.098), lit);

    float turn = atan2(e.px.y - e.size.y * 0.5, e.px.x - e.size.x * 0.5) / 6.2831853 + 0.5;
    float run = frac(turn - e.time * speed * 0.05);
    float comet = speed > 0 ? pow(saturate(1.0 - run * 3.2), 3.0) : 0.0;
    float edge = saturate(rim * (0.38 + 1.25 * comet)) * e.color.a;

    float depth = max(-d, 0.0);
    float halo = (exp(-depth / 16.0) * 0.07 + exp(-depth / 46.0) * 0.10 * comet) * inside;
    float sweep = frac(e.time * 0.09);
    float band = exp(-abs(e.uv.y - sweep) * 42.0) * 0.035 * inside;

    float a = saturate(fillAlpha * inside);
    float3 rgb = fill * a + tint * (halo + band);
    rgb = rgb * (1.0 - edge) + tint * edge;
    a = saturate(a + edge + halo + band);
    return float4(rgb, a);
}
]]

-- cc-skew(slant px, border px, fill, sheen speed): a slanted button. `fill` 1 = filled with the
-- decorator colour, below 1 = night ink at that alpha under a hairline. A sheen crosses it when
-- the speed is not 0.
CreatorEffects["cc-skew"] = [[
float CcSkewDistance(float2 px, float2 size, float slant)
{
    float k = slant / max(size.y, 1.0);
    float n = 1.0 / sqrt(1.0 + k * k);
    float left = (slant - k * px.y - px.x) * n;
    float right = (px.x - (size.x - k * px.y)) * n;
    float vert = max(-px.y, px.y - size.y);
    return max(max(left, right), vert);
}
float4 Effect(EffectInput e)
{
    float slant = e.params.x > 0 ? e.params.x : 14.0;
    float border = e.params.y > 0 ? e.params.y : 1.0;
    float fillMode = e.params.z;
    float speed = e.params.w;
    float d = CcSkewDistance(e.px, e.size, slant);
    float inside = 1.0 - smoothstep(-0.5, 0.5, d);
    float rim = (1.0 - smoothstep(border - 0.5, border + 0.5, -d)) * inside;
    float3 tint = e.color.a > 0 ? e.color.rgb / e.color.a : float3(0.13, 0.85, 0.89);
    float solid = step(0.995, fillMode);

    float k = slant / max(e.size.y, 1.0);
    float along = e.px.x + k * e.px.y;
    float head = frac(e.time * speed * 0.22) * (e.size.x + 260.0) - 130.0;
    float sheen = speed > 0 ? exp(-pow((along - head) / 34.0, 2.0)) : 0.0;

    float3 ink = float3(0.018, 0.040, 0.060);
    float top = saturate(1.0 - e.uv.y);
    float3 lit = tint * (0.86 + 0.14 * top) + float3(1.0, 1.0, 1.0) * sheen * 0.32;
    float3 dark = ink + tint * (0.05 * top + sheen * 0.10);
    float fa = solid > 0 ? e.color.a : saturate(fillMode);
    float3 body = solid > 0 ? lit : dark;
    float a = fa * inside;
    float3 rgb = body * a;
    float edge = rim * e.color.a * (solid > 0 ? 0.0 : (0.75 + 0.5 * sheen));
    edge = saturate(edge);
    rgb = rgb * (1.0 - edge) + tint * edge;
    a = saturate(a + edge);
    return float4(rgb, a);
}
]]

-- cc-stripes(period px, speed, softness, _): slanted lines marching to the right; the busy state
-- of a button and the veil behind a body being rebuilt.
CreatorEffects["cc-stripes"] = [[
float4 Effect(EffectInput e)
{
    float period = e.params.x > 0 ? e.params.x : 18.0;
    float at = frac((e.px.x + e.px.y - e.time * e.params.y * period) / period);
    float soft = clamp(e.params.z, 0.02, 0.45);
    float bar = smoothstep(0.5 - soft, 0.5, at) * (1.0 - smoothstep(1.0 - soft, 1.0, at));
    return e.color * bar;
}
]]

function CreatorEffects.register()
    local ok = true
    for name, source in pairs(CreatorEffects) do
        if type(source) == "string" then
            local done, why = Open77.ui.registerEffect(name, source)
            if not done then
                ok = false
                print(("[open77_creator] effect %s refused: %s"):format(name, tostring(why)))
            end
        end
    end
    return ok
end
