import Foundation

// The first guess, from a photo and the library's labelled photos: the one file the research loop changes
// (research/program.md). Everything it's scored by (LookStats measuring, LookMatch.evaluate, the held-out set) stays
// fixed in Look.swift. Keep `LookMatch.firstGuess(_:index:recipes:exclude:)` and `nearest` with these signatures.

extension LookStats {
    /// The numbers nearest-neighbour matching compares (scaled per index): tone shape, cast per zone, saturation per
    /// hue, how dark the saturated colours sit, grain, local contrast, black and white.
    var features: [Double] {
        let m = tone[3]
        var v = tone.enumerated().filter { $0.offset != 3 }.map { $0.element - m } + [m * 0.5, chroma, chroma90]
        v += castShadow + castMid + castHigh
        v += zip(hueChroma, hueShare).map { $0 * $1 }
        v += [saturatedL, grain, localContrast * 50, mono ? 30 : 0]
        return v
    }
}

extension LookMatch {
    public struct Neighbour: Sendable {
        public var recipe: Recipe
        public var file: String
        public var distance: Double
    }

    /// The library photos whose look is closest to `reference`, one per recipe, best first. `exclude` leaves recipes
    /// out (the evaluation leaves the one being guessed out).
    public static func nearest(_ reference: LookStats, index: LookIndex, recipes: [Recipe], count: Int = 5,
                               exclude: (Recipe) -> Bool = { _ in false }) -> [Neighbour] {
        let bySlug = Dictionary(recipes.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        let usable = index.entries.filter { e in
            guard let r = bySlug[e.slug] else { return false }
            return !exclude(r) && e.stats.mono == reference.mono
        }
        guard !usable.isEmpty else { return [] }
        let all = usable.map(\.stats.features)
        let n = all[0].count
        let mu = (0..<n).map { i in all.map { $0[i] }.reduce(0, +) / Double(all.count) }
        let sd = (0..<n).map { i in max(1e-6, (all.map { pow($0[i] - mu[i], 2) }.reduce(0, +) / Double(all.count)).squareRoot()) }
        func z(_ v: [Double]) -> [Double] { (0..<n).map { (v[$0] - mu[$0]) / sd[$0] } }
        let q = z(reference.features)
        let scored = zip(usable, all).map { e, f -> (Entry: LookIndex.Entry, d: Double) in
            let zf = z(f); return (e, zip(q, zf).map { pow($0 - $1, 2) }.reduce(0, +).squareRoot())
        }.sorted { $0.d < $1.d }
        var out: [Neighbour] = []
        for s in scored where !out.contains(where: { $0.recipe.slug == s.Entry.slug }) {
            out.append(Neighbour(recipe: bySlug[s.Entry.slug]!, file: s.Entry.file, distance: s.d))
            if out.count == count { break }
        }
        return out
    }

    /// The first guess: a blend of the recipes whose sample photos look most like the reference (film by weighted
    /// vote, numbers by weighted mean), or rules from the photo alone while the library has few sample photos.
    /// Measured on the owner's library (fuji match --evaluate) this beats the rules on every setting.
    public static func firstGuess(_ s: LookStats, index: LookIndex, recipes: [Recipe],
                                  exclude: (Recipe) -> Bool = { _ in false }) -> (settings: RecipeSettings, notes: [String], neighbours: [Neighbour]) {
        let rules = firstGuess(s)
        let nn = nearest(s, index: index, recipes: recipes, count: 5, exclude: exclude)
        guard nn.count >= 3, index.entries.count >= 15 else { return (rules.settings, rules.notes, nn) }
        let w = nn.map { 1 / ($0.distance + 0.5) }, total = w.reduce(0, +)
        func vote(_ f: (RecipeSettings) -> String) -> String {
            var t: [String: Double] = [:]
            for (n, wi) in zip(nn, w) { t[f(n.recipe.settings), default: 0] += wi }
            return t.max { $0.value < $1.value }!.key
        }
        func mean(_ f: (RecipeSettings) -> Double) -> Double { zip(nn, w).map { f($0.recipe.settings) * $1 }.reduce(0, +) / total }
        var r = RecipeSettings()
        r.film = vote(\.film)
        r.grainRoughness = vote(\.grainRoughness); r.grainSize = vote(\.grainSize)
        r.colorChrome = vote(\.colorChrome); r.colorChromeFxBlue = vote(\.colorChromeFxBlue)
        r.dynamicRange = vote(\.dynamicRange)
        r.wbRed = clamp(Int(mean { Double($0.wbRed) }.rounded()), -9, 9)
        r.wbBlue = clamp(Int(mean { Double($0.wbBlue) }.rounded()), -9, 9)
        r.highlight = halfStep(mean(\.highlight), -2, 4)
        r.shadow = halfStep(mean(\.shadow), -2, 4)
        r.sharpness = clamp(Int(mean { Double($0.sharpness) }.rounded()), -4, 4)
        r.highIsoNr = clamp(Int(mean { Double($0.highIsoNr) }.rounded()), -4, 4)
        r.clarity = clamp(Int(mean { Double($0.clarity) }.rounded()), -5, 5)
        if Film.isMonochrome(r.film) {
            r.monoWarmCool = clamp(Int(mean { Double($0.monoWarmCool ?? 0) }.rounded()), -9, 9)
            r.monoMagentaGreen = clamp(Int(mean { Double($0.monoMagentaGreen ?? 0) }.rounded()), -9, 9)
        } else {
            r.color = clamp(Int(mean { Double($0.color ?? 0) }.rounded()), -4, 4)
        }
        r.normalize()
        let names = nn.prefix(3).map(\.recipe.name).joined(separator: ", ")
        return (r, ["Blended from the library recipes whose photos look closest: \(names)."], nn)
    }

}
