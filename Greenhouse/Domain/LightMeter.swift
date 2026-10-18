import Foundation

/// Estimates how bright a spot is from the camera's automatic exposure, and
/// compares it with what a species likes.
///
/// iOS doesn't let apps read the ambient light sensor, but the camera picks a
/// shutter speed and ISO to expose the scene correctly, and from those the
/// standard exposure-value formula gives the light level. It's a rough
/// reading (phone cameras meter reflected light, not light falling on a leaf),
/// good for "too dim" vs "about right", not for exact numbers.
enum LightMeter {
    /// Exposure value at ISO 100: EV = log2(N² / t) − log2(ISO / 100).
    static func ev100(aperture: Double, exposureSeconds: Double, iso: Double) -> Double {
        log2(aperture * aperture / exposureSeconds) - log2(iso / 100)
    }

    /// Illuminance in lux, using the usual light-meter constant (2.5 lux at EV 0).
    static func lux(ev100: Double) -> Double {
        2.5 * pow(2, ev100)
    }

    static func lux(aperture: Double, exposureSeconds: Double, iso: Double) -> Double {
        lux(ev100: ev100(aperture: aperture, exposureSeconds: exposureSeconds, iso: iso))
    }

    /// Foot-candles, the unit most plant guides use (1 fc ≈ 10.76 lux).
    static func footCandles(lux: Double) -> Double { lux / 10.764 }

    enum Level: Equatable {
        case tooDim, aboutRight, tooBright

        var label: String {
            switch self {
            case .tooDim: "Too dim"
            case .aboutRight: "About right"
            case .tooBright: "Brighter than it likes"
            }
        }
    }

    /// Rough lux ranges for the light descriptions in the species list, from
    /// common houseplant guidance: low ≈ 50–250 fc, medium ≈ 250–1,000 fc,
    /// bright indirect ≈ 1,000–2,000 fc, direct sun ≈ 4,000 fc and up.
    static func range(for light: String) -> ClosedRange<Double>? {
        switch light.lowercased() {
        case "low to medium, indirect": 500...10_000
        case "low to bright, indirect": 500...22_000
        case "medium, indirect": 2_500...10_000
        case "bright, indirect": 10_000...22_000
        case "bright, some direct sun": 15_000...50_000
        case "full sun": 30_000...150_000
        case "part sun to part shade": 10_000...50_000
        case "shade to part shade": 2_500...22_000
        default: nil
        }
    }

    static func level(lux: Double, for light: String) -> Level? {
        guard let range = range(for: light) else { return nil }
        if lux < range.lowerBound { return .tooDim }
        if lux > range.upperBound { return .tooBright }
        return .aboutRight
    }

    /// Plain words for a reading, for when there's no species to compare with.
    static func describe(lux: Double) -> String {
        switch lux {
        case ..<500: "Very dim"
        case ..<2_500: "Low light"
        case ..<10_000: "Medium light"
        case ..<25_000: "Bright, indirect"
        default: "Direct sun"
        }
    }
}
