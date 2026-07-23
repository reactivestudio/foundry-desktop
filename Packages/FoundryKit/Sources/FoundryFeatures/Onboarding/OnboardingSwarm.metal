#include <metal_stdlib>
using namespace metal;

// Рой онбординга — порт docs/design/mockups/onboarding.html (принятый макет,
// PR #34) из GLSL ES 3.0 в MSL. Тот же материал, что Orb/OrbSwarm.metal, но с
// добавленными ручками онбординга: aspect (окно не квадратное), center/fit
// (линза и позиция орба), burst + режим линий (световые следы разлёта).
//
// Принятый Orb/OrbSwarm.metal НАРОЧНО не трогается (закон «не улучшать заодно»):
// у него своя утверждённая раскладка логотипа и лоадеров. Здесь — отдельная
// копия ядра с онбординговой хореографией. Расхождение чисел с прототипом —
// баг, а не вкус.
//
// Отличия GLSL→MSL, все вынужденные:
//   1. clip-space z: OpenGL [-1,1], Metal [0,1]. Прототип пишет zn*2-1, здесь zn.
//   2. Атрибутов нет: позиция из vertex_id.
//   3. texelFetch → texture.read; discard → discard_fragment.
//   4. Фон роя — bg.base #05030D (линейный 0.001518/0.000911/0.004025).

struct SwarmUniforms {
    float  time;
    float  count;
    float2 res;      // размер БУФЕРА в пикселях
    float  zoom;
    float  pt;       // размер точки в пикселях буфера
    float  taper;    // во сколько дальняя частица мельче ближней
    float  aspect;   // W/H канваса
    float2 center;   // позиция орба в NDC
    float  fit;      // линза: равномерное сжатие проекции вокруг центра
    float  burst;    // 0 — рой, 1 — разлетелся
    int    mode;     // 0 — точки, 1 — следы-линии
    float  step;     // шаг фазы между узлами следа
    float  jit;      // блюр хвоста: боковой сдвиг тусклой копии, px буфера
    float  t0;       // время старта разлёта (заморозка внутренней жизни)
};

struct ResolveUniforms {
    float time;
    int   ss;
};

struct VOut {
    float4 position  [[position]];
    float  pointSize [[point_size]];
    float3 col;
    float  family;   // 0 — холодная, 1 — тёплая
    float  line;     // 1 — фрагмент следа-линии (без круглой маски)
};

constant float PI = 3.14159265;
constant int   SEGS = 8;   // сегментов в следе; вершин на частицу в режиме линий — SEGS*2

static inline float2x2 rot(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(float2(c, -s), float2(s, c));
}

static inline float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

static inline float hash31(float3 p) {
    p = fract(p * 0.3183099 + float3(0.71, 0.113, 0.419));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

static inline float vnoise(float3 x) {
    float3 i = floor(x), f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash31(i + float3(0, 0, 0)), hash31(i + float3(1, 0, 0)), f.x),
                   mix(hash31(i + float3(0, 1, 0)), hash31(i + float3(1, 1, 0)), f.x), f.y),
               mix(mix(hash31(i + float3(0, 0, 1)), hash31(i + float3(1, 0, 1)), f.x),
                   mix(hash31(i + float3(0, 1, 1)), hash31(i + float3(1, 1, 1)), f.x), f.y), f.z);
}

static inline float fbm(float3 x) {
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 3; i++) { s += a * vnoise(x); x *= 2.03; a *= 0.5; }
    return s;
}

static inline float3 coolColor(int i) {
    if (i == 0) return float3(0.60, 0.20, 1.00);   // 9933FF фиолет      275°
    if (i == 1) return float3(0.36, 0.17, 1.00);   // 5B2BFF индиго      255°
    if (i == 2) return float3(0.29, 0.39, 0.97);   // 4A63F7 blue        231°
    return float3(0.27, 0.13, 0.81);               // 4522CE royal       254°
}

static inline float3 warmColor(int i) {
    if (i == 0) return float3(1.00, 0.09, 0.27);   // FF1744 малиновый   348°
    if (i == 1) return float3(1.00, 0.23, 0.19);   // FF3B30 алый          4°
    if (i == 2) return float3(1.00, 0.36, 0.24);   // FF5C3D коралл       11°
    return float3(1.00, 0.69, 0.13);               // FFB020 янтарь       39°
}

// Фон роя (нижний видимый слой окна) — временно осветлён до #241E3B
// (linear). Был bg.base #05030D (0.001518/0.000911/0.004025).
constant float3 BG_LIN = float3(0.017764, 0.012983, 0.043735);

vertex VOut swarmVertex(uint vid [[vertex_id]],
                        constant SwarmUniforms &U [[buffer(0)]]) {
    VOut out;
    // В режиме линий каждая частица занимает SEGS*2 вершин: сегмент k тянется
    // от узла k к узлу k+1, узел j — положение при фазе uBurst - j*uStep.
    int localVid = int(vid);
    float sIdx = 0.0;
    if (U.mode == 1) {
        int rest = localVid % (SEGS * 2);
        sIdx = float(rest / 2 + rest % 2);
        localVid = localVid / (SEGS * 2);
    }
    out.line = (U.mode == 1) ? 1.0 : 0.0;
    float i = float(localVid);

    // След проявляется ДЛИНОЙ, а не яркостью.
    float grow = smoothstep(0.10, 0.22, U.burst);
    float lenF = 0.6 + 0.4 * hash11(float(localVid) * 9.13);
    float bu = max(0.0, U.burst - sIdx * U.step * grow * lenF);
    float N = U.count;

    float k   = (i + 0.5) / N;
    float phi = acos(1.0 - 2.0 * k);
    float th  = PI * (1.0 + sqrt(5.0)) * (i + 0.5);
    float3 dir = float3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th));
    dir = normalize(dir + (float3(hash11(i * 3.11), hash11(i * 5.27), hash11(i * 7.43)) - 0.5) * 0.035);

    // Морфинг живёт до самого выброса; в момент рывка замораживается на uT0.
    float t = mix(U.time, U.t0, smoothstep(0.08, 0.18, U.burst));
    float r = 1.0
        + 0.230 * sin(1.8 * dir.x + t * 0.62) * sin(2.0 * dir.y - t * 0.47)
        + 0.130 * sin(2.5 * dir.z + t * 0.55)
        + 0.070 * sin(3.3 * dir.y + 1.6 * dir.x - t * 0.80)
        + 0.040 * sin(4.6 * dir.z - 2.1 * dir.x + t * 0.65);

    float jitter = (hash11(i * 1.37) - 0.5) * 0.05;
    float3 pos = dir * (r + jitter);

    float3 flow = float3(fbm(pos * 1.3 + float3(0.0, t * 0.20, 0.0)),
                         fbm(pos * 1.3 + float3(11.0, -t * 0.16, 3.0)),
                         fbm(pos * 1.3 + float3(27.0, t * 0.12, 7.0))) - 0.5;
    pos += flow * 0.07;

    float3 obj = pos;
    pos.xz = pos.xz * rot(t * 0.30);
    pos.xy = pos.xy * rot(sin(t * 0.19) * 0.42);

    // Разлёт: две части — сжатие к ядру, затем расширение за кадр по дугам.
    float bFade = 0.0;
    if (U.burst > 0.0) {
        float3 rad = normalize(pos);
        float lobe = fbm(rad * 2.6 + float3(11.0, 3.0, 7.0));
        float scAmp = 14.0 * (0.75 + 0.5 * hash11(i * 2.71)) * (0.85 + 0.3 * lobe);
        float latA  = 2.2 + 2.6 * hash11(i * 8.19);
        float3 side = normalize(float3(pos.xy, 0.0) + float3(1e-4, 0.0, 0.0));
        float SPL = 0.08;
        float del = 0.06 * hash11(i * 5.77);
        float cA  = 1.0 - 0.42 * smoothstep(0.0, SPL, bu);
        float x   = clamp((bu - SPL) / (1.0 - SPL), 0.0, 1.0);
        float xw  = max(0.0, x - del) / (1.0 - del);
        float f   = xw * xw * (1.4 - 0.4 * xw);
        float scl = cA + scAmp * f;
        if (U.mode == 1) {
            if (3.6 - pos.z < 0.34) { out.position = float4(0.0, 0.0, 2.0, 1.0);
                out.pointSize = 0.0; out.col = float3(0.0); out.family = 0.0; out.line = 0.0; return out; }
        }
        float aC = (0.55 + 0.25 * hash11(i * 3.91)) * pow(x, 0.6);
        float2 p2 = pos.xy * scl + side.xy * (f * latA);
        // GLSL mat2(cos,-sin,sin,cos) == rot(aC): крутка дуги разлёта.
        pos = float3(rot(aC) * p2, pos.z);
        bFade = xw;
    }

    float3 ro = float3(0.0, 0.0, 3.6);
    float3 rel = pos - ro;
    float dist = -rel.z;
    if (dist < 0.30) { out.position = float4(0.0, 0.0, 2.0, 1.0);
        out.pointSize = 0.0; out.col = float3(0.0); out.family = 0.0; out.line = 0.0; return out; }

    float2 proj = rel.xy / (dist * 1.175) * U.zoom;
    proj.x /= U.aspect;
    proj *= U.fit;
    proj += U.center;
    // Блюр хвоста — геометрией: тусклая копия сдвинута перпендикулярно
    // экранному направлению следа, сдвиг растёт к хвосту.
    if (U.mode == 1 && abs(U.jit) > 0.001) {
        float2 rd = proj - U.center;
        float2 perp = normalize(float2(-rd.y, rd.x) + float2(1e-5, 0.0));
        proj += perp * (U.jit * pow(sIdx / float(SEGS), 1.5) * 2.0 / U.res.y);
    }
    float zn = clamp((dist - 2.2) / 2.9, 0.0, 1.0);
    // z БЕЗ пересчёта в [-1,1]: у Metal clip-space z уже [0,1].
    out.position = float4(proj, zn, 1.0);

    float per  = 54.0;
    float u    = fract(t / per);
    float tr   = 0.333;
    float hold = 0.5 - tr;
    float wave;
    if      (u < hold)       wave = 0.0;
    else if (u < 0.5)        wave = smoothstep(0.0, 1.0, (u - hold) / tr);
    else if (u < 0.5 + hold) wave = 1.0;
    else                     wave = 1.0 - smoothstep(0.0, 1.0, (u - 0.5 - hold) / tr);

    float ord  = fbm(dir * 0.90 + float3(5.0, 0.0, 0.0));
    float ordN = clamp((ord - 0.20) / 0.40, 0.0, 1.0);
    ordN += (hash11(i * 4.77) - 0.5) * 0.30;
    bool isWarm = ordN < wave * 1.60 - 0.30;

    float sh = fbm(obj * 0.55 + float3(19.0, -t * 0.17, 5.0));
    float pick = clamp((sh - 0.369) / 0.246, 0.0, 0.999);
    float fidx = pick * 3.0;
    int   i0 = int(floor(fidx));
    int   i1 = min(i0 + 1, 3);
    float fr = fract(fidx);
    float edge = 0.22;
    float kEdge = smoothstep(1.0 - edge, 1.0, fr);
    float3 col = isWarm ? mix(warmColor(i0), warmColor(i1), kEdge)
                        : mix(coolColor(i0), coolColor(i1), kEdge);

    float depth = clamp((dist - 2.4) / 2.2, 0.0, 1.0);
    float shade = mix(1.0, 0.28, depth) * (0.78 + 0.22 * hash11(i * 2.13));
    // Гашение разлёта — по близости к камере, не по времени.
    if (U.burst > 0.0) shade *= smoothstep(0.30, 0.95, dist);
    // Вспышка отпускания.
    if (U.burst > 0.0) shade *= 1.0 + 0.22 * sin(clamp((U.burst - 0.08) / 0.09, 0.0, 1.0) * PI);
    // Угли мерцают.
    shade *= 1.0 - 0.30 * bFade * (0.5 + 0.5 * sin(t * 20.0 + i * 0.61));
    // Блики: изредка искра вспыхивает.
    shade *= 1.0 + 1.6 * bFade * pow(0.5 + 0.5 * sin(t * 9.0 + i * 7.3), 24.0);
    // След-линия: яркость спадает к хвосту.
    if (U.mode == 1) {
        float sN = sIdx / float(SEGS);
        shade *= 0.62 * pow(1.0 - sN, 2.6);
        if (abs(U.jit) > 0.001) shade *= 0.30 * smoothstep(0.15, 0.65, sN);
    }
    out.col = pow(col, float3(2.2)) * shade;
    // Хвост следа не темнее фона: пол — bg.base.
    if (U.mode == 1) out.col = max(out.col, BG_LIN);
    out.family = isWarm ? 1.0 : 0.0;

    out.pointSize = U.pt * mix(1.0, U.taper, depth) * (1.0 - 0.35 * bFade);
    return out;
}

fragment float4 swarmFragment(VOut in [[stage_in]],
                              float2 pc [[point_coord]]) {
    // Круглая маска только для точек; след-линия рисуется как есть.
    if (in.line < 0.5) {
        float2 d = pc - 0.5;
        if (length(d) > 0.46) discard_fragment();
    }
    return float4(in.col, in.family);
}

struct PostOut {
    float4 position [[position]];
};

vertex PostOut swarmPostVertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    PostOut out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

fragment float4 swarmPostFragment(PostOut in [[stage_in]],
                                  constant ResolveUniforms &U [[buffer(0)]],
                                  texture2d<float, access::read> src [[texture(0)]]) {
    // Семейное сведение сверхвыборки (обычное среднее дало бы розовый).
    uint2 base = uint2(in.position.xy) * uint(U.ss);
    float3 sumC = float3(0.0), sumW = float3(0.0);
    int nC = 0, nW = 0, nB = 0;
    for (int j = 0; j < U.ss; j++) {
        for (int i = 0; i < U.ss; i++) {
            float4 t = src.read(base + uint2(uint(i), uint(j)));
            if      (t.a > 0.75) { sumW += t.rgb; nW++; }
            else if (t.a < 0.25) { sumC += t.rgb; nC++; }
            else                 { nB++; }
        }
    }
    int lit = nC + nW;
    // Рой рисует ТОЛЬКО частицы. Фон — прозрачный: цвет даёт нижний SwiftUI-слой
    // (OB.fon). Где нет частиц — alpha 0. Где есть — premultiplied-альфа = доля
    // покрытия субпикселями (nB-субпиксели вносят прозрачность, не цвет фона).
    if (lit == 0) return float4(0.0);
    bool warmWins = nW >= nC;
    float3 avg = warmWins ? sumW / float(nW) : sumC / float(nC);  // цвет семьи (linear)
    float cov = float(lit) / float(U.ss * U.ss);
    float3 c = pow(max(avg, 0.0), float3(0.4545));  // linear→sRGB
    float2 fc = in.position.xy;
    float n1 = fract(sin(dot(fc, float2(12.9898, 78.233)) + U.time * 0.017) * 43758.5453);
    float n2 = fract(sin(dot(fc, float2(93.9898, 67.345)) - U.time * 0.023) * 24634.6345);
    c += (n1 + n2 - 1.0) * (2.0 / 255.0);
    return float4(c * cov, cov);  // premultiplied alpha
}
