#include <metal_stdlib>
using namespace metal;

// Рой «Восход» — порт design/loader-logo.html из GLSL ES 3.0 в MSL.
// Прототип в design/ остаётся источником истины: правки цвета и движения
// сначала туда, оттуда сюда. Числа ниже перенесены дословно, расхождения с
// прототипом — баг, а не вкусовщина.
//
// Три отличия от GLSL, все вынужденные:
//   1. clip-space z: в OpenGL диапазон [-1,1], в Metal [0,1]. Прототип пишет
//      zn*2.0-1.0, здесь — просто zn. Тест глубины тут несущий (он не даёт
//      цветам семей складываться в розовый), так что ошибка в z ломала бы
//      не порядок, а палитру.
//   2. Атрибутов нет вовсе: позиция считается из vertex_id, как и в прототипе.
//   3. texelFetch → texture.read.

struct OrbUniforms {
    float time;
    float count;
    float2 res;      // размер БУФЕРА в пикселях (не экрана и не точек)
    float zoom;
    float pt;        // размер точки в пикселях буфера
    float taper;     // во сколько раз дальняя частица мельче ближней
};

struct ResolveUniforms {
    float time;
    int   ss;        // во сколько раз буфер крупнее выхода
};

struct VOut {
    float4 position  [[position]];
    float  pointSize [[point_size]];
    float3 col;
    float  family;   // 0 — холодная семья, 1 — тёплая
};

constant float PI = 3.14159265;

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

// Восемь цветов, отобранных вручную, двумя семьями: холодная 231°–275° и
// тёплая 348°–39°. Семьи почти дополнительны, и смешивать их нельзя ничем —
// ни блендингом, ни mix(): любая середина между ними проходит через розовый,
// вычеркнутый из палитры. Отсюда весь дизайн: частица несёт ОДИН цвет из
// набора, а рой переходит из семьи в семью тем, что частицы переключаются
// поодиночке. Внутри семьи соседние тона расходятся максимум на 50°, там
// переход безопасен.
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

vertex VOut orbVertex(uint vid [[vertex_id]],
                      constant OrbUniforms &U [[buffer(0)]]) {
    VOut out;
    float i = float(vid);
    float N = U.count;

    // Решётка Фибоначчи — равномерно по сфере, без полюсных сгустков
    float k   = (i + 0.5) / N;
    float phi = acos(1.0 - 2.0 * k);
    float th  = PI * (1.0 + sqrt(5.0)) * (i + 0.5);
    float3 dir = float3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th));
    // Решётка слишком регулярна и даёт муар — сбиваем лёгким разбросом
    dir = normalize(dir + (float3(hash11(i * 3.11), hash11(i * 5.27), hash11(i * 7.43)) - 0.5) * 0.035);

    // Те самые «волны, обликом похожие на сферу»
    float t = U.time;
    float r = 1.0
        + 0.230 * sin(1.8 * dir.x + t * 0.62) * sin(2.0 * dir.y - t * 0.47)
        + 0.130 * sin(2.5 * dir.z + t * 0.55)
        + 0.070 * sin(3.3 * dir.y + 1.6 * dir.x - t * 0.80)
        + 0.040 * sin(4.6 * dir.z - 2.1 * dir.x + t * 0.65);

    // Толщина роя: частицы стоят слоем, а не идеально на поверхности
    float jitter = (hash11(i * 1.37) - 0.5) * 0.05;
    float3 pos = dir * (r + jitter);

    // Дрейф вдоль тела — рой течёт, но не расплывается в пар
    float3 flow = float3(fbm(pos * 1.3 + float3(0.0, t * 0.20, 0.0)),
                         fbm(pos * 1.3 + float3(11.0, -t * 0.16, 3.0)),
                         fbm(pos * 1.3 + float3(27.0, t * 0.12, 7.0))) - 0.5;
    pos += flow * 0.07;

    float3 obj = pos;
    pos.xz = pos.xz * rot(t * 0.30);
    pos.xy = pos.xy * rot(sin(t * 0.19) * 0.42);

    float3 ro = float3(0.0, 0.0, 3.6);
    float3 rel = pos - ro;
    float dist = -rel.z;
    float2 proj = rel.xy / (dist * 1.175) * U.zoom;
    float zn = clamp((dist - 2.2) / 2.9, 0.0, 1.0);
    // z БЕЗ пересчёта в [-1,1]: у Metal clip-space z уже [0,1].
    // Прототип на GLSL здесь пишет zn*2.0-1.0 — это его конвенция, не наша.
    out.position = float4(proj, zn, 1.0);

    // Волна с ВЫДЕРЖКАМИ: семья стоит 9 с, перетекание занимает 18 с — оно и
    // есть основное действие, а не перемычка между состояниями.
    float per  = 54.0;                     // полный цикл: синее → красное → синее
    float u    = fract(t / per);
    float tr   = 0.333;                    // доля цикла на один переход = 18 с
    float hold = 0.5 - tr;                 // выдержка одной семьи = 9 с
    float wave;
    if      (u < hold)       wave = 0.0;
    else if (u < 0.5)        wave = smoothstep(0.0, 1.0, (u - hold) / tr);
    else if (u < 0.5 + hold) wave = 1.0;
    else                     wave = 1.0 - smoothstep(0.0, 1.0, (u - 0.5 - hold) / tr);

    // Порядок переключения — поле по телу: фронт ползёт волной, а не
    // перекрашивает всё разом.
    float ord  = fbm(dir * 0.90 + float3(5.0, 0.0, 0.0));
    float ordN = clamp((ord - 0.20) / 0.40, 0.0, 1.0);
    // Зерно: у каждой частицы свой сдвиг порога, поэтому фронт не линия, а
    // полоса крупы, где синие и красные вперемешку. Это и читается «частицами».
    ordN += (hash11(i * 4.77) - 0.5) * 0.30;
    // Порог гуляет шире [0,1] — иначе на краях волны хвост частиц не дойдёт
    // до конца и рой никогда не станет чисто синим или чисто красным.
    bool isWarm = ordN < wave * 1.60 - 0.30;

    // Оттенок ВНУТРИ семьи. Частота 0.55: выше — оттенки сыплются рябью, ниже
    // 0.55 распределение перекашивается и два цвета семьи почти выпадают.
    float sh = fbm(obj * 0.55 + float3(19.0, -t * 0.17, 5.0));
    // Нормализация — по перцентилям ЭТОГО поля на ЭТОЙ частоте (p10 0.369, p90 0.616).
    float pick = clamp((sh - 0.369) / 0.246, 0.0, 0.999);
    float fidx = pick * 3.0;               // 0..3 — позиция между четырьмя цветами
    int   i0 = int(floor(fidx));
    int   i1 = min(i0 + 1, 3);
    float fr = fract(fidx);
    float edge = 0.22;                     // доля пятна, отданная под кайму
    float kEdge = smoothstep(1.0 - edge, 1.0, fr);
    // Растушёвка допустима ТОЛЬКО внутри семьи: соседи по рампе расходятся
    // максимум на 50°, их середина остаётся в семье. Через границу семей mix
    // прошёл бы ровно через розовый 300° — поэтому семья выбрана до растушёвки
    // и остаётся жёсткой.
    float3 col = isWarm ? mix(warmColor(i0), warmColor(i1), kEdge)
                        : mix(coolColor(i0), coolColor(i1), kEdge);

    // Глубина: дальние частицы тусклее — это и лепит объём вместо плоского пятна
    float depth = clamp((dist - 2.4) / 2.2, 0.0, 1.0);
    float shade = mix(1.0, 0.28, depth) * (0.78 + 0.22 * hash11(i * 2.13));
    // В буфер — ЛИНЕЙНЫЙ цвет. Палитра задана в sRGB, гамма в пост-пассе вернёт
    // ровно выбранный hex.
    out.col = pow(col, float3(2.2)) * shade;
    // Семья — в альфу. Не для прозрачности (частицы непрозрачны), а для
    // сведения: усреднять цвет можно только внутри семьи.
    out.family = isWarm ? 1.0 : 0.0;

    // Мелкие и чёткие. Крупный мягкий спрайт — это и есть «пар».
    out.pointSize = U.pt * mix(1.0, U.taper, depth);
    return out;
}

fragment float4 orbFragment(VOut in [[stage_in]],
                            float2 pc [[point_coord]]) {
    // Круглая частица с жёстким краем: размытый край читается паром.
    // Маска только режет квадрат спрайта в круг — умножать на неё цвет нельзя,
    // край уехал бы в чёрный вместо прозрачного.
    float2 d = pc - 0.5;
    if (length(d) > 0.46) discard_fragment();
    return float4(in.col, in.family);
}

struct PostOut {
    float4 position [[position]];
};

vertex PostOut postVertex(uint vid [[vertex_id]]) {
    // Полноэкранный треугольник без буфера вершин
    float2 p = float2((vid << 1) & 2, vid & 2);
    PostOut out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

// Фон в линейном виде — тот же, что уходит в clearColor.
constant float3 BG = float3(0.00021, 0.00033, 0.00160);

fragment float4 postFragment(PostOut in [[stage_in]],
                             constant ResolveUniforms &U [[buffer(0)]],
                             texture2d<float, access::read> src [[texture(0)]]) {
    // Сведение сверхвыборки — СЕМЕЙНОЕ, а не обычное среднее.
    // Обычное среднее запрещено: рядом лежат частицы двух семей, а середина
    // между 231-275° и 348-39° — розовый ~300°, вычеркнутый из палитры.
    // Побеждает семья большинства, меньшинство поглощается, фон участвует
    // только как площадь (иначе рой на кромке выцветал бы в фон).
    uint2 base = uint2(in.position.xy) * uint(U.ss);
    float3 sumC = float3(0.0), sumW = float3(0.0);
    int nC = 0, nW = 0, nB = 0;
    for (int j = 0; j < U.ss; j++) {
        for (int i = 0; i < U.ss; i++) {
            float4 t = src.read(base + uint2(uint(i), uint(j)));
            if      (t.a > 0.75) { sumW += t.rgb; nW++; }   // тёплая
            else if (t.a < 0.25) { sumC += t.rgb; nC++; }   // холодная
            else                 { nB++; }                  // фон: альфа 0.5
        }
    }
    float3 c;
    int lit = nC + nW;
    if (lit == 0) {
        c = BG;
    } else {
        bool warmWins = nW >= nC;
        float3 avg = warmWins ? sumW / float(nW) : sumC / float(nC);
        c = (avg * float(lit) + BG * float(nB)) / float(U.ss * U.ss);
    }
    // Гамма возвращает линейный цвет в sRGB — в выбранный hex буква в букву.
    c = pow(max(c, 0.0), float3(0.4545));
    // Дизер TPDF: убирает полосы на плавных переходах, стоит копейки.
    float2 fc = in.position.xy;
    float n1 = fract(sin(dot(fc, float2(12.9898, 78.233)) + U.time * 0.017) * 43758.5453);
    float n2 = fract(sin(dot(fc, float2(93.9898, 67.345)) - U.time * 0.023) * 24634.6345);
    return float4(c + (n1 + n2 - 1.0) * (2.0 / 255.0), 1.0);
}
