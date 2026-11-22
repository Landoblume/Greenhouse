#if DEBUG
import CoreData
import SwiftUI

/// Debug builds only: the check-in camera and share card on a sample plant,
/// for screenshots (the simulator can't get to them by tapping through).
/// The sample lives in its own in-memory store, so nothing touches the real
/// household:
///
///     xcrun simctl launch booted com.landenblume.greenhouse -debugSheet shareCard
///
/// Kinds: `checkIn`, `checkInAnswered`, `shareCard`, `shareCardNight`. Also
/// under Settings → Developer.
enum DebugSampleKind: String, CaseIterable, Identifiable {
    case checkIn, checkInAnswered, shareCard, shareCardNight
    var id: String { rawValue }

    var title: String {
        switch self {
        case .checkIn: return "Check-in camera"
        case .checkInAnswered: return "Check-in, already snapped"
        case .shareCard: return "Share card (paper)"
        case .shareCardNight: return "Share card (night)"
        }
    }

    static var launchRequest: DebugSampleKind? {
        UserDefaults.standard.string(forKey: "debugSheet").flatMap(DebugSampleKind.init(rawValue:))
    }
}

/// Presents the sample the launch arguments asked for, once.
struct DebugSampleLauncher: View {
    @State private var kind = DebugSampleKind.launchRequest

    var body: some View {
        Color.clear.sheet(item: $kind) { DebugSampleSheet(kind: $0) }
    }
}

struct DebugSampleSheet: View {
    let kind: DebugSampleKind
    @State private var sample = DebugSample()

    var body: some View {
        Group {
            switch kind {
            case .checkIn:
                CheckInCameraView(plant: sample.plant, household: sample.household)
            case .checkInAnswered:
                CheckInCameraView(plant: sample.plant, household: sample.household, firedAt: sample.answeredAt)
            case .shareCard:
                ShareCardView(plant: sample.plant, style: .paper)
            case .shareCardNight:
                ShareCardView(plant: sample.plant, style: .night)
            }
        }
        .environment(\.managedObjectContext, sample.persistence.viewContext)
    }
}

/// A plant with a first photo eight months back, a recent one, and care by
/// two people (placeholder names).
struct DebugSample {
    let persistence = Persistence(inMemory: true)
    let household: Household
    let plant: Plant
    /// A check-in day the recent photo already answers.
    let answeredAt: Date

    init() {
        let context = persistence.viewContext
        let calendar = Calendar.current
        func ago(days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: .now) ?? .now }
        household = persistence.createHousehold(name: "Sample", in: context)
        let acquired = calendar.date(byAdding: .month, value: -8, to: .now) ?? .now
        plant = PlantFactory.create(scientificName: "Monstera deliciosa",
                                    species: SpeciesCatalog.shared.species(id: "monstera-deliciosa"),
                                    nickname: "Monty", acquired: acquired, location: nil, setting: .indoor,
                                    waterEvery: 7, photo: nil, now: acquired, household: household,
                                    context: context, persistence: persistence)
        if let first = Self.jpeg(named: "EmptySeedling", background: UIColor(red: 0.86, green: 0.92, blue: 0.84, alpha: 1)) {
            PlantFactory.addPhoto(first, takenAt: acquired, to: plant, household: household, context: context, persistence: persistence)
        }
        let recent = ago(days: 83)
        if let now = UIImage(named: "SampleMonstera").flatMap({ ImageTools.preparedJPEG(from: $0, maxDimension: 1200) }) {
            PlantFactory.addPhoto(now, takenAt: recent, to: plant, household: household, context: context, persistence: persistence)
        }
        answeredAt = recent
        if let water = plant.tasks?.first {
            for (index, name) in ["Alex", "Sam", "Alex", "Sam", "Alex"].enumerated() {
                CareSchedule.markDone(water, by: name, at: ago(days: 7 * (index + 1)), household: household,
                                      context: context, persistence: persistence)
            }
        }
        persistence.save(context)
    }

    /// A transparent art asset flattened onto a color, as a photo stand-in.
    private static func jpeg(named name: String, background: UIColor) -> Data? {
        guard let art = UIImage(named: name) else { return nil }
        let size = CGSize(width: 900, height: 1200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let width = size.width * 0.8
            let height = width * art.size.height / max(art.size.width, 1)
            art.draw(in: CGRect(x: (size.width - width) / 2, y: size.height - height - 40, width: width, height: height))
        }
        return image.jpegData(compressionQuality: 0.85)
    }
}
#endif
