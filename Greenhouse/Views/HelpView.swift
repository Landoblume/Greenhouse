import SwiftUI

/// "How Greenhouse works": a short guide for whoever just joined.
struct HelpView: View {
    var body: some View {
        List {
            topic("Households", "house", """
            A household is one shared set of plants. Start one, then Settings → Invite to household sends an iCloud link (Messages works). Whoever taps it sees and edits the same plants on their iPhone.

            Already added plants before joining? A card on the Plants tab offers to bring them in, photos and history included.
            """)
            topic("Adding a plant", "plus.circle", """
            Tap + on the Plants tab. Search the species list by common or Latin name; named varieties like Marble Queen pothos have their own entries. Not listed? Type the Latin name yourself.

            Add a nickname to tell look-alikes apart, take a photo, and pick where it lives and its light.
            """)
            topic("Photos", "camera", """
            On a plant's page, Add photo starts its timeline. With two or more photos, Then vs now shows the first and latest side by side.
            """)
            topic("Stapling and splitting", "arrow.triangle.branch", """
            Combined two pots? Tap Staple on the Plants tab, pick the plants, and they become one tile. Took cuttings or divided a plant? Open it and tap Split.

            Nothing is lost either way: History on each plant shows where it came from, and photos from the originals carry over.
            """)
            topic("Care reminders", "drop", """
            Every plant gets a watering schedule. Tap Watered (or Done) when it's handled and the next date moves on, with your name on it so the other phone knows.

            For anything else, like a quarterly hydrogen peroxide treatment, tap + on the Care tab. A reminder can cover several plants, or none for household chores. Reminders arrive at the time set in Settings.
            """)
            topic("Anniversaries", "gift", """
            On the day you got a plant, you'll get a "you've had it a year" note. Stapled plants count from their oldest original.
            """)
            topic("Grow zone and light", "thermometer.sun", """
            Set your ZIP in Settings to get your USDA hardiness zone. Outdoor and seasonal plants then say whether they survive winter outside where you live.

            Each plant's page shows the light you picked next to what the species likes.
            """)
            topic("Syncing", "icloud", """
            Changes show up on the other phone within about a minute while the app is open. Both phones need to be signed in to iCloud.

            If something seems stuck, Settings shows the last sync result, with a Copy details button for anything that went wrong.
            """)
        }
        .navigationTitle("How Greenhouse works")
    }

    private func topic(_ title: String, _ icon: String, _ text: String) -> some View {
        Section {
            Text(text)
                .font(.callout)
        } header: {
            Label(title, systemImage: icon)
        }
    }
}
