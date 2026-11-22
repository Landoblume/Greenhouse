import CoreData
import SwiftUI

/// Pushed by a Plants-tab tile. Other links to a plant (the throwback card,
/// a family line, a project) push the `Plant` itself, so only a tile's push
/// morphs, and only back into a tile that's there. It carries how the page's
/// hero comes in, decided by what the tap actually did (a flight or not).
struct PlantTileRoute: Hashable {
    let plant: Plant
    var entrance = PlantHero.Entrance.fadeIn
}

/// How a tile opens its plant page (HANDOFF motion table, "Tile → plant page").
enum TileMorph: Equatable {
    /// iOS 18: the system zoom grows the page out of the tile's photo, and
    /// shrinks it back on the way out.
    case zoom
    /// iOS 17 (no zoom transition): the page is pushed without the slide and
    /// a copy of the tile's photo flies up into the hero over it.
    case overlay
    /// Reduce Motion: the page is pushed without the slide and fades in.
    case crossfade

    static func style(zoomAvailable: Bool, reduceMotion: Bool, forceOverlay: Bool = false) -> TileMorph {
        if reduceMotion { return .crossfade }
        return zoomAvailable && !forceOverlay ? .zoom : .overlay
    }

    /// The style on this phone right now.
    static func current(reduceMotion: Bool) -> TileMorph {
        let zoom: Bool
        if #available(iOS 18, *) { zoom = true } else { zoom = false }
        return style(zoomAvailable: zoom, reduceMotion: reduceMotion, forceOverlay: forcesOverlay)
    }

    /// Launch a debug build with `-tileMorph overlay` to see the iOS 17 path
    /// on a newer OS (there's no iOS 17 simulator to hand).
    static var forcesOverlay: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "tileMorph") == "overlay"
        #else
        false
        #endif
    }

    /// How the page's hero comes in. The zoom carries the hero with it, so
    /// it's there at once. The overlay is the hero until it lands, so the
    /// real one waits underneath (or the photo would show twice). Under
    /// Reduce Motion the hero's own fade is the crossfade.
    var heroEntrance: PlantHero.Entrance {
        switch self {
        case .zoom: .shown
        case .overlay: .afterFlight
        case .crossfade: .fadeIn
        }
    }

    /// How long the overlay's photo takes to reach the hero: `GH.Motion.hero`.
    static let flightDuration: Double = 0.45

    /// Where the hero lands: full width at the very top of the screen (the
    /// plant page ignores the top safe area). `space` is the overlay's frame
    /// in global coordinates.
    static func heroRect(in space: CGRect, height: CGFloat = GH.PlantPage.heroHeight) -> CGRect {
        CGRect(x: -space.minX, y: -space.minY, width: space.width, height: height)
    }
}

/// Where each tile's photo is on screen, for the iOS 17 overlay. A plain
/// class: tiles write to it as they scroll without redrawing anything.
final class TileFrameStore {
    var frames: [NSManagedObjectID: CGRect] = [:]
}

/// What a tile needs to be a morph source.
struct TileMorphSource {
    let namespace: Namespace.ID
    /// Set only for the overlay style, which needs the tile's frame.
    let frames: TileFrameStore?
}

/// A tile photo on its way to the hero (iOS 17).
struct TileFlight: Equatable {
    let plantID: NSManagedObjectID
    let photo: Photo?
    /// The tile photo's frame, in global coordinates.
    let from: CGRect
    var landed = false
    var fading = false
}

/// The flying copy of the tile's photo. Like the photo viewer, it follows
/// one of two slots with `matchedGeometryEffect`, so switching the source
/// slot from the tile to the hero springs it between them.
struct TileFlightOverlay: View {
    let flight: TileFlight
    @Namespace private var space

    var body: some View {
        GeometryReader { geo in
            let global = geo.frame(in: .global)
            let from = flight.from.offsetBy(dx: -global.minX, dy: -global.minY)
            let to = TileMorph.heroRect(in: global)
            ZStack {
                // The effect goes before `position`, which would make the
                // slot as big as the screen.
                Color.clear
                    .frame(width: from.width, height: from.height)
                    .matchedGeometryEffect(id: "slot", in: space, isSource: !flight.landed)
                    .position(x: from.midX, y: from.midY)
                Color.clear
                    .frame(width: to.width, height: to.height)
                    .matchedGeometryEffect(id: "slot", in: space, isSource: flight.landed)
                    .position(x: to.midX, y: to.midY)
                // A clear base takes the slot's size; the fill photo only
                // draws over it, so it can't grow the frame.
                Color.clear
                    // The tile's own size, so the first frame reuses the
                    // tile's cached picture instead of decoding on main.
                    .overlay { TilePhotoView(photo: flight.photo, maxPixel: PlantTile.photoMaxPixel) }
                    .clipShape(RoundedRectangle(cornerRadius: flight.landed ? 0 : GH.Radius.tile, style: .continuous))
                    .matchedGeometryEffect(id: "slot", in: space, isSource: false)
            }
        }
        .opacity(flight.fading ? 0 : 1)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// The tile side of the iOS 18 zoom; nothing on iOS 17.
    @ViewBuilder
    func tileMorphSource(id: NSManagedObjectID, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18, *), let namespace {
            matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: GH.Radius.tile, style: .continuous))
            }
        } else {
            self
        }
    }

    /// The page side of the iOS 18 zoom, when `enabled`.
    @ViewBuilder
    func tileMorphDestination(id: NSManagedObjectID, in namespace: Namespace.ID, enabled: Bool) -> some View {
        if #available(iOS 18, *), enabled {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}
