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
            On a plant's page, Add photo starts its timeline. Photos from your library keep the date they were taken. With two or more photos, Then vs now shows the first and latest side by side.

            Tap a photo, then the ••• button, to fix its date, add a caption, crop it, make it the main photo on the plant's tile, or delete it. You can also crop a photo right after taking it.

            Under History, Add milestone writes down things like a new pot, a repot or a first bloom, with the date and a note. Tap one to change or delete it.
            """)
            topic("Collections", "square.stack", """
            Group plants however you like: Indoor, Outdoor greenhouse, Succulents. Tap + Collection at the top of the Plants tab, then Choose plants, or tap New collection while adding or editing a plant. A plant can be in more than one.

            Picking a collection filters the Plants, Care and Plans tabs together, so each one has its own reminders, wishlist and projects. Press and hold a collection to rename or delete it; deleting never removes plants.

            Looking for one plant? Tap the magnifying glass at the top of the Plants tab and type a name, species or where it lives. The filter button next to it shows only indoor, outdoor or seasonal plants, or the ones that need water now, and changes the order.
            """)
            topic("Plans: wishlist and projects", "list.star", """
            The wishlist holds plants you'd like, with notes like where you saw one. It shows the light each one likes and whether it survives winter in your zone. When you bring one home, tap Got it: it becomes a plant and leaves the list.

            Projects are things to build or do, like painting a new greenhouse, with an optional target date and the plants they're for. Tap the circle when it's done.
            """)
            topic("Combining and splitting", "arrow.triangle.branch", """
            Potted two plants together? Open one and tap Combine with other plants (or press and hold it on the Plants tab), pick the others, and they become one tile. Took cuttings or divided a plant? Open it and tap Split.

            To remove a plant for good, press and hold it on the Plants tab → Delete plant. Its photos and its own reminders go with it.

            Nothing is lost either way: History on each plant shows where it came from, and photos and milestones from the originals carry over.
            """)
            topic("Care reminders", "drop", """
            Every plant gets a watering schedule. Tap Watered (or Done) when it's handled and the next date moves on, with your name on it so the other phone knows.

            For anything else, like a quarterly hydrogen peroxide treatment, tap + on the Care tab. A reminder can cover several plants, or none for household chores. Reminders arrive at the time set in Settings.
            """)
            topic("Anniversaries", "gift", """
            On the day you got a plant, you'll get a "you've had it a year" note. Combined plants count from their oldest original.
            """)
            topic("Grow zone and light", "thermometer.sun", """
            Set your ZIP in Settings to get your USDA hardiness zone. Outdoor and seasonal plants then say whether they survive winter outside where you live. A ZIP too new for the USDA map gets the zone of the nearest ZIP that's on it. If even that fails, Use my location finds the zone around your phone, or you can pick one by hand.

            Each plant's page shows the light you picked next to what the species likes. Measure the light here uses the camera to estimate how bright the spot really is and says whether that suits the plant.
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
