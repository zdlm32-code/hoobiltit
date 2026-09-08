import SwiftUI

/// Shown once, the first time the app notices the phone is moving at road speed.
///
/// Drive mode is the one part of this app that starts on its own: `syncModeWithMotion()` flips
/// the whole screen over at about 11 mph without anyone asking for it, keeps the display awake,
/// and puts a card in front of whoever is holding the phone. That is a reasonable thing to do
/// *for a passenger*, and it had never once been said out loud — not in the app, not on the
/// website, not in the App Store listing.
///
/// So this is the moment to say it. It is also the only affirmative choice a user ever makes in
/// hoobiltit: there is no account, no onboarding and no settings screen, which makes this the
/// one place the terms can be genuinely agreed to rather than merely published.
///
/// Deliberately not a scroll of legal text. One screen, three sentences, two buttons, and it
/// never appears again.
struct DriveSafetyNotice: View {
    let onEnable: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            Image(systemName: "car.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("You're moving")
                .font(.largeTitle.bold())
                .padding(.top, 18)

            VStack(alignment: .leading, spacing: 16) {
                Row(icon: "eye.trianglebadge.exclamationmark",
                    title: "Drive mode is for the passenger",
                    detail: "It names each road as you go and keeps the screen on. If you're "
                          + "driving, don't read it and don't tap it — nothing here is worth "
                          + "your attention on the road.")
                Row(icon: "bolt.horizontal",
                    title: "It starts on its own",
                    detail: "Once you're moving at road speed, the app switches over without "
                          + "asking. You can decline now, and turn it on later from the map.")
                Row(icon: "map",
                    title: "It is not a navigation app",
                    detail: "No routing, no hazards, no speed limits. It tells you who built "
                          + "and maintains the road you're on, and nothing more.")
            }
            .padding(.top, 26)
            .padding(.horizontal, 4)

            Spacer(minLength: 20)

            VStack(spacing: 12) {
                Button(action: onEnable) {
                    Text("Turn on drive mode")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)

                Button("Not now", action: onDecline)
                    .font(.body)

                // The one place in the product where these are put in front of someone rather
                // than left on a website they will never visit.
                HStack(spacing: 4) {
                    Link("Terms of Use", destination: URL(string: "https://hoobiltit.com/terms")!)
                    Text("·").foregroundStyle(.secondary)
                    Link("Privacy", destination: URL(string: "https://hoobiltit.com/privacy")!)
                }
                .font(.footnote)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
        .multilineTextAlignment(.leading)
        .interactiveDismissDisabled()
    }

    private struct Row: View {
        let icon: String
        let title: String
        let detail: String

        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}
