import XCTest
@testable import Greenhouse

/// The Plants tab's own logic: the "On this day" pick, tile styling and the
/// genus picker's counts.
final class PlantsTabTests: XCTestCase {
    // MARK: - On this day (pure pick)

    private struct Shot { let name: String; let at: Date }

    private func pick(_ shots: [Shot], today: Date) -> OnThisDay.Match<Shot>? {
        OnThisDay.pick(from: shots, today: today, takenAt: { $0.at }, key: { $0.name })
    }

    func testNoMatchMeansNoCard() {
        XCTAssertNil(pick([], today: day(2026, 11, 21)))
        XCTAssertNil(pick([Shot(name: "a", at: day(2025, 11, 20))], today: day(2026, 11, 21)), "other day")
        XCTAssertNil(pick([Shot(name: "a", at: day(2025, 10, 21))], today: day(2026, 11, 21)), "other month")
        XCTAssertNil(pick([Shot(name: "a", at: day(2026, 11, 21))], today: day(2026, 11, 21)), "this year isn't a throwback")
        XCTAssertNil(pick([Shot(name: "a", at: day(2027, 11, 21))], today: day(2026, 11, 21)), "the future isn't either")
    }

    func testMatchSaysHowManyYearsAgo() {
        let match = pick([Shot(name: "a", at: day(2025, 11, 21, hour: 8))], today: day(2026, 11, 21, hour: 20))
        XCTAssertEqual(match?.item.name, "a")
        XCTAssertEqual(match?.yearsAgo, 1)
        XCTAssertEqual(OnThisDay.headline(yearsAgo: 1), "1 year ago today")
        XCTAssertEqual(OnThisDay.headline(yearsAgo: 3), "3 years ago today")
    }

    func testSeveralMatchesPickTheOldestThenEarlierTimeThenKey() {
        let shots = [
            Shot(name: "b", at: day(2025, 11, 21, hour: 9)),
            Shot(name: "old", at: day(2023, 11, 21, hour: 15)),
            Shot(name: "a", at: day(2025, 11, 21, hour: 9)),
        ]
        XCTAssertEqual(pick(shots, today: day(2026, 11, 21))?.item.name, "old")
        XCTAssertEqual(pick(shots, today: day(2026, 11, 21))?.yearsAgo, 3)
        XCTAssertEqual(pick(Array(shots.reversed()), today: day(2026, 11, 21))?.item.name, "old", "order doesn't matter")

        let sameYear = [
            Shot(name: "late", at: day(2025, 11, 21, hour: 18)),
            Shot(name: "zeta", at: day(2025, 11, 21, hour: 7)),
            Shot(name: "alpha", at: day(2025, 11, 21, hour: 7)),
        ]
        XCTAssertEqual(pick(sameYear, today: day(2026, 11, 21))?.item.name, "alpha", "earlier time, then smaller key")
        XCTAssertEqual(pick(sameYear.shuffled(), today: day(2026, 11, 21))?.item.name, "alpha")
    }

    func testLeapDayPhotoShowsOnLeapDayAndFallsBackToFeb28() {
        let leapShot = [Shot(name: "leap", at: day(2024, 2, 29))]
        XCTAssertEqual(pick(leapShot, today: day(2028, 2, 29))?.yearsAgo, 4, "a leap year has the day")
        XCTAssertNil(pick(leapShot, today: day(2028, 2, 28)), "not early in a leap year")
        XCTAssertEqual(pick(leapShot, today: day(2026, 2, 28))?.yearsAgo, 2, "Feb 28 when there's no Feb 29")
        XCTAssertNil(pick(leapShot, today: day(2026, 3, 1)))
        // A real Feb 28 photo still shows on Feb 28; both can match in a common year.
        let both = leapShot + [Shot(name: "feb28", at: day(2025, 2, 28))]
        XCTAssertEqual(pick(both, today: day(2026, 2, 28))?.item.name, "leap", "oldest of the two")
        XCTAssertEqual(pick(both, today: day(2028, 2, 28))?.item.name, "feb28", "leap year: only the real Feb 28")
        XCTAssertNil(pick([Shot(name: "feb28", at: day(2025, 2, 28))], today: day(2026, 2, 27)))
    }

    func testUnusableItemsAreSkipped() {
        let shots = [Shot(name: "old", at: day(2023, 11, 21)), Shot(name: "new", at: day(2025, 11, 21))]
        let match = OnThisDay.pick(from: shots, today: day(2026, 11, 21), takenAt: { $0.at }, key: { $0.name },
                                   isUsable: { $0.name != "old" })
        XCTAssertEqual(match?.item.name, "new")
    }

    // MARK: - On this day (plants)

    func testPicksAmongActivePlantsPhotos() {
        let store = TestStore()
        let today = day(2026, 11, 21)
        let fern = store.plant(nickname: "Fern", acquired: day(2024, 1, 1), photo: true)
        let aloe = store.plant(nickname: "Aloe", acquired: day(2024, 1, 1), photo: true)
        fern.photos?.first?.takenAt = day(2025, 11, 21)
        aloe.photos?.first?.takenAt = day(2024, 11, 21)
        store.save()

        let match = OnThisDay.pick(in: [fern, aloe], today: today)
        XCTAssertEqual(match?.item.plant, aloe)
        XCTAssertEqual(match?.yearsAgo, 2)

        aloe.photos?.first?.imageData = nil
        XCTAssertEqual(OnThisDay.pick(in: [fern, aloe], today: today)?.item.plant, fern, "a photo without picture data doesn't count")
        fern.photos?.first?.takenAt = day(2025, 11, 22)
        XCTAssertNil(OnThisDay.pick(in: [fern, aloe], today: today))
    }

    func testRetiredPlantsDoNotCountButTheCombinedPlantInheritsTheirPhotos() {
        let store = TestStore()
        let a = store.plant(nickname: "A", acquired: day(2024, 1, 1), photo: true)
        let b = store.plant(nickname: "B", acquired: day(2024, 1, 1))
        a.photos?.first?.takenAt = day(2025, 11, 21)
        store.save()
        XCTAssertEqual(OnThisDay.pick(in: [a, b], today: day(2026, 11, 21))?.item.plant, a)

        let merged = Lineage.staple([a, b], nickname: "AB", household: store.household, context: store.context, persistence: store.persistence)
        store.save()
        let match = OnThisDay.pick(in: [a, b, merged], today: day(2026, 11, 21))
        XCTAssertEqual(match?.item.plant, merged, "the retired sources aren't active; the combined plant owns the photo now")
    }

    // MARK: - Tiles

    func testPhotoHeightIsStableVariedAndFromTheRange() {
        let ids = (0..<40).map { _ in UUID() }
        let heights = ids.map { PlantTileStyle.photoHeight(forID: $0) }
        XCTAssertTrue(heights.allSatisfy { PlantTileStyle.photoHeights.contains($0) })
        XCTAssertGreaterThan(Set(heights).count, 2, "heights vary")
        XCTAssertEqual(heights, ids.map { PlantTileStyle.photoHeight(forID: $0) }, "same id, same height")
        let fixed = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        XCTAssertEqual(PlantTileStyle.photoHeight(forID: fixed), PlantTileStyle.photoHeights[3])
        XCTAssertTrue(PlantTileStyle.photoHeights.contains(PlantTileStyle.photoHeight(forID: nil)))
    }

    func testWateringChipTonesAndLabels() {
        XCTAssertNil(WateringChip.make(for: nil))
        XCTAssertEqual(WateringChip.make(for: .today), WateringChip(label: "Water today", shortLabel: "Due", tone: .due))
        XCTAssertEqual(WateringChip.make(for: .upcoming(days: 1)), WateringChip(label: "Tomorrow", shortLabel: "in 1d", tone: .later))
        XCTAssertEqual(WateringChip.make(for: .upcoming(days: 4)), WateringChip(label: "In 4 days", shortLabel: "in 4d", tone: .later))
        XCTAssertEqual(WateringChip.make(for: .overdue(days: 1)), WateringChip(label: "Overdue · 1 day", shortLabel: "1d", tone: .overdue))
        XCTAssertEqual(WateringChip.make(for: .overdue(days: 3)), WateringChip(label: "Overdue · 3 days", shortLabel: "3d", tone: .overdue))
    }

    func testAvatarsAreTheOtherPeopleOnly() {
        XCTAssertEqual(PeopleAvatars.others(me: "Sam", loggers: []), [], "nobody else: avatars hidden")
        XCTAssertEqual(PeopleAvatars.others(me: "Sam", loggers: ["Sam", " sam ", "SAM"]), [], "this phone's own name is excluded")
        XCTAssertEqual(PeopleAvatars.others(me: "Sam", loggers: ["Zed", "alex", "Alex ", "Sam"]), ["Alex", "Zed"],
                       "one person per name, in a stable order")
        XCTAssertEqual(PeopleAvatars.others(me: "Sam", loggers: ["Alex", "alex"]), ["Alex"], "ties break by spelling, not input order")
        XCTAssertEqual(PeopleAvatars.others(me: "Sam", loggers: ["alex", "Alex"]), ["Alex"])
    }

    func testAvatarsDontGuessWhenThisPhonesNameIsEmpty() {
        XCTAssertEqual(PeopleAvatars.others(me: "", loggers: ["Zed", "Alex"]), [])
        XCTAssertEqual(PeopleAvatars.others(me: "  ", loggers: ["Zed"]), [])
    }

    func testAvatarSpokenLabelListsEveryone() {
        XCTAssertEqual(PeopleAvatars.spokenLabel(for: ["Alex"]), "Shared with Alex")
        XCTAssertEqual(PeopleAvatars.spokenLabel(for: ["Alex", "Sam"]), "Shared with Alex and Sam")
        let three = PeopleAvatars.spokenLabel(for: ["Alex", "Riley", "Sam"])
        XCTAssertTrue(["Alex", "Riley", "Sam"].allSatisfy { three.contains($0) }, "names everyone, however the locale joins them")
    }

    func testChipShortLabelsForNarrowTiles() {
        XCTAssertEqual(WateringChip.make(for: .overdue(days: 207))?.shortLabel, "207d")
        XCTAssertEqual(WateringChip.make(for: .today)?.shortLabel, "Due")
        XCTAssertEqual(WateringChip.make(for: .upcoming(days: 3))?.shortLabel, "in 3d")
        XCTAssertEqual(WateringChip.make(for: .upcoming(days: 1))?.shortLabel, "in 1d")
    }

    // MARK: - Masonry columns

    func testColumnsGoToTheShortestWithTheSecondStartingLower() {
        // Bottoms start at 0 and 28. Tile 0 goes left (216), 1 right (144), 2 right (260), 3 left (216 < 260).
        let heights: [CGFloat] = [200, 100, 100, 100]
        let result = MasonryColumns.assign(heights: heights, columns: 2, stagger: 28, spacing: 16)
        XCTAssertEqual(result, [[0, 3], [1, 2]])
        XCTAssertEqual(MasonryColumns.assign(heights: [50, 50, 50], columns: 2, stagger: 28, spacing: 16), [[0, 2], [1]])
        XCTAssertEqual(MasonryColumns.assign(heights: [], columns: 2, stagger: 28, spacing: 16), [[], []])
        XCTAssertEqual(MasonryColumns.assign(heights: [1, 2, 3], columns: 1, stagger: 28, spacing: 16), [[0, 1, 2]])
        XCTAssertEqual(MasonryColumns.assign(heights: [1, 2], columns: 0, stagger: 28, spacing: 16), [[0, 1]], "never fewer than one column")
    }

    func testColumnsKeepEveryTileOnceAndNeverDependOnTextSize() {
        let ids = (0..<100).map { _ in UUID() }
        let heights = ids.map { PlantTileStyle.estimatedHeight(forID: $0) }
        let result = MasonryColumns.assign(heights: heights, columns: 2, stagger: 28, spacing: 16)
        XCTAssertEqual(result.flatMap { $0 }.sorted(), Array(0..<100))
        XCTAssertEqual(result, MasonryColumns.assign(heights: heights, columns: 2, stagger: 28, spacing: 16), "deterministic")
        let left = result[0].map { heights[$0] }.reduce(0, +), right = result[1].map { heights[$0] }.reduce(0, +)
        XCTAssertLessThan(abs(left - right), 400, "columns stay roughly balanced")
        XCTAssertEqual(PlantTileStyle.estimatedHeight(forID: nil), PlantTileStyle.photoHeight(forID: nil) + PlantTileStyle.labelAllowance)
    }

    // MARK: - Genus picker

    private func plant(_ store: TestStore, latin: String?) -> Plant {
        let plant = store.plant(acquired: day(2026, 3, 1))
        plant.scientificName = latin
        return plant
    }

    func testGenusCountsAreSortedAndCountPlants() {
        let store = TestStore()
        let plants = [
            plant(store, latin: "Monstera deliciosa"), plant(store, latin: "monstera adansonii"),
            plant(store, latin: "Monstera obliqua"), plant(store, latin: "Aloe vera"), plant(store, latin: nil),
        ]
        XCTAssertEqual(PlantFilter.genusCounts(in: plants),
                       [PlantFilter.GenusCount(genus: "Aloe", count: 1), PlantFilter.GenusCount(genus: "Monstera", count: 3)])
        XCTAssertEqual(PlantFilter.genusCounts(in: plants).map(\.label), ["Aloe (1)", "Monstera (3)"])
        XCTAssertEqual(PlantFilter.genusCounts(in: []), [])
    }

    func testPickerOnlyOffersAChoiceOfTwoOrMoreGenera() {
        let store = TestStore()
        XCTAssertFalse(PlantFilter.offersGenusPicker(in: []))
        let monsteras = [plant(store, latin: "Monstera deliciosa"), plant(store, latin: "Monstera adansonii"), plant(store, latin: nil)]
        XCTAssertFalse(PlantFilter.offersGenusPicker(in: monsteras), "one genus is no choice")
        XCTAssertTrue(PlantFilter.offersGenusPicker(in: monsteras + [plant(store, latin: "Aloe vera")]))
    }
}
