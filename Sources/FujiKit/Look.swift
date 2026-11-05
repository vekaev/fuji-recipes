import CoreGraphics
import Foundation
import ImageIO

/// "Match a look": the measurable look of a photo (tone, colour cast, saturation, grain), a first-guess recipe from
/// it, and a search that lets the camera develop one of the owner's RAWs with candidate recipes and keeps the ones
/// whose look comes closest. The statistics are chosen to depend on the *look* more than on what's in the picture
/// (tone shape around the median, the colour of near-neutral pixels per tone zone), but a RAW of a similar scene and
/// light still matches best. See docs/adr/0005-match-a-look.md.
public struct LookStats: Codable, Equatable, Sendable {
    /// L* (0…100) at the 2, 10, 25, 50, 75, 90 and 98th percentiles.
    public var tone: [Double]
    /// Mean chroma (C*ab) and its 90th percentile.
    public var chroma: Double
    public var chroma90: Double
    /// Mean a*, b* of near-neutral pixels (weighted towards low chroma) in shadows (L < 35), mid tones, highlights (L > 70).
    public var castShadow: [Double]
    public var castMid: [Double]
    public var castHigh: [Double]
    /// Mean chroma per hue sector (red, orange, yellow, green, cyan, blue) and each sector's share of coloured pixels.
    public var hueChroma: [Double]
    public var hueShare: [Double]
    /// How dark the most saturated colours sit (mean L* of the top-chroma decile): Color Chrome deepens them.
    public var saturatedL: Double
    /// Pixel-level noise in flat areas (grain), and local contrast (clarity), both on a ~1500 px version of the image.
    public var grain: Double
    public var localContrast: Double
    public var mono: Bool

    // MARK: Measuring

    /// Measures an image file (JPEG, HEIC, PNG, WebP, TIFF, a RAW's embedded preview…).
    public static func measure(file: URL) throws -> LookStats {
        guard let src = CGImageSourceCreateWithURL(file as CFURL, nil) else { throw CameraError("Can't open \(file.lastPathComponent) as an image.") }
        return try measure(source: src, name: file.lastPathComponent)
    }

    public static func measure(data: Data) throws -> LookStats {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { throw CameraError("That isn't an image this Mac can read.") }
        return try measure(source: src, name: "image")
    }

    static func measure(source: CGImageSource, name: String) throws -> LookStats {
        func thumb(_ px: Int) -> CGImage? {
            CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                            kCGImageSourceCreateThumbnailWithTransform: true,
                                                            kCGImageSourceThumbnailMaxPixelSize: px] as CFDictionary)
        }
        guard let small = thumb(320) else { throw CameraError("Can't read \(name) as an image.") }
        var s = colour(Pixels(trimmed(small)))
        if let big = thumb(1000) { (s.grain, s.localContrast) = texture(Pixels(trimmed(big))) }
        return s
    }

    /// For tests and the simulated camera: measures an already-decoded image.
    public static func measure(image: CGImage) -> LookStats {
        let img = trimmed(image)
        var s = colour(Pixels(img)); (s.grain, s.localContrast) = texture(Pixels(img)); return s
    }

    /// Cuts off flat borders (Instagram's white letterbox, black frames, a caption strip of one colour).
    static func trimmed(_ image: CGImage) -> CGImage {
        let px = Pixels(image), w = px.width, h = px.height
        guard w > 16, h > 16 else { return image }
        func flat(_ idx: [Int]) -> Bool {
            var mr = 0.0, mg = 0.0, mb = 0.0
            for i in idx { mr += px.r(i); mg += px.g(i); mb += px.b(i) }
            let n = Double(idx.count); mr /= n; mg /= n; mb /= n
            var dev = 0.0
            for i in idx { dev += abs(px.r(i) - mr) + abs(px.g(i) - mg) + abs(px.b(i) - mb) }
            return dev / n < 0.03
        }
        var top = 0, bottom = h - 1, left = 0, right = w - 1
        while top < h / 3, flat((0..<w).map { top * w + $0 }) { top += 1 }
        while bottom > h * 2 / 3, flat((0..<w).map { bottom * w + $0 }) { bottom -= 1 }
        while left < w / 3, flat((top...bottom).map { $0 * w + left }) { left += 1 }
        while right > w * 2 / 3, flat((top...bottom).map { $0 * w + right }) { right -= 1 }
        guard top > 0 || left > 0 || bottom < h - 1 || right < w - 1 else { return image }
        return image.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)) ?? image
    }

    private static func colour(_ px: Pixels) -> LookStats {
        var L: [Double] = [], C: [Double] = []
        var zones = [[0.0, 0, 0], [0.0, 0, 0], [0.0, 0, 0]]   // Σw·a, Σw·b, Σw per zone, near-grey pixels only
        var loose = [[0.0, 0, 0], [0.0, 0, 0], [0.0, 0, 0]]   // every pixel, for photos with nothing grey in a zone
        var hueSum = [Double](repeating: 0, count: 6), hueN = [Double](repeating: 0, count: 6)
        var labs: [(Double, Double)] = []
        var abList: [(Double, Double)] = []
        L.reserveCapacity(px.count); C.reserveCapacity(px.count)
        for i in 0..<px.count {
            let (l, a, b) = Lab.from(px.r(i), px.g(i), px.b(i))
            let c = (a * a + b * b).squareRoot()
            L.append(l); C.append(c); labs.append((l, c))
            if l > 8 && l < 95 { abList.append((a, b)) }
            let z = l < 35 ? 0 : (l > 70 ? 2 : 1)
            if l > 3 && l < 99 {
                let w = max(0, 1 - c / 14)                                 // near-grey pixels tell the cast
                zones[z][0] += w * a; zones[z][1] += w * b; zones[z][2] += w
                let w2 = 1 / (1 + c / 6)
                loose[z][0] += w2 * a; loose[z][1] += w2 * b; loose[z][2] += w2
            }
            if c > 12 {
                var h = atan2(b, a) * 180 / .pi; if h < 0 { h += 360 }
                // red 345–20, orange 20–55, yellow 55–100, green 100–170, cyan 170–235, blue 235–345
                let sector = h < 20 || h >= 345 ? 0 : h < 55 ? 1 : h < 100 ? 2 : h < 170 ? 3 : h < 235 ? 4 : 5
                hueSum[sector] += c; hueN[sector] += 1
            }
        }
        let sortedL = L.sorted(), sortedC = C.sorted()
        func pct(_ a: [Double], _ p: Double) -> Double { a.isEmpty ? 0 : a[min(a.count - 1, Int(Double(a.count - 1) * p))] }
        let coloured = max(1, hueN.reduce(0, +))
        let n = Double(max(1, px.count))
        let cast = (0..<3).map { z -> [Double] in
            let use = zones[z][2] > n * 0.01 ? zones[z] : loose[z]
            return use[2] > 0 ? [use[0] / use[2], use[1] / use[2]] : [0.0, 0.0]
        }
        let top = labs.sorted { $0.1 > $1.1 }.prefix(max(1, labs.count / 10))
        let mean = C.reduce(0, +) / Double(max(1, C.count))
        let c90 = pct(sortedC, 0.9)
        // A toned black-and-white photo has colour, but the same colour everywhere: a*, b* barely spread.
        let ma = abList.map(\.0).reduce(0, +) / Double(max(1, abList.count)), mb = abList.map(\.1).reduce(0, +) / Double(max(1, abList.count))
        let tintSpread = (abList.map { pow($0.0 - ma, 2) + pow($0.1 - mb, 2) }.reduce(0, +) / Double(max(1, abList.count))).squareRoot()
        return LookStats(tone: [0.02, 0.10, 0.25, 0.5, 0.75, 0.9, 0.98].map { pct(sortedL, $0) },
                         chroma: mean, chroma90: c90, castShadow: cast[0], castMid: cast[1], castHigh: cast[2],
                         hueChroma: (0..<6).map { hueN[$0] > 0 ? hueSum[$0] / hueN[$0] : 0 },
                         hueShare: hueN.map { $0 / coloured },
                         saturatedL: top.map(\.0).reduce(0, +) / Double(top.count),
                         grain: 0, localContrast: 0, mono: (mean < 3 && c90 < 7) || (mean < 14 && tintSpread < 2.5))
    }

    /// Grain: the median absolute Laplacian of luminance where the image is flat (no edges). Clarity: mean difference
    /// between luminance and a 9-px box blur, relative to the image's spread.
    private static func texture(_ px: Pixels) -> (Double, Double) {
        let w = px.width, h = px.height
        guard w > 20, h > 20 else { return (0, 0) }
        var y = [Double](repeating: 0, count: w * h)
        for i in 0..<(w * h) { y[i] = 0.2126 * px.r(i) + 0.7152 * px.g(i) + 0.0722 * px.b(i) }
        var flat: [Double] = []
        var detail = 0.0, n = 0.0
        let step = max(1, (w * h) / 250_000)
        var idx = 0
        for yy in 5..<(h - 5) {
            for xx in 5..<(w - 5) {
                idx += 1; if idx % step != 0 { continue }
                let i = yy * w + xx
                let gx = y[i + 2] - y[i - 2], gy = y[i + 2 * w] - y[i - 2 * w]
                let lap = abs(4 * y[i] - y[i - 1] - y[i + 1] - y[i - w] - y[i + w])
                if abs(gx) + abs(gy) < 0.03 { flat.append(lap) }
                var box = 0.0
                for d in stride(from: -4, through: 4, by: 2) { box += y[i + d] + y[i + d * w] }
                detail += abs(y[i] - box / 10); n += 1
            }
        }
        flat.sort()
        let grain = flat.isEmpty ? 0 : flat[flat.count / 2] * 255
        let mean = y.reduce(0, +) / Double(y.count)
        let spread = max(0.05, (y.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(y.count)).squareRoot())
        return (grain, n > 0 ? detail / n / spread : 0)
    }

    // MARK: Comparing

    /// How far apart two looks are (0 = identical). Tone is compared as a shape around the median, so a brighter
    /// scene doesn't count as a different look; the median itself counts a little.
    public func distance(to o: LookStats) -> Double {
        residual(to: o).map { $0 * $0 }.reduce(0, +).squareRoot()
    }

    /// The weighted differences `distance` sums the squares of: what the camera search drives towards zero.
    public func residual(to o: LookStats) -> [Double] {
        var r: [Double] = []
        let m1 = tone[3], m2 = o.tone[3]
        for i in tone.indices where i != 3 { r.append(0.6.squareRoot() * ((tone[i] - m1) - (o.tone[i] - m2))) }
        r.append(0.15.squareRoot() * (m1 - m2))
        for (a, b) in [(castShadow, o.castShadow), (castMid, o.castMid), (castHigh, o.castHigh)] {
            r.append(1.2.squareRoot() * (a[0] - b[0])); r.append(1.2.squareRoot() * (a[1] - b[1]))
        }
        r.append(chroma - o.chroma); r.append(0.4.squareRoot() * (chroma90 - o.chroma90))
        for k in 0..<6 {   // hues both photos have enough of
            let w = min(hueShare[k], o.hueShare[k]) * 6
            r.append((0.3 * w).squareRoot() * (hueChroma[k] - o.hueChroma[k]))
        }
        r.append(mono != o.mono ? 20 : 0)
        return r
    }

    /// 0…100 for the screen: 100 identical, ~80 close, under 50 a different look.
    public func match(to o: LookStats) -> Int { Int((100 * exp(-distance(to: o) / 30)).rounded()) }
}

// MARK: First guess

public enum LookMatch {
    /// Colour films the camera search tries, and how saturated each renders at Color 0 (mean C*ab, rough).
    static let colourFilms: [(String, Double)] = [("Provia", 22), ("Velvia", 28), ("Astia", 20), ("Classic Chrome", 15),
        ("Reala Ace", 21), ("Pro Neg. Std", 16), ("Pro Neg. Hi", 18), ("Classic Neg.", 18), ("Nostalgic Neg.", 20),
        ("Eterna", 13), ("Eterna Bleach Bypass", 8)]
    static let monoFilms = ["Acros", "Acros+Ye", "Acros+R", "Acros+G", "Monochrome"]

    /// A recipe from the photo alone, no camera needed. Rough by nature: the camera search refines it.
    public static func firstGuess(_ s: LookStats) -> (settings: RecipeSettings, notes: [String]) {
        var r = RecipeSettings()
        var notes: [String] = []
        let lowSpread = s.tone[3] - s.tone[1], highSpread = s.tone[5] - s.tone[3]
        let topSqueeze = s.tone[6] - s.tone[5]
        let warmHigh = s.castHigh[1], coolShadow = s.castShadow[1]

        if s.mono {
            r.film = s.grain > 4 ? "Acros" : "Monochrome"
            // Toning: warm/cool from b*, magenta/green from a* of the mid tones.
            r.monoWarmCool = clamp(Int((s.castMid[1] / 1.5).rounded()), -9, 9)
            r.monoMagentaGreen = clamp(Int((s.castMid[0] / 1.5).rounded()), -9, 9)
            notes.append("Black and white: \(r.film); the camera search also tries the Ye, R and G filters.")
        } else {
            if s.chroma < 11 { r.film = lowSpread + highSpread > 55 ? "Classic Chrome" : "Eterna" }
            else if coolShadow < -2 && warmHigh > 3 { r.film = "Classic Neg." }
            else if warmHigh > 5 && lowSpread + highSpread < 55 { r.film = "Nostalgic Neg." }
            else if s.chroma > 26 { r.film = "Velvia" }
            else if s.chroma < 15 { r.film = "Classic Chrome" }
            else if lowSpread + highSpread < 50 { r.film = "Pro Neg. Std" }
            else { r.film = "Reala Ace" }
            let base = colourFilms.first { $0.0 == r.film }?.1 ?? 20
            r.color = clamp(Int(((s.chroma - base) / 3).rounded()), -4, 4)
            // White balance shift from the cast of near-neutral mid tones: a red step moves a*≈+1.0, b*≈+1.2;
            // a blue step a*≈+0.5, b*≈−1.6 (rough; the search corrects it).
            let a = s.castMid[0], b = s.castMid[1]
            let red = (1.6 * a + 0.5 * b) / (1.0 * 1.6 + 0.5 * 1.2)
            let blue = (1.2 * a - 1.0 * b) / (0.5 * 1.2 + 1.0 * 1.6)
            r.wbRed = clamp(Int(red.rounded()), -6, 6)
            r.wbBlue = clamp(Int(blue.rounded()), -6, 6)
            r.colorChrome = s.chroma90 > 30 && s.saturatedL < 55 ? "Strong" : s.chroma90 > 20 ? "Weak" : "Off"
            r.colorChromeFxBlue = s.hueShare[4] + s.hueShare[5] > 0.25 && s.hueChroma[5] + s.hueChroma[4] > 50 ? "Strong"
                : s.hueShare[4] + s.hueShare[5] > 0.15 ? "Weak" : "Off"
        }
        // Tone: an average photo spreads ~28 L* below the median and ~30 above (p10…p90).
        r.shadow = halfStep((lowSpread - 28) / 6, -2, 4)
        r.highlight = halfStep((highSpread - 30) / 6, -2, 4)
        if topSqueeze < 7 && s.tone[5] > 70 { r.dynamicRange = "DR400"; notes.append("Highlights roll off softly: DR400 (needs ISO 640+).") }
        else if topSqueeze < 10 && s.tone[5] > 65 { r.dynamicRange = "DR200"; notes.append("DR200 (needs ISO 320+).") }
        else { r.dynamicRange = "DR100" }
        // Grain and clarity can't be judged on the camera's 640-px previews, so they come from the photo alone.
        switch s.grain {
        case ..<1.2: break
        case ..<2.5: r.grainRoughness = "Weak"; r.grainSize = "Small"
        case ..<4.5: r.grainRoughness = "Strong"; r.grainSize = "Small"
        default: r.grainRoughness = "Strong"; r.grainSize = "Large"
        }
        r.clarity = s.localContrast < 0.1 ? -3 : s.localContrast < 0.14 ? -2 : s.localContrast > 0.3 ? 2 : 0
        r.highIsoNr = -4
        notes.append("Grain and clarity are read from the photo only: a recompressed Instagram image hides grain.")
        // Measured on the library (fuji match --evaluate), reading WB shift, tone and Color straight off a photo does
        // worse than leaving them neutral: the scene's own light and colours get in the way. So they start at zero and
        // the camera search (or the library's photos) sets them.
        if !s.mono { r.wbRed = 0; r.wbBlue = 0; r.color = 0 }
        r.highlight = 0; r.shadow = 0
        r.normalize()
        return (r, notes)
    }

    // MARK: Camera search

    public struct Candidate: Sendable {
        public var settings: RecipeSettings
        public var stats: LookStats
        public var distance: Double
        public var jpeg: Data
        public var match: Int { Int((100 * exp(-distance / 30)).rounded()) }
    }

    public struct Progress: Sendable {
        public var done: Int, budget: Int
        public var best: Candidate?
        public var stage: String
    }

    /// Searches recipes near `start` by developing them (`render` returns a JPEG) and comparing their looks with
    /// `reference`: first the film simulation, then white balance, tone and colour one at a time, with a step that
    /// halves when no direction helps. Stops at `budget` renders. Returns the best three distinct candidates.
    public static func refine(reference: LookStats, start: RecipeSettings, budget: Int = 60,
                              render: (RecipeSettings) async throws -> Data,
                              progress: (Progress) -> Void = { _ in }) async throws -> [Candidate] {
        var tried: [String: Candidate] = [:]
        var done = 0
        var best: Candidate?
        func key(_ s: RecipeSettings) -> String { RenderCache.recipeKey(s) }
        func eval(_ s0: RecipeSettings, _ stage: String) async throws -> Candidate? {
            var s = s0; s.normalize()
            if let c = tried[key(s)] { return c }
            guard done < budget else { return nil }
            try Task.checkCancellation()
            let jpeg = try await render(s)
            let stats = try LookStats.measure(data: jpeg)
            let c = Candidate(settings: s, stats: stats, distance: stats.distance(to: reference), jpeg: jpeg)
            tried[key(s)] = c; done += 1
            if best == nil || c.distance < best!.distance { best = c }
            progress(Progress(done: done, budget: budget, best: best, stage: stage))
            return c
        }

        guard let first = try await eval(start, "Your photo's first guess") else { return [] }
        // 1. Film simulation, everything else as guessed.
        var byFilm: [Candidate] = [first]
        let films = start.isMonochrome ? monoFilms : colourFilms.map(\.0)
        for f in films where f != start.film {
            var s = start; s.film = f
            if start.isMonochrome { s.monoWarmCool = start.monoWarmCool ?? 0; s.monoMagentaGreen = start.monoMagentaGreen ?? 0 }
            else { s.color = start.color ?? 0 }
            if let c = try await eval(s, "Film simulations") { byFilm.append(c) }
        }
        if start.isMonochrome {
            for f in ["Reala Ace", "Provia", "Classic Chrome"] {
                var s = RecipeSettings(); s.film = f; s.color = 0
                if let n = try await eval(s, "Film simulations") { byFilm.append(n) }
            }
        }
        byFilm.sort { $0.distance < $1.distance }
        for c in Array(byFilm.prefix(2)) {
            var s = c.settings; s.wbRed = 0; s.wbBlue = 0; s.highlight = 0; s.shadow = 0
            if s.isMonochrome { s.monoWarmCool = 0; s.monoMagentaGreen = 0 } else { s.color = 0 }
            if let n = try await eval(s, "Film simulations") { byFilm.append(n) }
        }
        byFilm.sort { $0.distance < $1.distance }
        /// One direction to move in: a single setting, or WB red and blue together (warm/cool, magenta/green), since a
        /// colour cast only moves the right way when both shift. `whole` settings take whole steps, tone half steps.
        struct Axis {
            let name: String; let step: Double; let whole: Bool
            let apply: (RecipeSettings, Double) -> RecipeSettings?      // nil when the move leaves the camera's range
        }
        func single(_ name: String, _ step: Double, _ lo: Double, _ hi: Double, whole: Bool,
                    _ get: @escaping (RecipeSettings) -> Double, _ set: @escaping (inout RecipeSettings, Double) -> Void) -> Axis {
            Axis(name: name, step: step, whole: whole) { s, d in
                let v = get(s) + d
                guard v >= lo, v <= hi else { return nil }
                var x = s; set(&x, v); return x
            }
        }
        func wb(_ name: String, _ r: Int, _ b: Int) -> Axis {
            Axis(name: name, step: 2, whole: true) { s, d in
                let k = Int(d), nr = s.wbRed + r * k, nb = s.wbBlue + b * k
                guard abs(nr) <= 9, abs(nb) <= 9 else { return nil }
                var x = s; x.wbRed = nr; x.wbBlue = nb; return x
            }
        }
        let tone = [single("Shadows", 1, -2, 4, whole: false, { $0.shadow }, { $0.shadow = $1 }),
                    single("Highlights", 1, -2, 4, whole: false, { $0.highlight }, { $0.highlight = $1 })]
        let axes: [Axis] = start.isMonochrome
            ? [single("Warm / cool", 3, -9, 9, whole: true, { Double($0.monoWarmCool ?? 0) }, { $0.monoWarmCool = Int($1) }),
               single("Magenta / green", 3, -9, 9, whole: true, { Double($0.monoMagentaGreen ?? 0) }, { $0.monoMagentaGreen = Int($1) })] + tone
            : [wb("Warm / cool", 1, -1), wb("Magenta / green", 1, 1),
               single("Color", 1, -4, 4, whole: true, { Double($0.color ?? 0) }, { $0.color = Int($1) })] + tone
               + [wb("WB red", 1, 0), wb("WB blue", 0, 1)]
        func descend(from start: Candidate, until limit: Int) async throws -> Candidate {
            var current = start
            var steps = axes.map(\.step)
            var round = 0
            while done < limit && round < 8 {
                var improved = false
                for (k, ax) in axes.enumerated() where done < limit {
                    var moved = false
                    for dir in [1.0, -1.0] {
                        guard let probe = ax.apply(current.settings, dir * steps[k]) else { continue }
                        guard let c = try await eval(probe, ax.name) else { break }
                        if c.distance < current.distance - 0.05 {
                            current = c; moved = true; improved = true
                            while done < limit, let further = ax.apply(current.settings, dir * steps[k]),
                                  let c2 = try await eval(further, ax.name), c2.distance < current.distance - 0.05 {
                                current = c2      // keep going the same way while it helps
                            }
                            break
                        }
                    }
                    if !moved { steps[k] = ax.whole ? max(1, (steps[k] / 2).rounded(.down)) : max(0.5, steps[k] / 2) }
                }
                round += 1
                if !improved && axes.indices.allSatisfy({ steps[$0] <= (axes[$0].whole ? 1 : 0.5) }) { break }
            }
            return current
        }
        // 2. Levenberg–Marquardt on the best films: measure once how each setting moves the look (one render per
        //    setting), then solve for all of them together; each step after that costs one render. The sensitivities
        //    hardly depend on the film, so they're measured on the best film and reused for the next two.
        struct Param { let step: Double; let lo: Double; let hi: Double; let quantum: Double
                       let get: (RecipeSettings) -> Double; let set: (inout RecipeSettings, Double) -> Void }
        let params: [Param] = start.isMonochrome
            ? [Param(step: 3, lo: -9, hi: 9, quantum: 1, get: { Double($0.monoWarmCool ?? 0) }, set: { $0.monoWarmCool = Int($1) }),
               Param(step: 3, lo: -9, hi: 9, quantum: 1, get: { Double($0.monoMagentaGreen ?? 0) }, set: { $0.monoMagentaGreen = Int($1) }),
               Param(step: 1, lo: -2, hi: 4, quantum: 0.5, get: { $0.highlight }, set: { $0.highlight = $1 }),
               Param(step: 1, lo: -2, hi: 4, quantum: 0.5, get: { $0.shadow }, set: { $0.shadow = $1 })]
            : [Param(step: 2, lo: -9, hi: 9, quantum: 1, get: { Double($0.wbRed) }, set: { $0.wbRed = Int($1) }),
               Param(step: 2, lo: -9, hi: 9, quantum: 1, get: { Double($0.wbBlue) }, set: { $0.wbBlue = Int($1) }),
               Param(step: 1, lo: -4, hi: 4, quantum: 1, get: { Double($0.color ?? 0) }, set: { $0.color = Int($1) }),
               Param(step: 1, lo: -2, hi: 4, quantum: 0.5, get: { $0.highlight }, set: { $0.highlight = $1 }),
               Param(step: 1, lo: -2, hi: 4, quantum: 0.5, get: { $0.shadow }, set: { $0.shadow = $1 })]
        func moved(_ s: RecipeSettings, _ i: Int, by d: Double) -> RecipeSettings {
            var x = s; let p = params[i]
            let v = min(p.hi, max(p.lo, ((p.get(s) + d) / p.quantum).rounded() * p.quantum)); p.set(&x, v); return x
        }
        var jacobian: [[Double]]?      // jacobian[i] = how the residual moves per unit of setting i
        func sensitivities(at c: Candidate) async throws -> [[Double]]? {
            let r0 = c.stats.residual(to: reference)
            var cols: [[Double]] = []
            for (i, p) in params.enumerated() {
                let dir = p.get(c.settings) + p.step <= p.hi ? p.step : -p.step
                guard let probe = try await eval(moved(c.settings, i, by: dir), "Measuring how each setting moves the look") else { return nil }
                let r1 = probe.stats.residual(to: reference)
                cols.append(zip(r1, r0).map { ($0 - $1) / dir })
            }
            return cols
        }
        func solveStep(_ J: [[Double]], _ r: [Double], lambda: Double) -> [Double] {
            let n = J.count
            var A = (0..<n).map { i in (0..<n).map { j in zip(J[i], J[j]).map(*).reduce(0, +) + (i == j ? lambda * (1 + zip(J[i], J[i]).map(*).reduce(0, +)) : 0) } }
            var g = (0..<n).map { i in -zip(J[i], r).map(*).reduce(0, +) }
            for c in 0..<n {   // Gaussian elimination with partial pivoting
                let piv = (c..<n).max { abs(A[$0][c]) < abs(A[$1][c]) }!
                A.swapAt(c, piv); g.swapAt(c, piv)
                guard abs(A[c][c]) > 1e-9 else { continue }
                for k in (c + 1)..<n where k < n {
                    let f = A[k][c] / A[c][c]
                    for j in c..<n { A[k][j] -= f * A[c][j] }
                    g[k] -= f * g[c]
                }
            }
            var x = [Double](repeating: 0, count: n)
            for c in stride(from: n - 1, through: 0, by: -1) where abs(A[c][c]) > 1e-9 {
                x[c] = (g[c] - ((c + 1)..<n).map { A[c][$0] * x[$0] }.reduce(0, +)) / A[c][c]
            }
            return x
        }
        func levenberg(from c0: Candidate, steps maxSteps: Int) async throws -> Candidate {
            var current = c0
            if jacobian == nil { jacobian = try await sensitivities(at: c0) }
            guard let J = jacobian else { return current }
            var lambda = 0.05
            for _ in 0..<maxSteps where done < budget {
                let delta = solveStep(J, current.stats.residual(to: reference), lambda: lambda)
                var next = current.settings
                for i in params.indices { next = moved(next, i, by: delta[i]) }
                if RenderCache.recipeKey(next) == RenderCache.recipeKey(current.settings) { break }
                guard let c = try await eval(next, "Solving for white balance, colour and tone") else { break }
                if c.distance < current.distance { current = c; lambda *= 0.5 } else { lambda *= 4 }
            }
            return current
        }
        // Every film gets one corrective step before they're ranked (white balance, colour and tone set right for it), so
        // a film isn't dropped only because the first guess's white balance was off; then the best two get more steps.
        jacobian = try await sensitivities(at: byFilm[0])
        var corrected: [Candidate] = []
        for c in byFilm where done < budget { corrected.append(try await levenberg(from: c, steps: 1)) }
        corrected.sort { $0.distance < $1.distance }
        var finals: [Candidate] = []
        var picks = Array(corrected.prefix(3))
        if !picks.contains(where: { $0.settings.film == start.film }), let g = corrected.first(where: { $0.settings.film == start.film }) { picks[picks.count - 1] = g }
        for c in picks where done < budget { finals.append(try await levenberg(from: c, steps: 3)) }
        // 3. Polish the best one setting at a time, with what's left of the budget. (Measured on 20 random recipes:
        //    polishing three films with a third each, or Broyden updates, did worse.)
        let ranked = finals.sorted { $0.distance < $1.distance }
        if ranked.count > 1 { _ = try await descend(from: ranked[1], until: done + (budget - done) / 2) }
        if let top = ranked.first { _ = try await descend(from: top, until: budget) }
        // Three distinct results, best first; a result that only differs by a half step from a better one is skipped.
        var out: [Candidate] = []
        for c in tried.values.sorted(by: { $0.distance < $1.distance }) {
            if out.contains(where: { $0.settings.differences(to: c.settings).count <= 1 && abs($0.distance - c.distance) < 1 }) { continue }
            out.append(c)
            if out.count == 3 { break }
        }
        return out
    }

    static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(hi, max(lo, v)) }
    static func halfStep(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, (v * 2).rounded() / 2)) }
}

// MARK: Pixels and colour

/// sRGB pixels of a CGImage, 0…1 per channel, drawn into a known colour space.
struct Pixels {
    let width: Int, height: Int
    private let data: [UInt8]
    var count: Int { width * height }

    init(_ image: CGImage) {
        let w = image.width, h = image.height
        width = w; height = h
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        buf.withUnsafeMutableBytes { p in
            if let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                   space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        data = buf
    }

    func r(_ i: Int) -> Double { Double(data[4 * i]) / 255 }
    func g(_ i: Int) -> Double { Double(data[4 * i + 1]) / 255 }
    func b(_ i: Int) -> Double { Double(data[4 * i + 2]) / 255 }
}

enum Lab {
    private static let table: [Double] = (0...255).map { v in
        let c = Double(v) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// sRGB (0…1) → CIE L*a*b* (D65).
    static func from(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let R = table[Int((r * 255).rounded())], G = table[Int((g * 255).rounded())], B = table[Int((b * 255).rounded())]
        let x = (0.4124 * R + 0.3576 * G + 0.1805 * B) / 0.95047
        let y = 0.2126 * R + 0.7152 * G + 0.0722 * B
        let z = (0.0193 * R + 0.1192 * G + 0.9505 * B) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16 / 116 }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }
}

// MARK: Saving a matched look

extension Library {
    /// Saves a matched look as a to-try recipe named `name`, with the reference photo (and the camera's render, if
    /// any) as its samples. A recipe with the same settings already in the library is returned instead.
    public func saveMatched(_ settings: RecipeSettings, name: String, reference: URL, raw: URL? = nil, match: Int? = nil,
                            render: Data? = nil, notes: [String] = []) throws -> (recipe: Recipe, existing: Bool) {
        if let twin = self.match(settings) { return (twin, true) }
        var r = Recipe(slug: "", name: name, status: "to-try", settings: settings)
        r.source = .init(kind: "manual", dateAdded: Date().day)
        r.source?.credit = "Matched from \(reference.lastPathComponent)"
        var lines = ["Matched from the look of \(reference.lastPathComponent)"
                     + (raw.map { " on \($0.lastPathComponent), developed by the camera" } ?? " (first guess from the photo, not checked on the camera)")
                     + (match.map { ": \($0)% match." } ?? ".")]
        lines += notes
        r.notes = lines.joined(separator: "\n")
        r.uncertain = raw == nil ? ["settings (estimated from a photo)"] : ["grain_roughness", "grain_size", "clarity"]
        r.tags = settings.isMonochrome ? ["B&W"] : nil
        let saved = try save(r)
        let dir = root.appendingPathComponent("samples/\(saved.slug)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: reference, to: dir.appendingPathComponent("reference." + (reference.pathExtension.isEmpty ? "jpg" : reference.pathExtension.lowercased())))
        if let render { try? render.write(to: dir.appendingPathComponent("render.jpg")) }
        return (saved, false)
    }
}

// MARK: Learning from the library

/// Every sample photo in the library, measured once, with the recipe it was shot with: the labelled data the first
/// guess learns from (nearest neighbours). Kept in `looks.json` and refreshed when photos change. It grows with
/// every recipe added, so guesses get better with the library.
public struct LookIndex: Codable, Sendable {
    public struct Entry: Codable, Sendable {
        public var slug: String
        public var file: String
        public var stamp: String          // size + modification date, to notice a changed file
        public var stats: LookStats
    }
    public var entries: [Entry] = []

    public init(entries: [Entry] = []) { self.entries = entries }

    static func url(_ library: Library) -> URL { library.root.appendingPathComponent("looks.json") }

    /// The photos that show a recipe: its samples folder (not a matched look's reference photo) and, for recipes
    /// found in the owner's own JPEGs, the photo paths listed in the recipe.
    static func photos(_ r: Recipe, library: Library) -> [URL] {
        let dir = library.root.appendingPathComponent("samples/\(r.slug)")
        let exts: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "tif", "tiff"]
        var out = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { exts.contains($0.pathExtension.lowercased()) && !$0.lastPathComponent.lowercased().hasPrefix("reference.") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for p in r.samples ?? [] {
            let u = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: u.path), !u.path.hasPrefix(dir.path) { out.append(u) }
        }
        return out
    }

    static func stamp(_ u: URL) -> String {
        let a = try? FileManager.default.attributesOfItem(atPath: u.path)
        return "\((a?[.size] as? NSNumber)?.intValue ?? 0)-\(Int((a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0))"
    }

    /// Loads the index and measures any photo that's new or changed (about 0.1–0.3 s each), dropping removed ones.
    public static func load(_ library: Library, update: Bool = true) -> LookIndex {
        var idx = (try? JSONDecoder().decode(LookIndex.self, from: Data(contentsOf: url(library)))) ?? LookIndex()
        guard update else { return idx }
        let recipes = allRecipes(library)
        let known = Dictionary(idx.entries.map { ($0.file + "|" + $0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        var fresh: [Entry] = []
        var changed = false
        for r in recipes {
            for u in photos(r, library: library) {
                let st = stamp(u)
                if let e = known[u.path + "|" + r.slug], e.stamp == st { fresh.append(e); continue }
                guard let s = try? LookStats.measure(file: u) else { continue }
                fresh.append(Entry(slug: r.slug, file: u.path, stamp: st, stats: s)); changed = true
            }
        }
        if changed || fresh.count != idx.entries.count {
            idx.entries = fresh
            if let d = try? JSONEncoder().encode(idx) { try? d.write(to: url(library), options: .atomic) }
        }
        return idx
    }
}

extension LookMatch {
    /// How well the first guess does on the library itself: each recipe's photos are guessed with that recipe (and any
    /// with identical settings) left out. Also how often a photo's own recipe comes up among the three nearest when
    /// it's left in (recognising a recipe from a new photo of it).
    public struct Evaluation: Sendable, Codable {
        public var photos = 0, recipes = 0
        public var film = 0.0, family = 0.0, mono = 0.0
        public var wbRed = 0.0, wbBlue = 0.0, highlight = 0.0, shadow = 0.0, color = 0.0
        public var recognisedFirst = 0.0, recognisedTop3 = 0.0
        public var rulesFilm = 0.0, rulesWB = 0.0
        /// One number for the research loop (higher is better): film right counts most, then the family, minus the
        /// average error of WB red, WB blue, highlight, shadow and Color (steps), plus recognising library recipes.
        public var score: Double {
            100 * film + 50 * family - 8 * (wbRed + wbBlue + highlight + shadow + color) + 30 * recognisedTop3
        }
        public var text: String {
            func p(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }
            func e(_ x: Double) -> String { String(format: "±%.1f", x) }
            return """
            \(photos) sample photos of \(recipes) recipes.
            Guessing a recipe that isn't in the library: film simulation \(p(film)) exact, \(p(family)) right family, \
            black & white \(p(mono)); off by WB red \(e(wbRed)), WB blue \(e(wbBlue)), highlights \(e(highlight)), \
            shadows \(e(shadow)), color \(e(color)). (Rules from the photo alone: film \(p(rulesFilm)), WB \(e(rulesWB)).)
            Recognising a library recipe from another photo of it: first \(p(recognisedFirst)), top three \(p(recognisedTop3)).
            """
        }
    }

    /// The research loop's fixed evaluation (research/program.md). dev: the library's own photos, each guessed with
    /// its recipe left out. heldOut: every reference set's photos (other photographers, other scenes), guessed from the
    /// library alone, so a change that only memorises the library doesn't count.
    public static func score(_ library: Library) -> (dev: Evaluation, heldOut: Evaluation, sets: [(String, Evaluation)]) {
        let index = LookIndex.load(library)
        let mine = (try? library.recipes()) ?? []
        let refs = LookIndex.referenceRecipes(library)
        let all = mine + refs
        let dev = evaluate(index: index, recipes: mine)
        let held = evaluate(index: index, recipes: all, testOn: { $0.status == "reference" }, trainOn: { $0.status != "reference" })
        let names = Array(Set(refs.compactMap { $0.source?.creator })).sorted()
        let sets = names.map { name in
            (name, evaluate(index: index, recipes: all, testOn: { $0.status == "reference" && $0.source?.creator == name }, trainOn: { $0.status != "reference" }))
        }
        return (dev, held, sets)
    }

    static let family: [String: String] = ["Classic Neg.": "warm negative", "Nostalgic Neg.": "warm negative",
        "Classic Chrome": "chrome", "Eterna": "chrome", "Eterna Bleach Bypass": "chrome", "Provia": "slide", "Velvia": "slide",
        "Astia": "slide", "Reala Ace": "slide", "Pro Neg. Std": "negative", "Pro Neg. Hi": "negative"]

    /// `testOn` picks the photos that are guessed (all by default); every photo still teaches.
    public static func evaluate(index: LookIndex, recipes: [Recipe], testOn: (Recipe) -> Bool = { _ in true },
                                trainOn: (Recipe) -> Bool = { _ in true }) -> Evaluation {
        var ev = Evaluation()
        let bySlug = Dictionary(recipes.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        let allEntries = index.entries.filter { bySlug[$0.slug] != nil && trainOn(bySlug[$0.slug]!) }
        let entries = index.entries.filter { bySlug[$0.slug] != nil && testOn(bySlug[$0.slug]!) }
        guard !entries.isEmpty else { return ev }
        ev.photos = entries.count; ev.recipes = Set(entries.map(\.slug)).count
        var colourCount = 0.0
        for e in entries {
            let truth = bySlug[e.slug]!.settings
            var t = truth; t.normalize()
            let g = firstGuess(e.stats, index: LookIndex(entries: allEntries), recipes: recipes) { r in
                var s = r.settings; s.normalize(); return r.slug == e.slug || s == t
            }.settings
            let rules = firstGuess(e.stats).settings
            ev.film += g.film == truth.film ? 1 : 0
            ev.family += (family[g.film] ?? "mono") == (family[truth.film] ?? "mono") ? 1 : 0
            ev.mono += g.isMonochrome == truth.isMonochrome ? 1 : 0
            ev.wbRed += Double(abs(g.wbRed - truth.wbRed)); ev.wbBlue += Double(abs(g.wbBlue - truth.wbBlue))
            ev.highlight += abs(g.highlight - truth.highlight); ev.shadow += abs(g.shadow - truth.shadow)
            if !truth.isMonochrome { ev.color += Double(abs((g.color ?? 0) - (truth.color ?? 0))); colourCount += 1 }
            ev.rulesFilm += rules.film == truth.film ? 1 : 0
            ev.rulesWB += Double(abs(rules.wbRed - truth.wbRed) + abs(rules.wbBlue - truth.wbBlue)) / 2
        }
        var recog = 0.0
        for e in entries where entries.filter({ $0.slug == e.slug }).count >= 2 {
            recog += 1
            let others = LookIndex(entries: allEntries.filter { $0.file != e.file || $0.slug != e.slug })
            let nn = nearest(e.stats, index: others, recipes: recipes, count: 3)
            if nn.first?.recipe.slug == e.slug { ev.recognisedFirst += 1 }
            if nn.contains(where: { $0.recipe.slug == e.slug }) { ev.recognisedTop3 += 1 }
        }
        let n = Double(entries.count)
        ev.film /= n; ev.family /= n; ev.mono /= n; ev.wbRed /= n; ev.wbBlue /= n; ev.highlight /= n; ev.shadow /= n
        ev.color /= max(1, colourCount); ev.rulesFilm /= n; ev.rulesWB /= n
        if recog > 0 { ev.recognisedFirst /= recog; ev.recognisedTop3 /= recog }
        return ev
    }
}

// MARK: Reference sets: labelled photos that aren't the owner's recipes

/// A reference set lives in `looks/<set>/` in the library: `recipes.json` (name, link, settings, photo files) and the
/// photos, downsized. Its recipes teach Match a look what each recipe looks like without appearing in Recipes; one
/// that matches can be added to the library with a tap. Collected for personal use only; never published.
public struct LookSetRecipe: Codable, Sendable {
    public var slug: String
    public var name: String
    public var url: String?
    public var settings: RecipeSettings
    public var files: [String]
}

extension LookIndex {
    static func setsDir(_ library: Library) -> URL { library.root.appendingPathComponent("looks") }

    /// Every reference set's recipes, as recipes with status "reference" (slug "ref-<set>-<slug>", photos in `samples`).
    public static func referenceRecipes(_ library: Library) -> [Recipe] {
        let dir = setsDir(library)
        let sets = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).sorted { $0.path < $1.path }
        return sets.flatMap { set -> [Recipe] in
            guard let d = try? Data(contentsOf: set.appendingPathComponent("recipes.json")),
                  let list = try? JSONDecoder().decode([LookSetRecipe].self, from: d) else { return [] }
            let label = (try? String(contentsOf: set.appendingPathComponent("NAME"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? set.lastPathComponent
            return list.map { x in
                var r = Recipe(slug: "ref-\(set.lastPathComponent)-\(x.slug)", name: x.name, status: "reference", settings: x.settings)
                r.source = .init(kind: "website", url: x.url, creator: label)
                r.samples = x.files.map { set.appendingPathComponent($0).path }
                return r
            }
        }
    }

    /// The library's recipes plus every reference set's: what Match a look learns from and suggests.
    public static func allRecipes(_ library: Library) -> [Recipe] { ((try? library.recipes()) ?? []) + referenceRecipes(library) }

    /// Imports a labelled set from JSON lines ({name, url, settings, samples: [paths]}), copying each photo at most
    /// 1000 px wide. Paths are relative to the file's folder or its parent. Returns how many recipes and photos.
    @discardableResult
    public static func importSet(jsonl: URL, name: String, into library: Library) throws -> (recipes: Int, photos: Int) {
        let text = try String(contentsOf: jsonl, encoding: .utf8)
        let folder = setsDir(library).appendingPathComponent(Recipe.slugify(name))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try name.write(to: folder.appendingPathComponent("NAME"), atomically: true, encoding: .utf8)
        var out: [LookSetRecipe] = []
        var photos = 0
        for line in text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let n = obj["name"] as? String, let sj = obj["settings"],
                  let sd = try? JSONSerialization.data(withJSONObject: sj),
                  let settings = try? JSONDecoder().decode(RecipeSettings.self, from: sd) else { continue }
            var slug = Recipe.slugify(n)
            while out.contains(where: { $0.slug == slug }) { slug += "-2" }
            var files: [String] = []
            for (i, p) in ((obj["samples"] as? [String]) ?? []).enumerated() {
                let candidates = [URL(fileURLWithPath: p), jsonl.deletingLastPathComponent().appendingPathComponent(p),
                                  jsonl.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(p)]
                guard let src = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
                      let s = CGImageSourceCreateWithURL(src as CFURL, nil),
                      let img = CGImageSourceCreateThumbnailAtIndex(s, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                           kCGImageSourceCreateThumbnailWithTransform: true,
                                                                           kCGImageSourceThumbnailMaxPixelSize: 1000] as CFDictionary) else { continue }
                let file = "\(slug)-\(i + 1).jpg"
                guard let dest = CGImageDestinationCreateWithURL(folder.appendingPathComponent(file) as CFURL, "public.jpeg" as CFString, 1, nil) else { continue }
                CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
                if CGImageDestinationFinalize(dest) { files.append(file); photos += 1 }
            }
            out.append(LookSetRecipe(slug: slug, name: n, url: obj["url"] as? String, settings: settings, files: files))
        }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(out).write(to: folder.appendingPathComponent("recipes.json"), options: .atomic)
        return (out.count, photos)
    }
}

// MARK: Benchmark: a fixed, repeatable score for the camera search

extension LookMatch {
    public struct BenchmarkCase: Sendable { public var target: RecipeSettings; public var found: RecipeSettings; public var match: Int; public var close: Bool }
    public struct Benchmark: Sendable {
        public var cases: [BenchmarkCase] = []
        public var renders = 0
        public var seconds = 0.0
        public var matched: Int { cases.filter { $0.match >= 85 }.count }
        public var recovered: Int { cases.filter(\.close).count }
        /// The single number to improve (higher is better): mean match % with a bonus for recovering the recipe.
        public var score: Double { cases.isEmpty ? 0 : Double(cases.map { $0.match + ($0.close ? 20 : 0) }.reduce(0, +)) / Double(cases.count) }
        public var text: String {
            "\(cases.count) hidden recipes: \(matched) matched at 85%+, \(recovered) recovered (right film, every setting within one step). "
            + "Score \(String(format: "%.1f", score)). \(renders) renders in \(Int(seconds)) s."
        }
    }

    /// Develops the RAW with `count` random recipes (fixed `seed`, so every run tests the same ones), hides each, and
    /// asks the search to find it from its render alone. On the simulated camera this tests the search; on the real
    /// X-E5 it measures the real thing (60 renders a case, about 2 minutes each).
    public static func benchmark(count: Int = 20, seed: UInt64 = 7, budget: Int = 60,
                                 render: (RecipeSettings) async throws -> Data, log: (String) -> Void = { _ in }) async throws -> Benchmark {
        var rng = SplitMix(seed: seed)
        let films = colourFilms.map(\.0) + ["Acros", "Acros+R"]
        var out = Benchmark()
        let start = Date()
        for i in 0..<count {
            var t = RecipeSettings()
            t.film = films[Int(rng.next() % UInt64(films.count))]
            t.wbRed = Int(rng.next() % 11) - 5; t.wbBlue = Int(rng.next() % 11) - 5
            t.highlight = Double(Int(rng.next() % 9) - 4) / 2; t.shadow = Double(Int(rng.next() % 9) - 4) / 2
            t.color = Int(rng.next() % 7) - 3
            if t.isMonochrome { t.monoWarmCool = Int(rng.next() % 11) - 5 }
            t.normalize()
            let reference = try LookStats.measure(data: try await render(t))
            var used = 0
            let found = try await refine(reference: reference, start: firstGuess(reference).settings, budget: budget) { s in used += 1; return try await render(s) }
            out.renders += used + 1
            guard let b = found.first else { continue }
            let f = b.settings
            let close = (f.film == t.film || (f.isMonochrome && t.isMonochrome))
                && (f.isMonochrome ? abs((f.monoWarmCool ?? 0) - (t.monoWarmCool ?? 0)) <= 1
                    : abs(f.wbRed - t.wbRed) <= 1 && abs(f.wbBlue - t.wbBlue) <= 1 && abs((f.color ?? 0) - (t.color ?? 0)) <= 1)
                && abs(f.highlight - t.highlight) <= 1 && abs(f.shadow - t.shadow) <= 1
            out.cases.append(BenchmarkCase(target: t, found: f, match: b.match, close: close))
            log("\(i + 1)/\(count) \(b.match)% \(close ? "✓" : "✗") hidden: \(t.summary) · found: \(f.summary)")
        }
        out.seconds = Date().timeIntervalSince(start)
        return out
    }
}

/// A tiny seeded generator so the benchmark's hidden recipes are the same on every machine and run.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
